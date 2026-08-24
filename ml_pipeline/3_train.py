"""
Stage 2 — Neural Color Transfer 학습
MobileNetV3-Small 인코더 + Progressive LUT Decoder (5³ → 65³)

수정점 (워크트리 2_train.py 대비):
  - LUT decoder를 5³ 예측 + trilinear upsample로 교체
    → Linear(1024, 823875) [843M param, VRAM 초과] 제거
    → Linear(1024, 375)   [~3M param total] 로 대체
  - 학습 VRAM: ~3.2GB → ~1.5GB (배치 4, fp16)

실행: python 3_train.py
"""

import argparse
import json
import os
import math
import numpy as np
from pathlib import Path
import subprocess
import sys

import torch
import torch.nn as nn
import torch.nn.functional as F
from torch.utils.data import Dataset, DataLoader
from torch.amp import autocast, GradScaler
import timm
from PIL import Image
from tqdm import tqdm

# ── 설정 ──────────────────────────────────────────────
PIPELINE_DIR   = Path(__file__).resolve().parent
DATASET_DIR    = PIPELINE_DIR / "data/dataset"
CHECKPOINT     = PIPELINE_DIR / "checkpoints/color_transfer.pt"
LUT_DIM       = 65          # 학습 및 저장 해상도
DECODER_DIM   = 17          # 17³=4913 → 9³의 6.7배 정밀도
BATCH_SIZE    = 4
LR            = 5e-5        # 안정적 수렴을 위해 절반으로
EPOCHS        = 60
WARMUP_STEPS  = 300
VAL_RATIO     = 0.05
N_COLOR_SAMPLES = 2000      # image-space loss용 무작위 색 샘플 수
LAMBDA        = {"image": 1.0, "smooth": 0.05}  # image-space loss로 전환
REQUIRED_LUT_KINDS = ("cube", "bin", "canon_clog2", "canon_clog3")
SOURCE_GROUP_BY_KIND = {
    "cube": "crawled",
    "bin": "app",
    "canon_clog2": "canon",
    "canon_clog3": "canon",
}
REQUIRED_SOURCE_GROUPS = ("crawled", "app", "canon")

# Must match lib/ai/models/lut_predictor.dart.
IMAGENET_MEAN = torch.tensor([0.485, 0.456, 0.406]).view(3, 1, 1)
IMAGENET_STD  = torch.tensor([0.229, 0.224, 0.225]).view(3, 1, 1)

os.makedirs(CHECKPOINT.parent, exist_ok=True)
DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")
print(f"Device: {DEVICE}")


# ── 데이터셋 ──────────────────────────────────────────
class ColorTransferDataset(Dataset):
    """Dataset generated from every required LUT source, tracked by manifest."""
    def __init__(self, root: str, require_all_sources: bool = True,
                 require_balanced_sources: bool = True):
        root_path = Path(root)
        manifest_path = root_path / "manifest.jsonl"
        if not manifest_path.exists():
            raise FileNotFoundError(
                f"{manifest_path} 없음. `python 3_train.py --prepare-dataset --clean-dataset`으로 "
                "통합 데이터셋을 새로 생성하세요."
            )

        self.samples = []
        seen_ids = set()
        for line_number, line in enumerate(manifest_path.read_text().splitlines(), start=1):
            if not line.strip():
                continue
            try:
                row = json.loads(line)
                sample_id = row["id"]
                source_lut = row["sourceLut"]
                lut_kind = row["lutKind"]
                input_domain = row["inputDomain"]
                sampling_group = row["samplingGroup"]
                sampling_mode = row["samplingMode"]
            except (json.JSONDecodeError, KeyError) as error:
                raise ValueError(
                    f"{manifest_path}:{line_number} 형식 오류 또는 이전 데이터셋입니다: {error}. "
                    "`--prepare-dataset --clean-dataset`으로 Canon sRGB 합성 데이터셋을 재생성하세요."
                ) from error

            expected_domain = "srgb_composed" if lut_kind.startswith("canon_") else "srgb"
            if input_domain != expected_domain:
                raise ValueError(
                    f"{manifest_path}:{line_number}의 {lut_kind} LUT 입력 도메인이 {input_domain!r}입니다. "
                    f"{expected_domain!r} 데이터셋을 다시 생성하세요."
                )
            if sampling_group != SOURCE_GROUP_BY_KIND[lut_kind]:
                raise ValueError(
                    f"{manifest_path}:{line_number}의 samplingGroup이 LUT 출처와 맞지 않습니다. "
                    "데이터셋을 다시 생성하세요."
                )

            if sample_id in seen_ids:
                raise ValueError(f"{manifest_path}:{line_number} 중복 sample id: {sample_id}")
            seen_ids.add(sample_id)
            style_path = root_path / "graded" / f"{sample_id}.jpg"
            lut_path = root_path / "luts" / f"{sample_id}.bin"
            if not style_path.exists() or not lut_path.exists():
                raise FileNotFoundError(
                    f"manifest 샘플 {sample_id}의 graded/LUT 파일이 없습니다. "
                    "--clean-dataset으로 다시 생성하세요."
                )
            self.samples.append({
                "style": style_path,
                "lut": lut_path,
                "source_lut": source_lut,
                "lut_kind": lut_kind,
                "sampling_group": sampling_group,
                "sampling_mode": sampling_mode,
            })

        if not self.samples:
            raise ValueError(f"{manifest_path}에 유효한 학습 샘플이 없습니다.")

        self.counts_by_kind = {
            kind: sum(sample["lut_kind"] == kind for sample in self.samples)
            for kind in REQUIRED_LUT_KINDS
        }
        self.counts_by_group = {
            group: sum(sample["sampling_group"] == group for sample in self.samples)
            for group in REQUIRED_SOURCE_GROUPS
        }
        if require_all_sources:
            missing = [kind for kind, count in self.counts_by_kind.items() if count == 0]
            if missing:
                raise ValueError(
                    "통합 학습 데이터셋에 누락된 LUT 소스: " + ", ".join(missing) +
                    ". `--prepare-dataset --clean-dataset`으로 재생성하세요."
                )
        if require_balanced_sources:
            modes = {sample["sampling_mode"] for sample in self.samples}
            if modes != {"balanced_source"}:
                raise ValueError(
                    "균형 샘플링 데이터셋이 아닙니다. "
                    "`--prepare-dataset --clean-dataset`으로 다시 생성하세요."
                )
            if max(self.counts_by_group.values()) - min(self.counts_by_group.values()) > 1:
                raise ValueError(
                    f"소스별 학습 쌍이 불균형합니다: {self.counts_by_group}. "
                    "`--prepare-dataset --clean-dataset`으로 다시 생성하세요."
                )

        self.lut_sources = sorted({sample["source_lut"] for sample in self.samples})

    def __len__(self):
        return len(self.samples)

    def __getitem__(self, idx):
        sample = self.samples[idx]
        style = Image.open(sample["style"]).convert("RGB")
        style = torch.from_numpy(np.array(style, dtype=np.float32) / 255.0)
        style = style.permute(2, 0, 1)  # (3, H, W)
        style = (style - IMAGENET_MEAN) / IMAGENET_STD

        lut = np.fromfile(sample["lut"], dtype=np.float16).astype(np.float32)
        lut = torch.from_numpy(lut).reshape(LUT_DIM, LUT_DIM, LUT_DIM, 3)
        return style, lut


# ── 모델 ──────────────────────────────────────────────
class ColorTransferNet(nn.Module):
    """
    MobileNetV3-Small → Color Head → 5³ LUT → (학습 시) trilinear upsample → 65³
    TFLite export 시 5³ 출력, Dart 앱에서 65³ 업샘플.
    총 파라미터 ~3M (원본 대비 280배 감소, VRAM 1.5GB 절감).
    """
    def __init__(self, decoder_dim: int = 5, lut_dim: int = 65):
        super().__init__()
        self.decoder_dim = decoder_dim
        self.lut_dim     = lut_dim

        self.encoder = timm.create_model(
            "mobilenetv3_small_100",
            pretrained=True,
            num_classes=0,
            global_pool="avg",
        )
        # timm 버전마다 num_features가 다를 수 있으므로 dummy forward로 실제 크기 감지
        with torch.no_grad():
            feat_dim = self.encoder(torch.zeros(1, 3, 256, 256)).shape[-1]

        self.color_head = nn.Sequential(
            nn.Linear(feat_dim, 256), nn.SiLU(), nn.Dropout(0.1),
            nn.Linear(256, 512),      nn.SiLU(),
        )

        # Small LUT 예측: decoder_dim³ × 3 출력
        self.lut_decoder = nn.Sequential(
            nn.Linear(512, 1024), nn.SiLU(),
            nn.Linear(1024, decoder_dim ** 3 * 3),
            nn.Sigmoid(),
        )

        self._init_identity()

    def _init_identity(self):
        """identity LUT으로 초기화 — 학습 초기 안정성 향상."""
        coords = torch.linspace(0, 1, self.decoder_dim)
        r, g, b = torch.meshgrid(coords, coords, coords, indexing="ij")
        identity = torch.stack([r, g, b], dim=-1).reshape(-1)
        with torch.no_grad():
            last_linear = self.lut_decoder[-2]  # Linear before Sigmoid
            nn.init.zeros_(last_linear.weight)
            last_linear.bias.data = torch.logit(identity.clamp(1e-4, 1 - 1e-4))

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        """
        x: (B, 3, 256, 256)
        returns: (B, lut_dim, lut_dim, lut_dim, 3) — 65³ LUT
        """
        feat  = self.encoder(x)                                       # (B, 576)
        feat  = self.color_head(feat)                                  # (B, 512)
        lut_s = self.lut_decoder(feat)                                 # (B, decoder_dim³×3)
        lut_s = lut_s.reshape(-1, self.decoder_dim, self.decoder_dim,
                              self.decoder_dim, 3)                     # (B, 5,5,5, 3)

        # trilinear upsample: (B,3,5,5,5) → (B,3,65,65,65) → (B,65,65,65,3)
        lut65 = F.interpolate(
            lut_s.permute(0, 4, 1, 2, 3),
            size=(self.lut_dim,) * 3,
            mode="trilinear",
            align_corners=True,
        ).permute(0, 2, 3, 4, 1)                                      # (B,65,65,65,3)

        return lut65

    def forward_small(self, x: torch.Tensor) -> torch.Tensor:
        """TFLite export용: decoder_dim³ 출력만 반환 (업샘플 없음)."""
        feat  = self.encoder(x)
        feat  = self.color_head(feat)
        lut_s = self.lut_decoder(feat)
        return lut_s.reshape(-1, self.decoder_dim, self.decoder_dim,
                             self.decoder_dim, 3)


# ── Loss ──────────────────────────────────────────────
def rgb_to_lab(rgb: torch.Tensor) -> torch.Tensor:
    mask   = rgb > 0.04045
    linear = torch.where(mask, ((rgb + 0.055) / 1.055) ** 2.4, rgb / 12.92)
    M = torch.tensor([
        [0.4124564, 0.3575761, 0.1804375],
        [0.2126729, 0.7151522, 0.0721750],
        [0.0193339, 0.1191920, 0.9503041],
    ], device=rgb.device, dtype=rgb.dtype)
    xyz   = linear @ M.T
    xyz_n = xyz / torch.tensor([0.95047, 1.0, 1.08883],
                                device=rgb.device, dtype=rgb.dtype)
    f = torch.where(xyz_n > 0.008856,
                    xyz_n ** (1.0 / 3),
                    (903.3 * xyz_n + 16) / 116)
    L = 116 * f[..., 1] - 16
    a = 500 * (f[..., 0] - f[..., 1])
    b = 200 * (f[..., 1] - f[..., 2])
    return torch.stack([L, a, b], dim=-1)


def apply_lut_torch(colors: torch.Tensor, lut: torch.Tensor) -> torch.Tensor:
    """
    colors: (N, 3) float32 [0,1]
    lut:    (B, D, D, D, 3) float32 [0,1]
    returns (B, N, 3) — lut을 colors에 trilinear 적용 (미분 가능)

    F.grid_sample을 사용해 완전히 미분 가능.
    """
    B, D = lut.shape[0], lut.shape[1]
    N    = colors.shape[0]

    # grid_sample은 (B, C, D, H, W) 입력 + (B, N, 1, 1, 3) 좌표
    # lut: (B,D,D,D,3) → (B,3,D,D,D)
    lut_t = lut.permute(0, 4, 1, 2, 3)

    # 색상 좌표 [0,1] → [-1,1] (grid_sample 규약)
    coords = colors * 2 - 1                           # (N, 3)
    coords = coords.unsqueeze(0).unsqueeze(2).unsqueeze(2)  # (1, N, 1, 1, 3)
    coords = coords.expand(B, -1, -1, -1, -1)         # (B, N, 1, 1, 3)

    out = F.grid_sample(
        lut_t, coords,
        mode="bilinear", padding_mode="border", align_corners=True
    )  # (B, 3, N, 1, 1)
    return out.squeeze(-1).squeeze(-1).permute(0, 2, 1)  # (B, N, 3)


def image_space_loss(pred_lut: torch.Tensor, gt_lut: torch.Tensor,
                     n: int = N_COLOR_SAMPLES) -> torch.Tensor:
    """
    LUT 값 자체가 아닌, 무작위 색상에 적용한 결과를 비교.
    → 실제 시각적 색차를 최소화하도록 학습.
    """
    colors = torch.rand(n, 3, device=pred_lut.device)   # (N,3)
    pred_out = apply_lut_torch(colors, pred_lut)         # (B,N,3)
    gt_out   = apply_lut_torch(colors, gt_lut)           # (B,N,3)

    pred_lab = rgb_to_lab(pred_out.reshape(-1, 3)).reshape(pred_out.shape)
    gt_lab   = rgb_to_lab(gt_out.reshape(-1, 3)).reshape(gt_out.shape)
    return torch.mean(torch.sqrt(((pred_lab - gt_lab) ** 2).sum(-1) + 1e-6))


def smoothness_loss(lut: torch.Tensor) -> torch.Tensor:
    dr = (lut[:, 1:, :, :, :] - lut[:, :-1, :, :, :]).abs().mean()
    dg = (lut[:, :, 1:, :, :] - lut[:, :, :-1, :, :]).abs().mean()
    db = (lut[:, :, :, 1:, :] - lut[:, :, :, :-1, :]).abs().mean()
    return (dr + dg + db) / 3


def total_loss(pred: torch.Tensor, gt: torch.Tensor):
    img = image_space_loss(pred, gt)
    sm  = smoothness_loss(pred)
    combined = LAMBDA["image"] * img + LAMBDA["smooth"] * sm
    return combined, img.item(), sm.item()


# ── 학습 루프 ──────────────────────────────────────────
def split_by_lut_source(dataset: ColorTransferDataset, val_ratio: float, seed: int):
    """Hold out complete LUTs so validation cannot memorize a seen target LUT."""
    by_source = {}
    for idx, sample in enumerate(dataset.samples):
        by_source.setdefault(sample["source_lut"], []).append(idx)

    if len(by_source) < 2:
        raise ValueError("LUT 단위 검증에는 서로 다른 LUT가 최소 2개 필요합니다.")
    source_luts = sorted(by_source)
    rng = np.random.default_rng(seed)
    rng.shuffle(source_luts)
    val_source_count = min(
        len(source_luts) - 1,
        max(1, round(len(source_luts) * val_ratio)),
    )
    val_sources = set(source_luts[:val_source_count])
    train_indices = [idx for source, indices in by_source.items()
                     if source not in val_sources for idx in indices]
    val_indices = [idx for source, indices in by_source.items()
                   if source in val_sources for idx in indices]
    return (torch.utils.data.Subset(dataset, train_indices),
            torch.utils.data.Subset(dataset, val_indices),
            val_sources)


def prepare_dataset(clean: bool, pairs_per_lut: int | None):
    command = [sys.executable, str(Path(__file__).with_name("2_generate_dataset.py")),
               "--require-all-sources"]
    if clean:
        command.append("--clean")
    if pairs_per_lut is not None:
        command.extend(["--pairs-per-lut", str(pairs_per_lut)])
    subprocess.run(command, check=True)


def train(args):
    if args.prepare_dataset:
        prepare_dataset(args.clean_dataset, args.pairs_per_lut)
    elif args.clean_dataset or args.pairs_per_lut is not None:
        raise ValueError("--clean-dataset 및 --pairs-per-lut는 --prepare-dataset과 함께 사용하세요.")

    torch.manual_seed(args.seed)
    np.random.seed(args.seed)
    full_ds = ColorTransferDataset(
        DATASET_DIR,
        require_all_sources=not args.allow_incomplete_dataset,
        require_balanced_sources=not args.allow_unbalanced_dataset,
    )
    train_ds, val_ds, val_sources = split_by_lut_source(full_ds, VAL_RATIO, args.seed)
    source_summary = ", ".join(
        f"{group} {full_ds.counts_by_group[group]}쌍" for group in REQUIRED_SOURCE_GROUPS
    )
    print(f"통합 데이터셋: {len(full_ds)}쌍 / {len(full_ds.lut_sources)} LUT ({source_summary})")
    print(f"LUT 단위 분리: train {len(train_ds)}쌍, val {len(val_ds)}쌍 ({len(val_sources)} LUT)")

    # Windows에서 num_workers>0 시 멀티프로세스 출력 스팸 발생 → 0으로 고정
    train_loader = DataLoader(train_ds, batch_size=BATCH_SIZE,
                              shuffle=True,  num_workers=0, pin_memory=True)
    val_loader   = DataLoader(val_ds,   batch_size=BATCH_SIZE,
                              shuffle=False, num_workers=0, pin_memory=True)

    model     = ColorTransferNet(DECODER_DIM, LUT_DIM).to(DEVICE)
    opt       = torch.optim.AdamW(model.parameters(), lr=LR, weight_decay=1e-4)
    scaler    = GradScaler("cuda")

    total_steps = EPOCHS * len(train_loader)
    def lr_lambda(step):
        if step < WARMUP_STEPS:
            return step / max(WARMUP_STEPS, 1)
        progress = (step - WARMUP_STEPS) / max(total_steps - WARMUP_STEPS, 1)
        return 0.5 * (1 + math.cos(math.pi * progress))
    scheduler = torch.optim.lr_scheduler.LambdaLR(opt, lr_lambda)

    best_val    = float("inf")
    global_step = 0

    for epoch in range(EPOCHS):
        model.train()
        pbar = tqdm(train_loader, desc=f"Epoch {epoch+1}/{EPOCHS}")
        for style, gt_lut in pbar:
            style  = style.to(DEVICE)
            gt_lut = gt_lut.to(DEVICE)

            opt.zero_grad()
            with autocast("cuda"):
                pred_lut      = model(style)
                loss, de, sm  = total_loss(pred_lut, gt_lut)

            # NaN 감지 — 배치 스킵 (발산 방지)
            if not torch.isfinite(loss):
                opt.zero_grad()
                continue

            scaler.scale(loss).backward()
            scaler.unscale_(opt)
            torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
            scaler.step(opt)
            scaler.update()
            scheduler.step()
            global_step += 1

            pbar.set_postfix(
                loss=f"{loss.item():.4f}",
                img=f"{de:.3f}",
                lr=f"{scheduler.get_last_lr()[0]:.2e}",
            )

        # Validation (image-space ΔE)
        model.eval()
        val_de = 0.0
        with torch.no_grad():
            for style, gt_lut in val_loader:
                style  = style.to(DEVICE)
                gt_lut = gt_lut.to(DEVICE)
                with autocast("cuda"):
                    pred = model(style)
                val_de += image_space_loss(pred, gt_lut).item()
        val_de /= max(len(val_loader), 1)
        if not math.isfinite(val_de):
            print("  Val ΔE: NaN (스킵)")
            continue
        print(f"  Val ΔE: {val_de:.4f}  (목표: < 2.0)")

        if val_de < best_val:
            best_val = val_de
            torch.save({
                "epoch":       epoch,
                "model":       model.state_dict(),
                "val_de":      val_de,
                "lut_dim":     LUT_DIM,
                "decoder_dim": DECODER_DIM,
                "dataset_samples": len(full_ds),
                "dataset_lut_sources": len(full_ds.lut_sources),
                "dataset_counts_by_kind": full_ds.counts_by_kind,
                "dataset_counts_by_group": full_ds.counts_by_group,
                "validation_lut_sources": sorted(val_sources),
            }, CHECKPOINT)
            print(f"  ✓ 저장 (best ΔE={val_de:.4f})")

    print(f"\n학습 완료. Best Val ΔE: {best_val:.4f}")
    if best_val < 2.0:
        print("  ✓ 98%+ 정확도 달성 (ΔE < 2.0)")
    else:
        print("  ※ 목표 미달. 데이터 추가 또는 에폭 증가 필요.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Train Neural Color Transfer on crawled, app, and Canon LUTs."
    )
    parser.add_argument(
        "--prepare-dataset", action="store_true",
        help="Build training triplets from crawled CUBE, app BIN, and Canon LUT sources first.",
    )
    parser.add_argument(
        "--clean-dataset", action="store_true",
        help="With --prepare-dataset, discard old triplets before rebuilding.",
    )
    parser.add_argument(
        "--pairs-per-lut", type=int,
        help="With --prepare-dataset, use this many image pairs per LUT.",
    )
    parser.add_argument(
        "--allow-incomplete-dataset", action="store_true",
        help="Allow a dataset without all four LUT kinds; intended only for smoke tests.",
    )
    parser.add_argument(
        "--allow-unbalanced-dataset", action="store_true",
        help="Allow a non-balanced dataset; intended only for debugging.",
    )
    parser.add_argument("--seed", type=int, default=42)
    train(parser.parse_args())
