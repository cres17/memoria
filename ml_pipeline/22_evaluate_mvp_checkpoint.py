"""Evaluate the bounded MVP checkpoint on a fixed conditional split."""

from __future__ import annotations

import argparse
import importlib
import json
from pathlib import Path

import numpy as np
import torch


PIPELINE_DIR = Path(__file__).resolve().parent
CHECKPOINT = PIPELINE_DIR / "checkpoints" / "conditional_lut_mvp_17.pt"
MASK_PATH = PIPELINE_DIR / "reports" / "hue_masks" / "hue_coverage_17.npz"
OUTPUT = PIPELINE_DIR / "reports" / "mvp" / "mvp_checkpoint_validation_report.json"
mvp = importlib.import_module("20_train_conditional_lut_mvp")
baseline = importlib.import_module("18_evaluate_conditional_baselines")
evaluator = importlib.import_module("17_evaluate_conditional_lut")


def load_masks(path: Path) -> dict[str, np.ndarray]:
    with np.load(path) as archive:
        return {str(i): m.astype(bool) for i, m in zip(archive["ids"].astype(str), archive["observed_cube_mask"])}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--checkpoint", type=Path, default=CHECKPOINT)
    parser.add_argument("--partition", choices=("validation", "test"), default="validation")
    parser.add_argument("--output", type=Path, default=OUTPUT)
    parser.add_argument("--semantic-cache-dir", type=Path)
    args = parser.parse_args()
    checkpoint = torch.load(args.checkpoint, map_location=mvp.DEVICE, weights_only=False)
    semantic_cache_dir = args.semantic_cache_dir or (
        Path(checkpoint["semantic_cache_dir"]) if checkpoint.get("semantic_cache_dir") else None
    )
    dataset_dir = Path(checkpoint.get("dataset_dir", mvp.DATASET_DIR))
    mask_path = Path(checkpoint.get("mask_path", MASK_PATH))
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
    masks = load_masks(mask_path)
    records = mvp.read_split_records(
        Path(checkpoint["split_path"]), {args.partition}, dataset_dir
    )
    reports = []
    with torch.no_grad():
        for record in records:
            reference = mvp.v2.load_image_tensor(record["reference_path"]).unsqueeze(0).to(mvp.DEVICE)
            semantic_masks = (mvp.load_semantic_masks(semantic_cache_dir, record["id"]).unsqueeze(0).to(mvp.DEVICE)
                              if model.semantic_pooled_features else None)
            prediction, _ = model(reference, semantic_masks)
            target = evaluator.load_lut(record["lut_path"])
            reports.append(
                evaluator.evaluate_lut_pair(
                    prediction[0].cpu().numpy(), target, mvp.CUBE_DIM, masks[record["id"]]
                )
                | {
                    "group": record["samplingGroup"],
                    "id": record["id"],
                    "source_lut": record["sourceLut"],
                }
            )
    result = {
        "checkpoint": str(args.checkpoint),
        "partition": args.partition,
        "samples": len(reports),
        "training_protocol": {
            "dataset_dir": str(dataset_dir),
            "split_path": str(checkpoint["split_path"]),
            "mask_path": str(mask_path),
            "training_sampler": checkpoint.get("training_sampler_protocol", "legacy_or_unspecified"),
            "validation_accuracy": checkpoint.get("validation_accuracy_protocol", "legacy_or_unspecified"),
            "validation_style": checkpoint.get("validation_style_protocol", "legacy_or_unspecified"),
            "checkpoint_selection_metric": checkpoint.get("checkpoint_selection_metric", "legacy_or_unspecified"),
        },
        "overall": baseline.aggregate(reports),
        "lut_macro": baseline.aggregate_by_source_lut(reports),
        "by_group": {
            group: baseline.aggregate([report for report in reports if report["group"] == group])
            for group in mvp.SOURCE_GROUPS
        },
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(f"MVP checkpoint evaluation complete -> {args.output}")


if __name__ == "__main__":
    main()
