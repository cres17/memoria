"""Diagnose whether a conditional LUT checkpoint has collapsed toward a mean LUT.

This is a read-only checkpoint analysis.  It compares each generated bounded
17^3 LUT with the train-set mean LUT and identity LUT under the same clamped
sRGB evaluator contract used by the baseline reports.  It deliberately does
not start a new training run or overwrite a checkpoint.
"""

from __future__ import annotations

import argparse
import importlib
import json
from collections import defaultdict
from pathlib import Path

import numpy as np
import torch


PIPELINE_DIR = Path(__file__).resolve().parent
CHECKPOINT = PIPELINE_DIR / "checkpoints" / "conditional_lut_mvp_17.pt"
MASK_PATH = PIPELINE_DIR / "reports" / "hue_masks" / "hue_coverage_17.npz"
OUTPUT = PIPELINE_DIR / "reports" / "mvp" / "mvp_bottleneck_analysis_report.json"

mvp = importlib.import_module("20_train_conditional_lut_mvp")
baseline = importlib.import_module("18_evaluate_conditional_baselines")
evaluator = importlib.import_module("17_evaluate_conditional_lut")


def load_masks() -> dict[str, np.ndarray]:
    with np.load(MASK_PATH) as archive:
        if int(archive["cube_dim"]) != mvp.CUBE_DIM:
            raise ValueError("Hue mask grid must match checkpoint cube dimension")
        return {str(sample_id): mask.astype(bool) for sample_id, mask in zip(archive["ids"].astype(str), archive["observed_cube_mask"])}


def mean_target_lut(records: list[dict]) -> np.ndarray:
    targets_by_source: dict[str, np.ndarray] = {}
    for record in records:
        targets_by_source.setdefault(record["sourceLut"], mvp.load_target_lut(record["lut_path"]))
    if not targets_by_source:
        raise ValueError("no train LUT targets available")
    return np.mean(np.stack(list(targets_by_source.values())), axis=0).astype(np.float32)


def lut_distance(left: np.ndarray, right: np.ndarray) -> dict[str, float]:
    delta = left - right
    return {
        "node_rgb_mae": float(np.abs(delta).mean()),
        "node_rgb_rmse": float(np.sqrt(np.square(delta).mean())),
    }


def summarize_scalar(values: list[float]) -> dict[str, float | int]:
    array = np.asarray(values, dtype=np.float64)
    if not array.size:
        return {"count": 0, "mean": None, "min": None, "max": None, "std": None}
    return {"count": int(array.size), "mean": float(array.mean()), "min": float(array.min()), "max": float(array.max()), "std": float(array.std())}


def aggregate_group(rows: list[dict]) -> dict:
    if not rows:
        return {"samples": 0}
    return {
        "samples": len(rows),
        "prediction_to_train_mean": {
            key: summarize_scalar([row["prediction_to_train_mean"][key] for row in rows])
            for key in ("node_rgb_mae", "node_rgb_rmse")
        },
        "prediction_to_identity": {
            key: summarize_scalar([row["prediction_to_identity"][key] for row in rows])
            for key in ("node_rgb_mae", "node_rgb_rmse")
        },
        "target_to_train_mean": {
            key: summarize_scalar([row["target_to_train_mean"][key] for row in rows])
            for key in ("node_rgb_mae", "node_rgb_rmse")
        },
        "decoder_residual_logits": {
            key: summarize_scalar([row["decoder_residual_logits"][key] for row in rows])
            for key in ("abs_mean", "std")
        },
        "style_code": {
            key: summarize_scalar([row["style_code"][key] for row in rows])
            for key in ("l2", "component_std")
        },
        "prediction_lut_quality": baseline.aggregate(rows)["prediction_lut_quality"],
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Analyze direct conditional-LUT checkpoint collapse without training.")
    parser.add_argument("--checkpoint", type=Path, default=CHECKPOINT)
    parser.add_argument("--partition", choices=("validation", "test"), default="validation")
    parser.add_argument("--max-samples", type=int)
    parser.add_argument("--output", type=Path, default=OUTPUT)
    parser.add_argument("--semantic-cache-dir", type=Path)
    args = parser.parse_args()
    if args.max_samples is not None and args.max_samples <= 0:
        parser.error("--max-samples must be positive")

    checkpoint = torch.load(args.checkpoint, map_location=mvp.DEVICE, weights_only=False)
    semantic_cache_dir = args.semantic_cache_dir or (
        Path(checkpoint["semantic_cache_dir"]) if checkpoint.get("semantic_cache_dir") else None
    )
    model = mvp.ConditionalLUTMVP(
        style_dim=int(checkpoint["style_dim"]),
        cube_dim=int(checkpoint["cube_dim"]),
        pretrained=False,
        decoder_output_mode=str(checkpoint.get("decoder_output_mode", "identity_logit")),
        decoder_hidden_dim=int(checkpoint.get("decoder_hidden_dim", 512)),
        structured_auxiliary=bool(checkpoint.get("structured_auxiliary_enabled", False)),
        semantic_pooled_features=bool(checkpoint.get("semantic_pooled_features", False)),
    ).to(mvp.DEVICE)
    model.load_state_dict(checkpoint["state_dict"])
    model.eval()
    masks = load_masks()
    train_mean = mean_target_lut(mvp.read_split_records(Path(checkpoint["split_path"]), {"train"}))
    identity = evaluator.identity_lut(mvp.CUBE_DIM)
    records = mvp.read_split_records(Path(checkpoint["split_path"]), {args.partition})
    if args.max_samples is not None:
        records = records[:args.max_samples]

    rows: list[dict] = []
    predictions: list[np.ndarray] = []
    residuals: list[np.ndarray] = []
    style_codes: list[np.ndarray] = []
    with torch.no_grad():
        for record in records:
            reference = mvp.v2.load_image_tensor(record["reference_path"]).unsqueeze(0).to(mvp.DEVICE)
            semantic_masks = (mvp.load_semantic_masks(semantic_cache_dir, record["id"]).unsqueeze(0).to(mvp.DEVICE)
                              if model.semantic_pooled_features else None)
            prediction, style_code = model(reference, semantic_masks)
            prediction_np = prediction[0].cpu().numpy()
            residual_logits = model.lut_decoder.residual_logits(style_code)[0].cpu().numpy()
            style_code_np = style_code[0].cpu().numpy()
            target = mvp.load_target_lut(record["lut_path"])
            pair = evaluator.evaluate_lut_pair(prediction_np, target, mvp.CUBE_DIM, masks[record["id"]])
            rows.append(
                pair
                | {
                    "id": record["id"],
                    "group": record["samplingGroup"],
                    "source_lut": record["sourceLut"],
                    "prediction_to_train_mean": lut_distance(prediction_np, train_mean),
                    "prediction_to_identity": lut_distance(prediction_np, identity),
                    "target_to_train_mean": lut_distance(target, train_mean),
                    "decoder_residual_logits": {
                        "abs_mean": float(np.abs(residual_logits).mean()),
                        "std": float(residual_logits.std()),
                    },
                    "style_code": {
                        "l2": float(np.linalg.norm(style_code_np)),
                        "component_std": float(style_code_np.std()),
                    },
                }
            )
            predictions.append(prediction_np.reshape(-1))
            residuals.append(residual_logits)
            style_codes.append(style_code_np)

    prediction_matrix = np.stack(predictions)
    residual_matrix = np.stack(residuals)
    style_matrix = np.stack(style_codes)
    output_variance = prediction_matrix.var(axis=0)
    target_variance = np.stack([mvp.load_target_lut(record["lut_path"]).reshape(-1) for record in records]).var(axis=0)
    by_group = {group: aggregate_group([row for row in rows if row["group"] == group]) for group in mvp.SOURCE_GROUPS}
    result = {
        "schema_version": 1,
        "experiment_id": "MVP-BOTTLENECK-ANALYSIS-001",
        "purpose": "read-only diagnosis before controlled ablations; no checkpoint or dataset artifacts were modified",
        "checkpoint": str(args.checkpoint),
        "partition": args.partition,
        "samples": len(rows),
        "renderer_contract": "bounded_generated_lut; target_accuracy_compares_clamped_srgb_render",
        "train_mean_target": evaluator.lut_stability(train_mean),
        "prediction_output_variance": {"mean": float(output_variance.mean()), "max": float(output_variance.max())},
        "decoder_residual_logit_variance": {"mean": float(residual_matrix.var(axis=0).mean()), "max": float(residual_matrix.var(axis=0).max())},
        "style_code_variance": {"mean": float(style_matrix.var(axis=0).mean()), "max": float(style_matrix.var(axis=0).max())},
        "target_output_variance": {"mean": float(target_variance.mean()), "max": float(target_variance.max())},
        "variance_retention_ratio": float(output_variance.mean() / target_variance.mean()) if target_variance.mean() else None,
        "overall": aggregate_group(rows),
        "lut_macro": baseline.aggregate_by_source_lut(rows),
        "by_group": by_group,
        "per_sample": rows,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(f"MVP bottleneck analysis complete -> {args.output}")


if __name__ == "__main__":
    main()
