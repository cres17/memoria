"""Build per-reference observed-color masks for conditional LUT evaluation.

Each mask labels 17^3 RGB cube points as observed or unobserved from the
graded reference image.  The mask is intentionally a coverage signal, not a
confidence score: later training may combine it with learned confidence.
"""

from __future__ import annotations

import argparse
import json
from collections import Counter
from pathlib import Path

import numpy as np
from PIL import Image


PIPELINE_DIR = Path(__file__).resolve().parent
DEFAULT_DATASET_DIR = PIPELINE_DIR / "data" / "dataset"
DEFAULT_OUTPUT_DIR = PIPELINE_DIR / "reports" / "hue_masks"


def rgb_to_hsv(rgb: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Convert RGB values in [0, 1] to vectorized HSV components."""
    maximum = rgb.max(axis=-1)
    minimum = rgb.min(axis=-1)
    delta = maximum - minimum
    hue = np.zeros_like(maximum)
    nonzero = delta > 1e-6
    red = nonzero & (maximum == rgb[..., 0])
    green = nonzero & (maximum == rgb[..., 1])
    blue = nonzero & (maximum == rgb[..., 2])
    hue[red] = ((rgb[..., 1][red] - rgb[..., 2][red]) / delta[red]) % 6.0
    hue[green] = ((rgb[..., 2][green] - rgb[..., 0][green]) / delta[green]) + 2.0
    hue[blue] = ((rgb[..., 0][blue] - rgb[..., 1][blue]) / delta[blue]) + 4.0
    hue /= 6.0
    saturation = np.zeros_like(maximum)
    nonblack = maximum > 1e-6
    saturation[nonblack] = delta[nonblack] / maximum[nonblack]
    return hue, saturation, maximum


def cube_colors(cube_dim: int) -> np.ndarray:
    values = np.linspace(0.0, 1.0, cube_dim, dtype=np.float32)
    red, green, blue = np.meshgrid(values, values, values, indexing="ij")
    return np.stack((red, green, blue), axis=-1).reshape(-1, 3)


def coverage_cells(
    rgb: np.ndarray,
    hue_bins: int,
    saturation_bins: int,
    value_bins: int,
    min_saturation: float,
    min_value: float,
    min_cell_pixels: int,
) -> tuple[np.ndarray, np.ndarray]:
    """Return observed chromatic HSV cells and achromatic value cells."""
    hue, saturation, value = rgb_to_hsv(rgb)
    chromatic = (saturation >= min_saturation) & (value >= min_value)
    hue_index = np.minimum((hue[chromatic] * hue_bins).astype(np.int64), hue_bins - 1)
    saturation_index = np.minimum(
        (saturation[chromatic] * saturation_bins).astype(np.int64), saturation_bins - 1
    )
    value_index = np.minimum((value[chromatic] * value_bins).astype(np.int64), value_bins - 1)
    flattened = (hue_index * saturation_bins + saturation_index) * value_bins + value_index
    chromatic_counts = np.bincount(
        flattened, minlength=hue_bins * saturation_bins * value_bins
    ).reshape(hue_bins, saturation_bins, value_bins)

    achromatic = ~chromatic
    achromatic_index = np.minimum(
        (value[achromatic] * value_bins).astype(np.int64), value_bins - 1
    )
    achromatic_counts = np.bincount(achromatic_index, minlength=value_bins)
    return chromatic_counts >= min_cell_pixels, achromatic_counts >= min_cell_pixels


def cube_observed_mask(
    colors: np.ndarray,
    chromatic_cells: np.ndarray,
    achromatic_cells: np.ndarray,
    min_saturation: float,
    min_value: float,
) -> np.ndarray:
    hue_bins, saturation_bins, value_bins = chromatic_cells.shape
    hue, saturation, value = rgb_to_hsv(colors)
    chromatic = (saturation >= min_saturation) & (value >= min_value)
    mask = np.zeros(colors.shape[0], dtype=np.uint8)
    hue_index = np.minimum((hue[chromatic] * hue_bins).astype(np.int64), hue_bins - 1)
    saturation_index = np.minimum(
        (saturation[chromatic] * saturation_bins).astype(np.int64), saturation_bins - 1
    )
    value_index = np.minimum((value[chromatic] * value_bins).astype(np.int64), value_bins - 1)
    mask[chromatic] = chromatic_cells[hue_index, saturation_index, value_index]

    achromatic = ~chromatic
    achromatic_value_index = np.minimum(
        (value[achromatic] * value_bins).astype(np.int64), value_bins - 1
    )
    mask[achromatic] = achromatic_cells[achromatic_value_index]
    return mask


def load_ids(dataset_dir: Path) -> list[str]:
    manifest_path = dataset_dir / "manifest.jsonl"
    if not manifest_path.exists():
        raise FileNotFoundError(f"manifest is missing: {manifest_path}")
    ids = []
    for line_number, line in enumerate(manifest_path.read_text().splitlines(), start=1):
        if not line.strip():
            continue
        record = json.loads(line)
        if "id" not in record:
            raise ValueError(f"{manifest_path}:{line_number} is missing id")
        ids.append(str(record["id"]))
    if len(ids) != len(set(ids)):
        raise ValueError("manifest has duplicate ids")
    return ids


def build_masks(
    dataset_dir: Path,
    cube_dim: int,
    hue_bins: int,
    saturation_bins: int,
    value_bins: int,
    min_saturation: float,
    min_value: float,
    min_cell_pixels: int,
) -> tuple[np.ndarray, list[dict]]:
    ids = load_ids(dataset_dir)
    colors = cube_colors(cube_dim)
    masks = np.empty((len(ids), len(colors)), dtype=np.uint8)
    rows = []
    for index, sample_id in enumerate(ids):
        path = dataset_dir / "graded" / f"{sample_id}.jpg"
        if not path.exists():
            raise FileNotFoundError(f"graded image is missing: {path}")
        with Image.open(path) as image:
            pixels = np.asarray(image.convert("RGB"), dtype=np.float32) / 255.0
        chromatic_cells, achromatic_cells = coverage_cells(
            pixels,
            hue_bins=hue_bins,
            saturation_bins=saturation_bins,
            value_bins=value_bins,
            min_saturation=min_saturation,
            min_value=min_value,
            min_cell_pixels=min_cell_pixels,
        )
        mask = cube_observed_mask(
            colors,
            chromatic_cells=chromatic_cells,
            achromatic_cells=achromatic_cells,
            min_saturation=min_saturation,
            min_value=min_value,
        )
        masks[index] = mask
        rows.append(
            {
                "id": sample_id,
                "observed_cube_points": int(mask.sum()),
                "unobserved_cube_points": int(mask.size - mask.sum()),
                "observed_cube_fraction": float(mask.mean()),
                "observed_chromatic_cells": int(chromatic_cells.sum()),
                "observed_achromatic_value_bins": int(achromatic_cells.sum()),
            }
        )
    return masks, rows


def main() -> None:
    parser = argparse.ArgumentParser(description="Build per-reference observed-color cube masks.")
    parser.add_argument("--dataset-dir", type=Path, default=DEFAULT_DATASET_DIR)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
    parser.add_argument("--cube-dim", type=int, default=17)
    parser.add_argument("--hue-bins", type=int, default=24)
    parser.add_argument("--saturation-bins", type=int, default=4)
    parser.add_argument("--value-bins", type=int, default=3)
    parser.add_argument("--min-saturation", type=float, default=0.05)
    parser.add_argument("--min-value", type=float, default=0.03)
    parser.add_argument("--min-cell-pixels", type=int, default=32)
    args = parser.parse_args()
    if min(args.cube_dim, args.hue_bins, args.saturation_bins, args.value_bins, args.min_cell_pixels) <= 0:
        parser.error("grid dimensions and --min-cell-pixels must be positive")
    if not 0.0 <= args.min_saturation <= 1.0 or not 0.0 <= args.min_value <= 1.0:
        parser.error("minimum saturation/value must be in [0, 1]")

    dataset_dir = args.dataset_dir.resolve()
    masks, rows = build_masks(
        dataset_dir,
        cube_dim=args.cube_dim,
        hue_bins=args.hue_bins,
        saturation_bins=args.saturation_bins,
        value_bins=args.value_bins,
        min_saturation=args.min_saturation,
        min_value=args.min_value,
        min_cell_pixels=args.min_cell_pixels,
    )
    args.output_dir.mkdir(parents=True, exist_ok=True)
    prefix = f"hue_coverage_{args.cube_dim}"
    archive_path = args.output_dir / f"{prefix}.npz"
    rows_path = args.output_dir / f"{prefix}.jsonl"
    report_path = args.output_dir / f"{prefix}.report.json"
    np.savez_compressed(
        archive_path,
        ids=np.asarray([row["id"] for row in rows]),
        observed_cube_mask=masks,
        cube_dim=np.asarray(args.cube_dim),
        hue_bins=np.asarray(args.hue_bins),
        saturation_bins=np.asarray(args.saturation_bins),
        value_bins=np.asarray(args.value_bins),
        min_saturation=np.asarray(args.min_saturation),
        min_value=np.asarray(args.min_value),
        min_cell_pixels=np.asarray(args.min_cell_pixels),
        cube_order=np.asarray("rgb_ij_flattened"),
    )
    rows_path.write_text("".join(json.dumps(row, sort_keys=True) + "\n" for row in rows))
    fractions = np.asarray([row["observed_cube_fraction"] for row in rows], dtype=np.float32)
    report = {
        "schema_version": 1,
        "dataset_dir": str(dataset_dir),
        "mask_archive": str(archive_path),
        "per_reference_rows": str(rows_path),
        "definition": (
            "A cube point is observed when its HSV hue/saturation/value cell occurs at least "
            "min_cell_pixels times in the graded reference. Achromatic points use value-only cells."
        ),
        "settings": {
            "cube_dim": args.cube_dim,
            "hue_bins": args.hue_bins,
            "saturation_bins": args.saturation_bins,
            "value_bins": args.value_bins,
            "min_saturation": args.min_saturation,
            "min_value": args.min_value,
            "min_cell_pixels": args.min_cell_pixels,
        },
        "summary": {
            "references": len(rows),
            "cube_points_per_reference": int(masks.shape[1]),
            "observed_fraction_min": float(fractions.min()),
            "observed_fraction_mean": float(fractions.mean()),
            "observed_fraction_max": float(fractions.max()),
            "empty_observed_masks": int(np.count_nonzero(fractions == 0.0)),
            "fully_observed_masks": int(np.count_nonzero(fractions == 1.0)),
        },
    }
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(
        f"hue masks complete references={len(rows)} cube_points={masks.shape[1]} "
        f"observed_fraction_mean={fractions.mean():.6f} report={report_path}"
    )


if __name__ == "__main__":
    main()
