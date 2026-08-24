"""Measure how much target-LUT variation is explained by tone-only transforms.

The audit is target-only: it never trains a model or uses a held-out target to
choose a checkpoint.  The validation partition determines the decoder-module
recommendation; test is reported only as a contract-stability check.
"""

from __future__ import annotations

import argparse
import importlib
import json
from collections import defaultdict
from pathlib import Path

import numpy as np


PIPELINE_DIR = Path(__file__).resolve().parent
SPLIT_PATH = PIPELINE_DIR / "reports" / "splits" / "conditional_lut_family_holdout.jsonl"
OUTPUT = PIPELINE_DIR / "reports" / "baselines" / "tone_curve_target_audit_001.json"
CUBE_DIM = 17

mvp = importlib.import_module("20_train_conditional_lut_mvp")
evaluator = importlib.import_module("17_evaluate_conditional_lut")


def identity_grid() -> np.ndarray:
    return evaluator.identity_lut(CUBE_DIM).astype(np.float32)


def luminance_tone_lut(target: np.ndarray) -> np.ndarray:
    """Preserve input chroma while remapping luminance through the neutral diagonal."""
    axis = np.linspace(0.0, 1.0, CUBE_DIM, dtype=np.float32)
    diagonal = target[np.arange(CUBE_DIM), np.arange(CUBE_DIM), np.arange(CUBE_DIM)]
    output_luma = diagonal @ np.asarray((0.2126, 0.7152, 0.0722), dtype=np.float32)
    grid = identity_grid()
    input_luma = grid @ np.asarray((0.2126, 0.7152, 0.0722), dtype=np.float32)
    mapped_luma = np.interp(input_luma.reshape(-1), axis, output_luma).reshape(input_luma.shape)
    scale = np.divide(mapped_luma, input_luma, out=np.zeros_like(mapped_luma), where=input_luma > 1e-6)
    result = grid * scale[..., None]
    result[input_luma <= 1e-6] = diagonal[0]
    return np.clip(result, 0.0, 1.0).astype(np.float32)


def channel_separable_lut(target: np.ndarray) -> np.ndarray:
    """Apply one neutral-diagonal curve per output channel, without hue coupling."""
    axis = np.linspace(0.0, 1.0, CUBE_DIM, dtype=np.float32)
    diagonal = target[np.arange(CUBE_DIM), np.arange(CUBE_DIM), np.arange(CUBE_DIM)]
    grid = identity_grid()
    result = np.empty_like(grid)
    for channel in range(3):
        result[..., channel] = np.interp(grid[..., channel].reshape(-1), axis, diagonal[:, channel]).reshape(grid.shape[:3])
    return np.clip(result, 0.0, 1.0).astype(np.float32)


def metrics(prediction: np.ndarray, target: np.ndarray) -> dict[str, float]:
    full_mask = np.ones(CUBE_DIM ** 3, dtype=bool)
    pair = evaluator.evaluate_lut_pair(prediction, target, CUBE_DIM, full_mask)
    return {
        "delta_e2000": float(pair["overall"]["delta_e2000"]["mean"]),
        "rgb_rmse": float(pair["overall"]["rgb_rmse"]),
        "rgb_mae": float(pair["overall"]["rgb_mae"]),
    }


def summarize(rows: list[dict]) -> dict:
    methods = ("identity", "luminance_tone", "channel_separable")
    result = {"source_luts": len(rows)}
    for method in methods:
        result[method] = {
            metric: float(np.mean([row[method][metric] for row in rows]))
            for metric in ("delta_e2000", "rgb_rmse", "rgb_mae")
        }
    identity_mse = np.square([row["identity"]["rgb_rmse"] for row in rows])
    for method in ("luminance_tone", "channel_separable"):
        method_mse = np.square([row[method]["rgb_rmse"] for row in rows])
        result[method]["variation_explained_vs_identity_mse"] = float(
            1.0 - method_mse.mean() / max(identity_mse.mean(), 1e-12)
        )
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description="Audit tone-only target-LUT reconstruction by partition.")
    parser.add_argument("--split-path", type=Path, default=SPLIT_PATH)
    parser.add_argument("--output", type=Path, default=OUTPUT)
    args = parser.parse_args()
    rows_by_partition: dict[str, list[dict]] = defaultdict(list)
    seen_sources: dict[str, set[str]] = defaultdict(set)
    for record in mvp.read_split_records(args.split_path, {"train", "validation", "test"}):
        source_lut = record["sourceLut"]
        if source_lut in seen_sources[record["split"]]:
            continue
        seen_sources[record["split"]].add(source_lut)
        target = mvp.load_target_lut(record["lut_path"])
        rows_by_partition[record["split"]].append(
            {
                "source_lut": source_lut,
                "group": record["samplingGroup"],
                "identity": metrics(identity_grid(), target),
                "luminance_tone": metrics(luminance_tone_lut(target), target),
                "channel_separable": metrics(channel_separable_lut(target), target),
            }
        )
    summaries = {partition: summarize(rows_by_partition[partition]) for partition in ("train", "validation", "test")}
    validation = summaries["validation"]
    luma_explained = validation["luminance_tone"]["variation_explained_vs_identity_mse"]
    channel_explained = validation["channel_separable"]["variation_explained_vs_identity_mse"]
    recommendation = {
        "selection_partition": "validation",
        "luminance_tone_variation_explained": luma_explained,
        "channel_separable_variation_explained": channel_explained,
        "recommended_first_module": "tone_curve" if luma_explained >= 0.10 else "hue_anchor_or_palette_before_tone_curve",
        "recommended_companion": "hue_anchor" if channel_explained - luma_explained >= 0.10 else "none_required_by_target_audit",
        "rule": "Use a Tone Curve first only when the validation neutral-luminance transform explains at least 10% of identity-relative target MSE; add Hue Anchor when channel-separable curves add at least 10 percentage points beyond luminance-only.",
        "test_role": "reported as a stability check; it does not select the module",
    }
    report = {
        "schema_version": 1,
        "experiment_id": "TONE-CURVE-TARGET-AUDIT-001",
        "purpose": "target-only representation audit before a structured decoder implementation",
        "split_path": str(args.split_path),
        "methods": {
            "identity": "identity 17^3 LUT",
            "luminance_tone": "neutral-diagonal luminance curve applied with input-chroma preservation",
            "channel_separable": "one neutral-diagonal curve per RGB channel; no cross-channel or hue coupling",
        },
        "summaries": summaries,
        "recommendation": recommendation,
        "per_source_lut": rows_by_partition,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(f"tone-curve target audit complete -> {args.output}")


if __name__ == "__main__":
    main()
