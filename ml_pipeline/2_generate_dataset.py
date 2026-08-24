"""
학습 데이터 생성 스크립트
- 중립 이미지 + LUT 컬렉션 → (neutral, graded, lut) 쌍 자동 생성
- .cube (실제 LUT) 와 .bin (synthetic LUT) 모두 지원
- 출력: dataset/ 폴더에 neutral/, graded/, luts/ 저장

요구사항: pip install numpy pillow tqdm
"""

import argparse
import json
import os
import shutil
import numpy as np
from pathlib import Path
from PIL import Image
from tqdm import tqdm

# ── 설정 ──────────────────────────────────────────────
PIPELINE_DIR       = Path(__file__).resolve().parent
NEUTRAL_IMAGES_DIR = PIPELINE_DIR / "data/neutral_images"
CUBE_DIR           = PIPELINE_DIR / "data/luts"       # whitelist로 수집한 .cube LUT
APP_BIN_DIR        = PIPELINE_DIR.parent / "assets/luts"  # 앱에 포함된 65³ float16 LUT
CANON_LUT_DIR      = PIPELINE_DIR.parent / "LUT"       # Canon C-Log 2/3 → BT.709 LUT
OUTPUT_DIR         = PIPELINE_DIR / "data/dataset"
TARGET_SIZE        = (256, 256)
TARGET_TOTAL_PAIRS = 3000
LUT_DIM            = 65

os.makedirs(OUTPUT_DIR / "neutral", exist_ok=True)
os.makedirs(OUTPUT_DIR / "graded",  exist_ok=True)
os.makedirs(OUTPUT_DIR / "luts",    exist_ok=True)

REQUIRED_LUT_KINDS = ("cube", "bin", "canon_clog2", "canon_clog3")
SOURCE_GROUP_BY_KIND = {
    "cube": "crawled",
    "bin": "app",
    "canon_clog2": "canon",
    "canon_clog3": "canon",
}
REQUIRED_SOURCE_GROUPS = ("crawled", "app", "canon")


def collect_lut_sources():
    """Returns all local LUTs once, tagged with their expected input domain."""
    sources = []
    sources.extend(("cube", path) for path in sorted(Path(CUBE_DIR).glob("*.cube")))
    sources.extend(("bin", path) for path in sorted(Path(APP_BIN_DIR).glob("*.bin")))

    # The same Canon look exists in 33-grid and 65-grid forms; retain only
    # 65-grid. CLog2's downloaded package is duplicated, so de-duplicate by
    # filename while preserving CLog2 and CLog3 as distinct input domains.
    canon = {}
    for path in sorted(Path(CANON_LUT_DIR).rglob("*.cube")):
        if path.parent.name != "65grid":
            continue
        if "CLog2_to_709_65" in path.name:
            canon.setdefault(("canon_clog2", path.name), path)
        elif "CLog3_to_709_65" in path.name:
            canon.setdefault(("canon_clog3", path.name), path)
    sources.extend((kind, path) for (kind, _), path in sorted(canon.items()))
    return sources


def source_counts(sources):
    return {
        kind: sum(1 for source_kind, _ in sources if source_kind == kind)
        for kind in REQUIRED_LUT_KINDS
    }


def source_group(lut_kind: str) -> str:
    return SOURCE_GROUP_BY_KIND[lut_kind]


def allocate_pairs(sources, total_pairs: int, pairs_per_lut: int | None):
    """Allocate equal pair budgets to crawled, app, and Canon source groups."""
    if pairs_per_lut is not None:
        return {path: pairs_per_lut for _, path in sources}, "per_lut"

    grouped = {group: [] for group in REQUIRED_SOURCE_GROUPS}
    for lut_kind, path in sources:
        grouped[source_group(lut_kind)].append(path)
    active_groups = [group for group in REQUIRED_SOURCE_GROUPS if grouped[group]]
    if not active_groups:
        return {}, "balanced_source"

    group_base, group_remainder = divmod(total_pairs, len(active_groups))
    pairs_by_lut = {}
    for group_index, group in enumerate(active_groups):
        group_budget = group_base + (group_index < group_remainder)
        lut_base, lut_remainder = divmod(group_budget, len(grouped[group]))
        for lut_index, path in enumerate(grouped[group]):
            pairs_by_lut[path] = lut_base + (lut_index < lut_remainder)
    return pairs_by_lut, "balanced_source"


def clear_output_dataset():
    """Remove only generated triplets so an old dataset cannot leak into training."""
    output = Path(OUTPUT_DIR)
    for directory in ("neutral", "graded", "luts"):
        target = output / directory
        if target.exists():
            shutil.rmtree(target)
        target.mkdir(parents=True, exist_ok=True)
    (output / "manifest.jsonl").unlink(missing_ok=True)


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


def apply_lut_to_colors(colors: np.ndarray, lut: np.ndarray) -> np.ndarray:
    """Apply a LUT to colors with any leading shape, using trilinear interpolation."""
    dim = lut.shape[0] - 1
    r = colors[..., 0] * dim
    g = colors[..., 1] * dim
    b = colors[..., 2] * dim

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


def apply_lut_to_image(img: np.ndarray, lut: np.ndarray) -> np.ndarray:
    """img: (H,W,3) float32 [0,1], lut: (65,65,65,3) float32 [0,1]"""
    return apply_lut_to_colors(img, lut)


def srgb_to_canon_log(img: np.ndarray, log_version: str) -> np.ndarray:
    """Adapts an sRGB image to the transfer domain expected by Canon LUTs.

    Canon LUTs are camera-log transforms, unlike the other LUT sources. This
    applies the documented positive-range transfer approximation after sRGB
    linearisation; it does not claim to convert the image's camera gamut.
    """
    linear = np.where(
        img <= 0.04045, img / 12.92, ((img + 0.055) / 1.055) ** 2.4
    )
    if log_version == "canon_clog2":
        encoded = 0.529136 * np.log10(10.1596 * linear + 1.0) + 0.0730597
    elif log_version == "canon_clog3":
        encoded = 0.42889912 * np.log10(14.98325 * linear + 1.0) + 0.12783901
    else:
        raise ValueError(f"unsupported Canon log version: {log_version}")
    return np.clip(encoded, 0.0, 1.0).astype(np.float32)


def compose_canon_srgb_lut(canon_lut: np.ndarray, log_version: str) -> np.ndarray:
    """Bake Canon's CLog input transform into a LUT the app can apply to sRGB.

    The app indexes every predicted LUT with ordinary sRGB pixels. Canon's
    supplied LUTs instead expect CLog2/CLog3 values, so training on their raw
    cubes would teach a LUT that has the wrong input domain at inference time.
    """
    coords = np.linspace(0.0, 1.0, LUT_DIM, dtype=np.float32)
    r, g, b = np.meshgrid(coords, coords, coords, indexing="ij")
    srgb_grid = np.stack([r, g, b], axis=-1)
    canon_input = srgb_to_canon_log(srgb_grid, log_version)
    return apply_lut_to_colors(canon_input, canon_lut).astype(np.float32)


def save_lut_bin(lut: np.ndarray, path: str):
    """65³ LUT → float16 binary"""
    lut_f16 = lut.astype(np.float16)
    lut_f16.tofile(path)


def main():
    parser = argparse.ArgumentParser(
        description="Generate neutral/graded/LUT training triplets from local images and LUTs."
    )
    parser.add_argument(
        "--pairs-per-lut", type=int,
        help="Debug override. Disables balanced source sampling and uses this count for every LUT.",
    )
    parser.add_argument(
        "--clean", action="store_true",
        help="Delete previously generated triplets before creating the combined dataset.",
    )
    parser.add_argument(
        "--require-all-sources", action="store_true",
        help="Fail unless crawled CUBE, app BIN, Canon CLog2, and Canon CLog3 LUTs are all present.",
    )
    args = parser.parse_args()
    if args.pairs_per_lut is not None and args.pairs_per_lut <= 0:
        parser.error("--pairs-per-lut must be positive")

    neutral_paths = (sorted(Path(NEUTRAL_IMAGES_DIR).glob("*.jpg")) +
                     sorted(Path(NEUTRAL_IMAGES_DIR).glob("*.png")))

    all_luts = collect_lut_sources()
    by_kind = source_counts(all_luts)
    pairs_by_lut, sampling_mode = allocate_pairs(
        all_luts, TARGET_TOTAL_PAIRS, args.pairs_per_lut
    )
    planned_by_group = {
        group: sum(
            pairs_by_lut[path]
            for lut_kind, path in all_luts
            if source_group(lut_kind) == group
        )
        for group in REQUIRED_SOURCE_GROUPS
    }

    print(f"중립 이미지: {len(neutral_paths)}장")
    print(f"LUT: 공개 CUBE {by_kind['cube']}개 + 앱 BIN {by_kind['bin']}개 + "
          f"Canon CLog2 {by_kind['canon_clog2']}개 + CLog3 {by_kind['canon_clog3']}개 = {len(all_luts)}개")
    print(f"소스별 학습 쌍 ({sampling_mode}): 크롤링 {planned_by_group['crawled']} + "
          f"앱 {planned_by_group['app']} + Canon {planned_by_group['canon']} = {sum(planned_by_group.values())}개")

    assert len(neutral_paths) > 0, f"{NEUTRAL_IMAGES_DIR}에 이미지 없음"
    assert len(all_luts) > 0,      "LUT 없음: 1_download_luts.py 또는 4_generate_synthetic_luts.py 먼저 실행"
    if args.require_all_sources:
        missing = [kind for kind, count in by_kind.items() if count == 0]
        if missing:
            parser.error(
                "통합 학습에 필요한 LUT 소스가 없습니다: " + ", ".join(missing) +
                ". ml_pipeline/data/luts(크롤링 CUBE), assets/luts(기존 앱 BIN), LUT(Canon)를 확인하세요."
            )
    if args.clean:
        clear_output_dataset()

    manifest_path = Path(OUTPUT_DIR) / "manifest.jsonl"
    idx = 0
    manifest_rows = []
    for lut_type, lut_path in tqdm(all_luts, desc="LUT 처리"):
        try:
            source_lut = (load_cube_lut(str(lut_path)) if lut_type != "bin"
                          else load_bin_lut(str(lut_path)))
            if source_lut.shape != (LUT_DIM, LUT_DIM, LUT_DIM, 3):
                source_lut = resample_lut(source_lut, LUT_DIM)
            lut_65 = (compose_canon_srgb_lut(source_lut, lut_type)
                      if lut_type.startswith("canon_") else source_lut)
        except Exception as e:
            print(f"  건너뜀 ({lut_path.name}): {e}")
            continue

        selected = np.random.choice(len(neutral_paths),
                                    min(pairs_by_lut[lut_path], len(neutral_paths)),
                                    replace=False)

        for ni in selected:
            try:
                img    = Image.open(neutral_paths[ni]).convert("RGB").resize(TARGET_SIZE)
                img_np = np.array(img, dtype=np.float32) / 255.0
                graded = apply_lut_to_image(img_np, lut_65)

                img_id = f"{idx:06d}"
                Image.fromarray((img_np * 255).astype(np.uint8)).save(
                OUTPUT_DIR / "neutral" / f"{img_id}.jpg", quality=95)
                Image.fromarray((graded * 255).astype(np.uint8)).save(
                OUTPUT_DIR / "graded" / f"{img_id}.jpg",  quality=95)
                save_lut_bin(lut_65, OUTPUT_DIR / "luts" / f"{img_id}.bin")
                manifest_rows.append({
                    "id": img_id,
                    "sourceImage": neutral_paths[ni].name,
                    "sourceLut": str(lut_path),
                    "lutKind": lut_type,
                    "inputDomain": "srgb_composed" if lut_type.startswith("canon_") else "srgb",
                    "samplingGroup": source_group(lut_type),
                    "samplingMode": sampling_mode,
                })
                idx += 1
            except Exception:
                continue

    manifest_path.write_text("".join(json.dumps(row) + "\n" for row in manifest_rows))
    print(f"\n완료: 총 {idx}쌍 생성 → {OUTPUT_DIR}/ (manifest: {manifest_path})")


if __name__ == "__main__":
    np.random.seed(42)
    main()
