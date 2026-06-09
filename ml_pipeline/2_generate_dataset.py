"""
학습 데이터 생성 스크립트
- 중립 이미지 + LUT 컬렉션 → (neutral, graded, lut) 쌍 자동 생성
- .cube (실제 LUT) 와 .bin (synthetic LUT) 모두 지원
- 출력: dataset/ 폴더에 neutral/, graded/, luts/ 저장

요구사항: pip install numpy pillow tqdm
"""

import os
import numpy as np
from pathlib import Path
from PIL import Image
from tqdm import tqdm

# ── 설정 ──────────────────────────────────────────────
NEUTRAL_IMAGES_DIR = "data/neutral_images"
CUBE_DIR           = "data/luts"              # 실제 .cube LUT
BIN_DIR            = "data/synthetic_luts"    # 수학 생성 .bin LUT
OUTPUT_DIR         = "data/dataset"
TARGET_SIZE        = (256, 256)
PAIRS_PER_LUT      = 10                       # LUT당 생성할 이미지 쌍 수
LUT_DIM            = 65

os.makedirs(f"{OUTPUT_DIR}/neutral", exist_ok=True)
os.makedirs(f"{OUTPUT_DIR}/graded",  exist_ok=True)
os.makedirs(f"{OUTPUT_DIR}/luts",    exist_ok=True)


def load_cube_lut(path: str) -> np.ndarray:
    """Adobe .cube → (dim,dim,dim,3) float32"""
    with open(path) as f:
        lines = f.readlines()
    dim, data = None, []
    for line in lines:
        line = line.strip()
        if line.startswith("LUT_3D_SIZE"):
            dim = int(line.split()[-1])
        elif line and not line.startswith("#") and not line.startswith("TITLE"):
            try:
                vals = [float(x) for x in line.split()]
                if len(vals) == 3:
                    data.append(vals)
            except ValueError:
                continue
    return np.array(data, dtype=np.float32).reshape(dim, dim, dim, 3)


def load_bin_lut(path: str) -> np.ndarray:
    """float16 binary .bin → (65,65,65,3) float32"""
    lut = np.fromfile(path, dtype=np.float16).astype(np.float32)
    return lut.reshape(LUT_DIM, LUT_DIM, LUT_DIM, 3)


def resample_lut(lut: np.ndarray, target_dim: int = 65) -> np.ndarray:
    """임의 크기 LUT → 65³ 리샘플링 (trilinear)"""
    src_dim = lut.shape[0]
    if src_dim == target_dim:
        return lut

    out = np.zeros((target_dim, target_dim, target_dim, 3), dtype=np.float32)
    coords = np.linspace(0, src_dim - 1, target_dim)

    for ri, r in enumerate(coords):
        for gi, g in enumerate(coords):
            for bi, b in enumerate(coords):
                r0, g0, b0 = int(r), int(g), int(b)
                r1 = min(r0 + 1, src_dim - 1)
                g1 = min(g0 + 1, src_dim - 1)
                b1 = min(b0 + 1, src_dim - 1)
                fr, fg, fb = r - r0, g - g0, b - b0

                # trilinear interpolation
                c000 = lut[r0, g0, b0]
                c001 = lut[r0, g0, b1]
                c010 = lut[r0, g1, b0]
                c011 = lut[r0, g1, b1]
                c100 = lut[r1, g0, b0]
                c101 = lut[r1, g0, b1]
                c110 = lut[r1, g1, b0]
                c111 = lut[r1, g1, b1]

                out[ri, gi, bi] = (
                    c000 * (1-fr)*(1-fg)*(1-fb) +
                    c100 * fr*(1-fg)*(1-fb) +
                    c010 * (1-fr)*fg*(1-fb) +
                    c110 * fr*fg*(1-fb) +
                    c001 * (1-fr)*(1-fg)*fb +
                    c101 * fr*(1-fg)*fb +
                    c011 * (1-fr)*fg*fb +
                    c111 * fr*fg*fb
                )

    return out


def apply_lut_to_image(img: np.ndarray, lut: np.ndarray) -> np.ndarray:
    """img: (H,W,3) float32 [0,1], lut: (65,65,65,3) float32 [0,1]"""
    dim = lut.shape[0] - 1
    r = img[:, :, 0] * dim
    g = img[:, :, 1] * dim
    b = img[:, :, 2] * dim

    r0 = np.clip(r.astype(int), 0, dim - 1)
    g0 = np.clip(g.astype(int), 0, dim - 1)
    b0 = np.clip(b.astype(int), 0, dim - 1)
    r1 = np.minimum(r0 + 1, dim)
    g1 = np.minimum(g0 + 1, dim)
    b1 = np.minimum(b0 + 1, dim)

    fr = (r - r0)[..., None]
    fg = (g - g0)[..., None]
    fb = (b - b0)[..., None]

    result = (
        lut[r0, g0, b0] * (1-fr)*(1-fg)*(1-fb) +
        lut[r1, g0, b0] * fr*(1-fg)*(1-fb) +
        lut[r0, g1, b0] * (1-fr)*fg*(1-fb) +
        lut[r1, g1, b0] * fr*fg*(1-fb) +
        lut[r0, g0, b1] * (1-fr)*(1-fg)*fb +
        lut[r1, g0, b1] * fr*(1-fg)*fb +
        lut[r0, g1, b1] * (1-fr)*fg*fb +
        lut[r1, g1, b1] * fr*fg*fb
    )

    return np.clip(result, 0, 1)


def save_lut_bin(lut: np.ndarray, path: str):
    """65³ LUT → float16 binary"""
    lut_f16 = lut.astype(np.float16)
    lut_f16.tofile(path)


def main():
    neutral_paths = (sorted(Path(NEUTRAL_IMAGES_DIR).glob("*.jpg")) +
                     sorted(Path(NEUTRAL_IMAGES_DIR).glob("*.png")))

    # .cube + .bin 모두 수집
    cube_paths = sorted(Path(CUBE_DIR).glob("*.cube"))
    bin_paths  = sorted(Path(BIN_DIR).glob("*.bin"))
    all_luts   = [("cube", p) for p in cube_paths] + \
                 [("bin",  p) for p in bin_paths]

    print(f"중립 이미지: {len(neutral_paths)}장")
    print(f"LUT: .cube {len(cube_paths)}개 + synthetic .bin {len(bin_paths)}개 = {len(all_luts)}개")
    print(f"예상 학습 쌍: {len(all_luts) * PAIRS_PER_LUT}개")

    assert len(neutral_paths) > 0, f"{NEUTRAL_IMAGES_DIR}에 이미지 없음"
    assert len(all_luts) > 0,      "LUT 없음: 1_download_luts.py 또는 4_generate_synthetic_luts.py 먼저 실행"

    idx = 0
    for lut_type, lut_path in tqdm(all_luts, desc="LUT 처리"):
        try:
            lut_65 = (load_cube_lut(str(lut_path)) if lut_type == "cube"
                      else load_bin_lut(str(lut_path)))
            if lut_65.shape != (LUT_DIM, LUT_DIM, LUT_DIM, 3):
                lut_65 = resample_lut(lut_65, LUT_DIM)
        except Exception as e:
            print(f"  건너뜀 ({lut_path.name}): {e}")
            continue

        selected = np.random.choice(len(neutral_paths),
                                    min(PAIRS_PER_LUT, len(neutral_paths)),
                                    replace=False)

        for ni in selected:
            try:
                img    = Image.open(neutral_paths[ni]).convert("RGB").resize(TARGET_SIZE)
                img_np = np.array(img, dtype=np.float32) / 255.0
                graded = apply_lut_to_image(img_np, lut_65)

                img_id = f"{idx:06d}"
                Image.fromarray((img_np * 255).astype(np.uint8)).save(
                    f"{OUTPUT_DIR}/neutral/{img_id}.jpg", quality=95)
                Image.fromarray((graded * 255).astype(np.uint8)).save(
                    f"{OUTPUT_DIR}/graded/{img_id}.jpg",  quality=95)
                save_lut_bin(lut_65, f"{OUTPUT_DIR}/luts/{img_id}.bin")
                idx += 1
            except Exception:
                continue

    print(f"\n완료: 총 {idx}쌍 생성 → {OUTPUT_DIR}/")


if __name__ == "__main__":
    np.random.seed(42)
    main()
