"""
Stage 3 — 모델 정확도 평가

지표:
  - mean_delta_e : 평균 CIE ΔE76 (낮을수록 정확)
  - capture_2    : ΔE < 2.0 픽셀 비율 (98%+ = 목표 달성)
  - capture_5    : ΔE < 5.0 픽셀 비율
  - psnr         : PSNR (dB)

실행: python 6_evaluate.py [--checkpoint path] [--n_samples 200]
"""

import argparse
import math
import numpy as np
from pathlib import Path

import torch
import torch.nn.functional as F
from PIL import Image
from tqdm import tqdm

from 3_train import ColorTransferNet, CHECKPOINT, LUT_DIM, DECODER_DIM, DEVICE


# ── 색공간 변환 ───────────────────────────────────────────────────────────────

def rgb_to_lab_np(rgb: np.ndarray) -> np.ndarray:
    """rgb: (..., 3) float32 [0,1] → Lab"""
    def linearize(c):
        return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    def f(t):
        return np.where(t > 0.008856, t ** (1/3), 7.787 * t + 16/116)

    lin = linearize(np.clip(rgb, 0, 1))
    M = np.array([[0.4124564, 0.3575761, 0.1804375],
                  [0.2126729, 0.7151522, 0.0721750],
                  [0.0193339, 0.1191920, 0.9503041]])
    xyz = lin @ M.T
    xyz_n = xyz / np.array([0.95047, 1.0, 1.08883])
    fx, fy, fz = f(xyz_n[...,0]), f(xyz_n[...,1]), f(xyz_n[...,2])
    L = 116*fy - 16
    a = 500*(fx - fy)
    b = 200*(fy - fz)
    return np.stack([L, a, b], axis=-1)


def apply_lut_np(img: np.ndarray, lut: np.ndarray) -> np.ndarray:
    """img: (H,W,3) [0,1], lut: (65,65,65,3) [0,1]"""
    dim = lut.shape[0] - 1
    r = img[..., 0] * dim
    g = img[..., 1] * dim
    b = img[..., 2] * dim
    r0 = np.clip(r.astype(int), 0, dim - 1)
    g0 = np.clip(g.astype(int), 0, dim - 1)
    b0 = np.clip(b.astype(int), 0, dim - 1)
    r1 = np.minimum(r0 + 1, dim)
    g1 = np.minimum(g0 + 1, dim)
    b1 = np.minimum(b0 + 1, dim)
    fr = (r - r0)[..., None]
    fg = (g - g0)[..., None]
    fb = (b - b0)[..., None]
    return np.clip(
        lut[r0,g0,b0]*(1-fr)*(1-fg)*(1-fb) +
        lut[r1,g0,b0]*fr*(1-fg)*(1-fb) +
        lut[r0,g1,b0]*(1-fr)*fg*(1-fb) +
        lut[r1,g1,b0]*fr*fg*(1-fb) +
        lut[r0,g0,b1]*(1-fr)*(1-fg)*fb +
        lut[r1,g0,b1]*fr*(1-fg)*fb +
        lut[r0,g1,b1]*(1-fr)*fg*fb +
        lut[r1,g1,b1]*fr*fg*fb, 0, 1)


# ── 평가 ──────────────────────────────────────────────
def upsample_lut(lut5: np.ndarray, target_dim: int = LUT_DIM) -> np.ndarray:
    """5³ LUT numpy → 65³ trilinear upsample."""
    t = torch.from_numpy(lut5).float().unsqueeze(0).permute(0,4,1,2,3)
    up = F.interpolate(t, size=(target_dim,)*3,
                       mode="trilinear", align_corners=True)
    return up.squeeze(0).permute(1,2,3,0).numpy()


def evaluate(checkpoint_path: str, n_samples: int = 200):
    # 모델 로드
    ckpt  = torch.load(checkpoint_path, map_location=DEVICE)
    model = ColorTransferNet(DECODER_DIM, LUT_DIM).to(DEVICE)
    model.load_state_dict(ckpt["model"])
    model.eval()
    print(f"모델 로드 (Val ΔE={ckpt['val_de']:.4f} @ epoch {ckpt['epoch']+1})")

    dataset_dir = Path("data/dataset")
    graded_imgs = sorted((dataset_dir / "graded").glob("*.jpg"))
    gt_lut_bins = sorted((dataset_dir / "luts").glob("*.bin"))

    n = min(n_samples, len(graded_imgs))
    indices = np.random.choice(len(graded_imgs), n, replace=False)

    all_de    = []
    all_psnr  = []
    cap2_list = []
    cap5_list = []

    print(f"\n평가 중 ({n}샘플)...")
    for idx in tqdm(indices):
        style_path  = graded_imgs[idx]
        gt_lut_path = gt_lut_bins[idx]

        # 스타일 이미지 → 모델 추론
        style_img = Image.open(style_path).convert("RGB").resize((256, 256))
        style_t   = torch.from_numpy(
            np.array(style_img, dtype=np.float32) / 255.0
        ).permute(2, 0, 1).unsqueeze(0).to(DEVICE)

        with torch.no_grad():
            lut5 = model.forward_small(style_t)   # (1,5,5,5,3)
            lut5_np = lut5[0].cpu().numpy()

        pred_lut = upsample_lut(lut5_np, LUT_DIM)  # (65,65,65,3)

        # GT LUT 로드
        gt_lut = np.fromfile(gt_lut_path, dtype=np.float16).astype(np.float32)
        gt_lut = gt_lut.reshape(LUT_DIM, LUT_DIM, LUT_DIM, 3)

        # 중립 이미지에 적용해서 비교
        neutral_path = dataset_dir / "neutral" / style_path.name
        if not neutral_path.exists():
            continue
        neutral_img = np.array(
            Image.open(neutral_path).convert("RGB"), dtype=np.float32) / 255.0

        pred_graded = apply_lut_np(neutral_img, pred_lut)
        gt_graded   = apply_lut_np(neutral_img, gt_lut)

        # ΔE 계산
        pred_lab = rgb_to_lab_np(pred_graded)
        gt_lab   = rgb_to_lab_np(gt_graded)
        de_map   = np.sqrt(np.sum((pred_lab - gt_lab) ** 2, axis=-1))

        all_de.append(de_map.mean())
        cap2_list.append((de_map < 2.0).mean())
        cap5_list.append((de_map < 5.0).mean())

        # PSNR
        mse = np.mean((pred_graded - gt_graded) ** 2)
        psnr = 10 * math.log10(1.0 / (mse + 1e-10))
        all_psnr.append(psnr)

    mean_de   = np.mean(all_de)
    mean_psnr = np.mean(all_psnr)
    mean_cap2 = np.mean(cap2_list) * 100
    mean_cap5 = np.mean(cap5_list) * 100

    print(f"\n{'='*45}")
    print(f"  평가 결과 ({n}샘플)")
    print(f"{'='*45}")
    print(f"  평균 ΔE (CIE76):     {mean_de:.3f}  {'✓' if mean_de < 2.0 else '✗'} (목표: < 2.0)")
    print(f"  PSNR:                {mean_psnr:.1f} dB")
    print(f"  ΔE < 2.0 픽셀 비율: {mean_cap2:.1f}%  {'✓' if mean_cap2 >= 98 else '✗'} (목표: ≥ 98%)")
    print(f"  ΔE < 5.0 픽셀 비율: {mean_cap5:.1f}%  {'✓' if mean_cap5 >= 90 else '✗'} (목표: ≥ 90%)")
    print(f"{'='*45}")

    if mean_de < 2.0 and mean_cap2 >= 98:
        print("\n  ✓ 98%+ 정확도 달성! 모델 배포 준비 완료.")
    else:
        print("\n  ✗ 목표 미달. 원인:")
        if mean_de >= 2.0:
            print(f"    - 평균 ΔE={mean_de:.2f} > 2.0: 데이터 증가 또는 에폭 추가")
        if mean_cap2 < 98:
            print(f"    - 캡처율 {mean_cap2:.1f}% < 98%: 다양한 스타일 LUT 추가 필요")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--checkpoint", default=CHECKPOINT)
    parser.add_argument("--n_samples",  type=int, default=200)
    args = parser.parse_args()
    evaluate(args.checkpoint, args.n_samples)
