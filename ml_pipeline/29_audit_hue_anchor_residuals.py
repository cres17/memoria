"""Audit hue-anchor reconstruction of residuals left after a luminance Tone Curve.

Each target LUT is represented by its neutral-luminance Tone Curve plus a
continuous circular interpolation of RGB residual anchors over input hue. The
anchor fit is target-only and partition-separated; validation alone chooses the
recommended anchor count.
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
OUTPUT = PIPELINE_DIR / "reports" / "baselines" / "hue_anchor_residual_target_audit_001.json"
CUBE_DIM = 17
ANCHOR_COUNTS = (6, 12, 24, 48)

mvp = importlib.import_module("20_train_conditional_lut_mvp")
evaluator = importlib.import_module("17_evaluate_conditional_lut")
tone = importlib.import_module("28_audit_tone_curve_targets")


def rgb_to_hsv(rgb: np.ndarray) -> np.ndarray:
    maximum = rgb.max(axis=-1)
    minimum = rgb.min(axis=-1)
    delta = maximum - minimum
    hue = np.zeros_like(maximum)
    nonzero = delta > 1e-8
    red = (maximum == rgb[..., 0]) & nonzero
    green = (maximum == rgb[..., 1]) & nonzero
    blue = (maximum == rgb[..., 2]) & nonzero
    hue[red] = np.mod((rgb[..., 1][red] - rgb[..., 2][red]) / delta[red], 6.0)
    hue[green] = (rgb[..., 2][green] - rgb[..., 0][green]) / delta[green] + 2.0
    hue[blue] = (rgb[..., 0][blue] - rgb[..., 1][blue]) / delta[blue] + 4.0
    hue /= 6.0
    saturation = np.divide(delta, maximum, out=np.zeros_like(delta), where=maximum > 1e-8)
    return np.stack((hue, saturation, maximum), axis=-1)


def hue_anchor_reconstruction(target: np.ndarray, anchor_count: int) -> np.ndarray:
    base = tone.luminance_tone_lut(target)
    grid = tone.identity_grid()
    hsv = rgb_to_hsv(grid.reshape(-1, 3))
    hue, saturation = hsv[:, 0], hsv[:, 1]
    residual = (target - base).reshape(-1, 3)
    bin_index = np.floor(hue * anchor_count).astype(np.int64) % anchor_count
    anchors = np.zeros((anchor_count, 3), dtype=np.float32)
    for index in range(anchor_count):
        selected = bin_index == index
        weights = saturation[selected]
        # Least-squares fit for residual ~= saturation * hue_anchor.
        denominator = float(np.square(weights).sum())
        if denominator > 1e-8:
            anchors[index] = (weights[:, None] * residual[selected]).sum(axis=0) / denominator
    position = hue * anchor_count - 0.5
    lower = np.floor(position).astype(np.int64) % anchor_count
    upper = (lower + 1) % anchor_count
    fraction = (position - np.floor(position))[:, None]
    interpolated = anchors[lower] + fraction * (anchors[upper] - anchors[lower])
    prediction = base.reshape(-1, 3) + saturation[:, None] * interpolated
    return np.clip(prediction.reshape(target.shape), 0.0, 1.0).astype(np.float32)


def metrics(prediction: np.ndarray, target: np.ndarray) -> dict[str, float]:
    full_mask = np.ones(CUBE_DIM ** 3, dtype=bool)
    pair = evaluator.evaluate_lut_pair(prediction, target, CUBE_DIM, full_mask)
    return {
        "delta_e2000": float(pair["overall"]["delta_e2000"]["mean"]),
        "rgb_rmse": float(pair["overall"]["rgb_rmse"]),
        "rgb_mae": float(pair["overall"]["rgb_mae"]),
    }


def summarize(rows: list[dict]) -> dict:
    result = {"source_luts": len(rows)}
    for name in ("identity", "tone_curve") + tuple(f"hue_anchor_{count}" for count in ANCHOR_COUNTS):
        result[name] = {
            metric: float(np.mean([row[name][metric] for row in rows]))
            for metric in ("delta_e2000", "rgb_rmse", "rgb_mae")
        }
    identity_mse = np.square([row["identity"]["rgb_rmse"] for row in rows]).mean()
    tone_mse = np.square([row["tone_curve"]["rgb_rmse"] for row in rows]).mean()
    for count in ANCHOR_COUNTS:
        name = f"hue_anchor_{count}"
        anchor_mse = np.square([row[name]["rgb_rmse"] for row in rows]).mean()
        result[name]["variation_explained_vs_identity_mse"] = float(1.0 - anchor_mse / max(identity_mse, 1e-12))
        result[name]["residual_explained_vs_tone_mse"] = float(1.0 - anchor_mse / max(tone_mse, 1e-12))
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description="Audit hue-anchor residual target representation.")
    parser.add_argument("--split-path", type=Path, default=SPLIT_PATH)
    parser.add_argument("--output", type=Path, default=OUTPUT)
    args = parser.parse_args()
    rows_by_partition: dict[str, list[dict]] = defaultdict(list)
    seen_sources: dict[str, set[str]] = defaultdict(set)
    for record in mvp.read_split_records(args.split_path, {"train", "validation", "test"}):
        source_lut = record["sourceLut"]
        partition = record["split"]
        if source_lut in seen_sources[partition]:
            continue
        seen_sources[partition].add(source_lut)
        target = mvp.load_target_lut(record["lut_path"])
        row = {
            "source_lut": source_lut,
            "group": record["samplingGroup"],
            "identity": metrics(tone.identity_grid(), target),
            "tone_curve": metrics(tone.luminance_tone_lut(target), target),
        }
        row.update({f"hue_anchor_{count}": metrics(hue_anchor_reconstruction(target, count), target) for count in ANCHOR_COUNTS})
        rows_by_partition[partition].append(row)
    summaries = {partition: summarize(rows_by_partition[partition]) for partition in ("train", "validation", "test")}
    validation = summaries["validation"]
    residual_explained = {count: validation[f"hue_anchor_{count}"]["residual_explained_vs_tone_mse"] for count in ANCHOR_COUNTS}
    best_count = max(ANCHOR_COUNTS, key=lambda count: residual_explained[count])
    best_explained = residual_explained[best_count]
    selected_count = next(
        count for count in ANCHOR_COUNTS if residual_explained[count] >= 0.90 * best_explained
    )
    recommendation = {
        "selection_partition": "validation",
        "residual_explained_by_anchor_count": residual_explained,
        "best_anchor_count": best_count,
        "selected_anchor_count": selected_count,
        "recommended_next_decoder": (
            "tone_curve_plus_hue_anchor_residual"
            if best_explained >= 0.10
            else "palette_or_full_residual_before_hue_anchor"
        ),
        "selection_rule": "Choose the smallest anchor count reaching 90% of the best validation residual-explained value. Recommend a hue-anchor residual only when the best setting explains at least 10% of Tone-Curve residual MSE.",
        "test_role": "reported as a stability check; it does not choose anchor count",
    }
    report = {
        "schema_version": 1,
        "experiment_id": "HUE-ANCHOR-RESIDUAL-TARGET-AUDIT-001",
        "purpose": "target-only residual representation audit after the Tone Curve-only conditional baseline failed",
        "split_path": str(args.split_path),
        "anchor_counts": list(ANCHOR_COUNTS),
        "representation": "neutral-luminance Tone Curve plus saturation-scaled circularly interpolated RGB hue residual anchors",
        "summaries": summaries,
        "recommendation": recommendation,
        "per_source_lut": rows_by_partition,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(f"hue-anchor residual target audit complete -> {args.output}")


if __name__ == "__main__":
    main()
