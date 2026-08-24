"""Audit raw LUT values versus the clamped rendering contract."""

from __future__ import annotations

import argparse
import json
from collections import defaultdict
from pathlib import Path

import numpy as np


PIPELINE_DIR = Path(__file__).resolve().parent
DATASET_DIR = PIPELINE_DIR / "data" / "dataset"
DEFAULT_OUTPUT = PIPELINE_DIR / "reports" / "lut_rendering_contract_audit.json"


def cube_colors(dim: int) -> np.ndarray:
    values = np.linspace(0.0, 1.0, dim, dtype=np.float32)
    red, green, blue = np.meshgrid(values, values, values, indexing="ij")
    return np.stack((red, green, blue), axis=-1).reshape(-1, 3)


def apply_lut(colors: np.ndarray, lut: np.ndarray) -> np.ndarray:
    dim = lut.shape[0] - 1
    coordinates = np.clip(colors, 0.0, 1.0) * dim
    lower = np.floor(coordinates).astype(np.int64)
    lower = np.clip(lower, 0, dim - 1)
    upper = np.minimum(lower + 1, dim)
    fraction = coordinates - lower
    r0, g0, b0 = lower[..., 0], lower[..., 1], lower[..., 2]
    r1, g1, b1 = upper[..., 0], upper[..., 1], upper[..., 2]
    fr, fg, fb = fraction[..., 0:1], fraction[..., 1:2], fraction[..., 2:3]
    return (
        lut[r0, g0, b0] * (1 - fr) * (1 - fg) * (1 - fb)
        + lut[r1, g0, b0] * fr * (1 - fg) * (1 - fb)
        + lut[r0, g1, b0] * (1 - fr) * fg * (1 - fb)
        + lut[r1, g1, b0] * fr * fg * (1 - fb)
        + lut[r0, g0, b1] * (1 - fr) * (1 - fg) * fb
        + lut[r1, g0, b1] * fr * (1 - fg) * fb
        + lut[r0, g1, b1] * (1 - fr) * fg * fb
        + lut[r1, g1, b1] * fr * fg * fb
    )


def summarize(values: list[float]) -> dict:
    array = np.asarray(values, dtype=np.float64)
    return {
        "count": int(array.size),
        "min": float(array.min()),
        "median": float(np.median(array)),
        "mean": float(array.mean()),
        "max": float(array.max()),
    }


def read_unique_luts(dataset_dir: Path) -> dict[str, dict]:
    unique = {}
    for line in (dataset_dir / "manifest.jsonl").read_text().splitlines():
        if not line:
            continue
        record = json.loads(line)
        unique.setdefault(
            record["sourceLut"],
            {
                "id": str(record["id"]),
                "group": record["samplingGroup"],
                "lut_kind": record["lutKind"],
            },
        )
    return unique


def load_lut(path: Path) -> np.ndarray:
    values = np.fromfile(path, dtype=np.float16).astype(np.float32)
    if values.size != 65 ** 3 * 3:
        raise ValueError(f"{path} has {values.size} values; expected {65 ** 3 * 3}")
    return values.reshape(65, 65, 65, 3)


def audit_lut(lut: np.ndarray, colors: np.ndarray) -> dict:
    raw_nodes = lut.reshape(-1, 3)
    raw_render = apply_lut(colors, lut)
    clamped_render = np.clip(raw_render, 0.0, 1.0)
    node_oog = (raw_nodes < 0.0) | (raw_nodes > 1.0)
    render_oog = (raw_render < 0.0) | (raw_render > 1.0)
    clamp_delta = np.abs(raw_render - clamped_render)
    return {
        "raw_node_value_oog_ratio": float(node_oog.mean()),
        "raw_node_oog_ratio": float(np.any(node_oog, axis=1).mean()),
        "raw_node_min": float(raw_nodes.min()),
        "raw_node_max": float(raw_nodes.max()),
        "raw_render_value_oog_ratio": float(render_oog.mean()),
        "raw_render_oog_ratio": float(np.any(render_oog, axis=1).mean()),
        "raw_render_min": float(raw_render.min()),
        "raw_render_max": float(raw_render.max()),
        "clamp_adjustment_mae": float(clamp_delta.mean()),
        "clamp_adjustment_max": float(clamp_delta.max()),
        "clamp_affected_render_ratio": float(np.any(clamp_delta > 0.0, axis=1).mean()),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Audit raw LUT OOG against clamped rendering.")
    parser.add_argument("--dataset-dir", type=Path, default=DATASET_DIR)
    parser.add_argument("--cube-dim", type=int, default=17)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    if args.cube_dim <= 1:
        parser.error("--cube-dim must be greater than 1")

    dataset_dir = args.dataset_dir.resolve()
    colors = cube_colors(args.cube_dim)
    rows = []
    for source_lut, source in sorted(read_unique_luts(dataset_dir).items()):
        lut_path = dataset_dir / "luts" / f"{source['id']}.bin"
        metrics = audit_lut(load_lut(lut_path), colors)
        rows.append({"source_lut": source_lut, **source, **metrics})

    by_group = {}
    for group in sorted({row["group"] for row in rows}):
        group_rows = [row for row in rows if row["group"] == group]
        metric_keys = [key for key in group_rows[0] if key.endswith("_ratio") or key.endswith("_mae")]
        by_group[group] = {"luts": len(group_rows)} | {
            key: summarize([row[key] for row in group_rows]) for key in metric_keys
        }
    metric_keys = [key for key in rows[0] if key.endswith("_ratio") or key.endswith("_mae")]
    report = {
        "schema_version": 1,
        "dataset_dir": str(dataset_dir),
        "cube_dim": args.cube_dim,
        "rendering_contract": {
            "accuracy_comparison": "clamped_srgb_rendered_output",
            "safety_measurement": "raw_lut_nodes_and_raw_cube_render",
            "clamp": "[0, 1] per RGB channel",
        },
        "overall": {"luts": len(rows)} | {key: summarize([row[key] for row in rows]) for key in metric_keys},
        "by_group": by_group,
        "top_raw_render_oog": sorted(rows, key=lambda row: row["raw_render_oog_ratio"], reverse=True)[:20],
        "per_lut": rows,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(f"rendering contract audit complete luts={len(rows)} report={args.output}")


if __name__ == "__main__":
    main()
