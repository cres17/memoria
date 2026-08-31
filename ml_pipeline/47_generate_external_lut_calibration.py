"""Generate a small, validation-only dataset from pinned external CUBE LUTs."""

from __future__ import annotations

import argparse
import importlib
import json
from pathlib import Path

import numpy as np
from PIL import Image


generator = importlib.import_module("2_generate_dataset")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--pairs-per-lut", type=int, default=12)
    parser.add_argument("--seed", type=int, default=20260828)
    parser.add_argument("--source-repository", required=True)
    parser.add_argument("--source-commit", required=True)
    parser.add_argument("--license", required=True)
    parser.add_argument("--clean", action="store_true")
    args = parser.parse_args()

    luts = sorted(args.source_dir.glob("*.cube"))
    neutral = sorted(generator.NEUTRAL_IMAGES_DIR.glob("*.jpg"))
    if not luts or len(neutral) < args.pairs_per_lut:
        raise ValueError("missing LUTs or insufficient neutral images")
    generator.prepare_output_dataset(args.output_dir, clean=args.clean)
    rng = np.random.default_rng(args.seed)
    rows = []
    index = 0
    for lut_path in luts:
        lut = generator.load_cube_lut(str(lut_path))
        if lut.shape[0] != generator.LUT_DIM:
            lut = generator.resample_lut(lut, generator.LUT_DIM)
        selected = rng.choice(len(neutral), args.pairs_per_lut, replace=False)
        source_hash = generator.sha256(lut_path)
        for neutral_index in selected:
            image = Image.open(neutral[int(neutral_index)]).convert("RGB").resize(generator.TARGET_SIZE)
            image_array = np.asarray(image, dtype=np.float32) / 255.0
            graded = generator.apply_lut_to_image(image_array, lut)
            sample_id = f"ext_{index:06d}"
            image.save(args.output_dir / "neutral" / f"{sample_id}.jpg", quality=95)
            Image.fromarray((graded * 255).astype(np.uint8)).save(
                args.output_dir / "graded" / f"{sample_id}.jpg", quality=95
            )
            generator.save_lut_bin(lut, args.output_dir / "luts" / f"{sample_id}.bin")
            rows.append({
                "id": sample_id,
                "split": "validation",
                "samplingGroup": "external_calibration",
                "sourceLut": str(lut_path.resolve()),
                "sourceLutSha256": source_hash,
                "sourceRepository": args.source_repository,
                "sourceCommit": args.source_commit,
                "license": args.license,
                "sourceImage": neutral[int(neutral_index)].name,
                "datasetVersion": "external-calibration-001",
                "lutAxisOrder": "r_fastest_rgb",
            })
            index += 1
    text = "".join(json.dumps(row) + "\n" for row in rows)
    (args.output_dir / "manifest.jsonl").write_text(text)
    (args.output_dir / "split.jsonl").write_text(text)
    print(json.dumps({"sourceLuts": len(luts), "records": len(rows)}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
