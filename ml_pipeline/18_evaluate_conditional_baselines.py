"""Evaluate Identity and V2 PCA baselines on conditional generation splits."""

from __future__ import annotations

import argparse
import importlib
import json
from collections import defaultdict
from pathlib import Path

import numpy as np
import torch


PIPELINE_DIR = Path(__file__).resolve().parent
CHECKPOINT_DIR = PIPELINE_DIR / "checkpoints"
REPORT_DIR = PIPELINE_DIR / "reports" / "baselines"
SPLIT_DIR = PIPELINE_DIR / "reports" / "splits"
MASK_ARCHIVE = PIPELINE_DIR / "reports" / "hue_masks" / "hue_coverage_17.npz"
v2 = importlib.import_module("11_train_basis_v2")
evaluator = importlib.import_module("17_evaluate_conditional_lut")
POLICIES = ("lut_holdout", "image_holdout", "lut_family_holdout")


def load_records(path: Path, partitions: set[str], max_samples: int | None) -> list[dict]:
    records = []
    for line in path.read_text().splitlines():
        if not line:
            continue
        record = json.loads(line)
        if record["split"] in partitions:
            records.append(record)
    records.sort(key=lambda record: record["id"])
    return records if max_samples is None else records[:max_samples]


def load_masks(path: Path) -> dict[str, np.ndarray]:
    with np.load(path) as archive:
        if int(archive["cube_dim"]) != v2.BASIS_DIM:
            raise ValueError("mask cube dimension must match V2 basis dimension")
        return {
            str(sample_id): mask.astype(bool)
            for sample_id, mask in zip(archive["ids"].astype(str), archive["observed_cube_mask"])
        }


def load_v2_model(checkpoint_path: Path) -> tuple[torch.nn.Module, np.ndarray, np.ndarray]:
    checkpoint = torch.load(checkpoint_path, map_location=v2.DEVICE, weights_only=False)
    basis_path = Path(checkpoint["basis_path"])
    raw = np.load(basis_path)
    if str(raw["coefficient_space"]) != "normalized_scaled_bases":
        raise RuntimeError("unexpected V2 coefficient space")
    mean = raw["mean"].reshape(-1).astype(np.float32)
    bases = raw["bases"].reshape(raw["bases"].shape[0], -1).astype(np.float32)
    model = v2.BasisResidualNetV2(bases.shape[0], pretrained=False).to(v2.DEVICE)
    model.load_state_dict(checkpoint["state_dict"])
    model.eval()
    return model, mean, bases


def aggregate(pair_reports: list[dict]) -> dict:
    if not pair_reports:
        return {"samples": 0}

    def weighted(section: str, metric: str) -> dict:
        values = [report[section][metric] for report in pair_reports if report.get(section)]
        if metric == "delta_e2000":
            total = sum(item["count"] for item in values)
            return {
                "count": total,
                "mean": sum(item["count"] * item["mean"] for item in values) / total if total else None,
                "max": max(item["max"] for item in values) if values else None,
            }
        return {"mean": float(np.mean(values)) if values else None}

    overall_mse = [report["overall"]["rgb_mse"] for report in pair_reports]
    result = {
        "samples": len(pair_reports),
        "overall": {
            "rgb_mae": weighted("overall", "rgb_mae")["mean"],
            "rgb_mse": float(np.mean(overall_mse)),
            "rgb_rmse": float(np.sqrt(np.mean(overall_mse))),
            "delta_e2000": weighted("overall", "delta_e2000"),
        },
        "observed_cube": {
            "rgb_mae": weighted("observed_cube", "rgb_mae")["mean"],
            "rgb_rmse": weighted("observed_cube", "rgb_rmse")["mean"],
            "delta_e2000": weighted("observed_cube", "delta_e2000"),
        },
        "unobserved_cube": {
            "rgb_mae": weighted("unobserved_cube", "rgb_mae")["mean"],
            "rgb_rmse": weighted("unobserved_cube", "rgb_rmse")["mean"],
            "delta_e2000": weighted("unobserved_cube", "delta_e2000"),
        },
    }
    for quality_key in ("prediction_lut_quality", "target_lut_quality"):
        reports = [report[quality_key] for report in pair_reports]
        result[quality_key] = {
            "smoothness_neighbor_l2_mean": float(np.mean([item["smoothness_neighbor_l2"]["mean"] for item in reports])),
            "smoothness_neighbor_l2_max": float(np.max([item["smoothness_neighbor_l2"]["max"] for item in reports])),
            "monotonicity_luminance_violation_ratio": float(np.mean([item["monotonicity_luminance_violation_ratio"] for item in reports])),
            "out_of_gamut_value_ratio": float(np.mean([item["out_of_gamut_value_ratio"] for item in reports])),
            "out_of_gamut_node_ratio": float(np.mean([item["out_of_gamut_node_ratio"] for item in reports])),
        }
    return result


def aggregate_by_source_lut(pair_reports: list[dict]) -> dict:
    """Macro-average metrics after giving every held-out source LUT equal weight."""
    grouped = defaultdict(list)
    for report in pair_reports:
        grouped[report["source_lut"]].append(report)
    if not grouped:
        return {"source_luts": 0}
    per_lut = []
    for source_lut, reports in sorted(grouped.items()):
        metrics = aggregate(reports)
        per_lut.append({
            "source_lut": source_lut,
            "group": reports[0]["group"],
            "samples": len(reports),
            "overall_delta_e2000": metrics["overall"]["delta_e2000"]["mean"],
            "observed_delta_e2000": metrics["observed_cube"]["delta_e2000"]["mean"],
            "unobserved_delta_e2000": metrics["unobserved_cube"]["delta_e2000"]["mean"],
            "overall_rgb_rmse": metrics["overall"]["rgb_rmse"],
        })

    def summary(key: str) -> dict:
        values = np.asarray([item[key] for item in per_lut], dtype=np.float64)
        return {
            "mean": float(values.mean()),
            "median": float(np.median(values)),
            "min": float(values.min()),
            "max": float(values.max()),
        }

    return {
        "source_luts": len(per_lut),
        "overall_delta_e2000": summary("overall_delta_e2000"),
        "observed_delta_e2000": summary("observed_delta_e2000"),
        "unobserved_delta_e2000": summary("unobserved_delta_e2000"),
        "overall_rgb_rmse": summary("overall_rgb_rmse"),
        "per_lut": per_lut,
    }


def evaluate_policy(
    policy: str,
    records: list[dict],
    masks: dict[str, np.ndarray],
    batch_size: int,
    include_v2: bool,
    v2_checkpoint_path: Path,
) -> dict:
    target_luts = {
        record["id"]: evaluator.load_lut(PIPELINE_DIR / "data" / "dataset" / "luts" / f"{record['id']}.bin")
        for record in records
    }
    identity = evaluator.identity_lut(v2.BASIS_DIM)
    reports_by_model = {"identity": []}
    if include_v2:
        reports_by_model["v2_pca"] = []
        model, mean, bases = load_v2_model(v2_checkpoint_path)

    for start in range(0, len(records), batch_size):
        batch = records[start:start + batch_size]
        predicted_luts = None
        if include_v2:
            images = torch.stack([
                v2.load_image_tensor(PIPELINE_DIR / "data" / "dataset" / "graded" / f"{record['id']}.jpg")
                for record in batch
            ]).to(v2.DEVICE)
            with torch.no_grad():
                coefficients = model(images).cpu().numpy()
            predicted_luts = (mean[None, :] + coefficients @ bases).reshape(
                len(batch), v2.BASIS_DIM, v2.BASIS_DIM, v2.BASIS_DIM, 3
            )
        for index, record in enumerate(batch):
            target = target_luts[record["id"]]
            mask = masks[record["id"]]
            reports_by_model["identity"].append(
                evaluator.evaluate_lut_pair(identity, target, v2.BASIS_DIM, mask)
                | {"group": record["samplingGroup"], "id": record["id"], "source_lut": record["sourceLut"]}
            )
            if include_v2:
                reports_by_model["v2_pca"].append(
                    evaluator.evaluate_lut_pair(predicted_luts[index], target, v2.BASIS_DIM, mask)
                    | {"group": record["samplingGroup"], "id": record["id"], "source_lut": record["sourceLut"]}
                )

    models = {}
    for name, reports in reports_by_model.items():
        models[name] = {
            "overall": aggregate(reports),
            "lut_macro": aggregate_by_source_lut(reports),
            "by_group": {
                group: aggregate([report for report in reports if report["group"] == group])
                for group in v2.SOURCE_GROUPS
            },
        }
    return {"policy": policy, "samples": len(records), "models": models}


def main() -> None:
    parser = argparse.ArgumentParser(description="Evaluate Identity and V2 PCA on conditional generation splits.")
    parser.add_argument("--policies", nargs="+", choices=POLICIES, default=("lut_holdout", "image_holdout"))
    parser.add_argument("--partitions", nargs="+", choices=("validation", "test"), default=("validation", "test"))
    parser.add_argument("--batch-size", type=int, default=32)
    parser.add_argument("--max-samples", type=int)
    parser.add_argument("--identity-only", action="store_true")
    parser.add_argument("--v2-checkpoint", type=Path, default=CHECKPOINT_DIR / "basis_v2_color.pt")
    parser.add_argument("--output", type=Path, default=REPORT_DIR / "conditional_baseline_report.json")
    args = parser.parse_args()
    if args.batch_size <= 0 or args.max_samples is not None and args.max_samples <= 0:
        parser.error("batch size and max samples must be positive")

    masks = load_masks(MASK_ARCHIVE)
    result = {
        "schema_version": 1,
        "cube_dim": v2.BASIS_DIM,
        "partitions": list(args.partitions),
        "max_samples_per_policy": args.max_samples,
        "comparison_output_clipped_to_srgb": True,
        "v2_checkpoint": str(args.v2_checkpoint),
        "policies": {},
    }
    for policy in args.policies:
        records = load_records(SPLIT_DIR / f"conditional_{policy}.jsonl", set(args.partitions), args.max_samples)
        result["policies"][policy] = evaluate_policy(
            policy, records, masks, args.batch_size, include_v2=not args.identity_only,
            v2_checkpoint_path=args.v2_checkpoint,
        )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(f"conditional baselines complete -> {args.output}")


if __name__ == "__main__":
    main()
