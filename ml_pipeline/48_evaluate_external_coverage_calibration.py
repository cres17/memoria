"""Evaluate fixed MVP/interpolation routing on independent external LUTs."""

from __future__ import annotations

import argparse
import hashlib
import importlib
import json
from collections import defaultdict
from pathlib import Path

import numpy as np
import torch


mvp = importlib.import_module("20_train_conditional_lut_mvp")
retrieval = importlib.import_module("21_evaluate_retrieval_baselines")
evaluator = importlib.import_module("17_evaluate_conditional_lut")
baseline = importlib.import_module("18_evaluate_conditional_baselines")


def bootstrap_ci(values: np.ndarray, samples: int, seed: int) -> list[float]:
    rng = np.random.default_rng(seed)
    indices = rng.integers(0, len(values), size=(samples, len(values)))
    return [float(x) for x in np.percentile(values[indices].mean(axis=1), (2.5, 97.5))]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--checkpoint", type=Path, required=True)
    parser.add_argument("--train-dataset", type=Path, required=True)
    parser.add_argument("--train-split", type=Path, required=True)
    parser.add_argument("--query-dataset", type=Path, required=True)
    parser.add_argument("--query-split", type=Path, required=True)
    parser.add_argument("--query-masks", type=Path, required=True)
    parser.add_argument("--threshold", type=float, default=0.03)
    parser.add_argument("--query-partition", choices=("validation", "test"), default="validation")
    parser.add_argument("--allow-one-time-test", action="store_true")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--bootstrap-samples", type=int, default=20000)
    parser.add_argument("--seed", type=int, default=20260828)
    args = parser.parse_args()
    if args.query_partition == "test" and not args.allow_one_time_test:
        parser.error("test evaluation requires --allow-one-time-test after calibration gate passes")

    checkpoint = torch.load(args.checkpoint, map_location=mvp.DEVICE, weights_only=False)
    model = mvp.ConditionalLUTMVP(
        style_dim=int(checkpoint["style_dim"]), cube_dim=int(checkpoint["cube_dim"]),
        pretrained=False, decoder_output_mode=str(checkpoint.get("decoder_output_mode", "identity_logit")),
        decoder_hidden_dim=int(checkpoint.get("decoder_hidden_dim", 512)),
        structured_auxiliary=bool(checkpoint.get("structured_auxiliary_enabled", False)),
        semantic_pooled_features=bool(checkpoint.get("semantic_pooled_features", False)),
    ).to(mvp.DEVICE)
    model.load_state_dict(checkpoint["state_dict"])
    model.eval()

    train = retrieval.load_records(args.train_split, {"train"}, args.train_dataset)
    query = retrieval.load_records(args.query_split, {args.query_partition}, args.query_dataset)
    train_hashes = {row["sourceLutSha256"] for row in train}
    query_hashes = {row["sourceLutSha256"] for row in query}
    overlap = train_hashes & query_hashes
    if overlap:
        raise ValueError(f"external calibration LUT content overlaps training: {sorted(overlap)}")
    sources, centroids, train_luts = retrieval.build_lut_index(train)
    masks = retrieval.load_masks(args.query_masks)
    reports = defaultdict(lambda: {"mvp": [], "interpolation": [], "coverage": []})
    with torch.no_grad():
        for record in query:
            reference = mvp.v2.load_image_tensor(record["image_path"]).unsqueeze(0).to(mvp.DEVICE)
            prediction, _ = model(reference)
            _, interpolated = retrieval.retrieval_predictions(
                retrieval.image_feature(record["image_path"]), centroids, sources, train_luts, 3
            )
            target = evaluator.load_lut(record["lut_path"])
            mask = masks[record["id"]]
            reports[record["sourceLut"]]["mvp"].append(
                evaluator.evaluate_lut_pair(prediction[0].cpu().numpy(), target, 17, mask)
            )
            reports[record["sourceLut"]]["interpolation"].append(
                evaluator.evaluate_lut_pair(interpolated, target, 17, mask)
            )
            reports[record["sourceLut"]]["coverage"].append(float(mask.mean()))

    per_lut = []
    for source, values in sorted(reports.items()):
        mvp_error = baseline.aggregate(values["mvp"])["overall"]["delta_e2000"]["mean"]
        interpolation_error = baseline.aggregate(values["interpolation"])["overall"]["delta_e2000"]["mean"]
        coverage = float(np.mean(values["coverage"]))
        fallback = coverage < args.threshold
        selected = interpolation_error if fallback else mvp_error
        per_lut.append({
            "sourceLut": source, "coverage": coverage, "usedInterpolation": fallback,
            "mvpDeltaE2000": mvp_error, "interpolationDeltaE2000": interpolation_error,
            "selectedDeltaE2000": selected,
            "selectedMinusInterpolation": selected - interpolation_error,
        })
    differences = np.asarray([row["selectedMinusInterpolation"] for row in per_lut])
    result = {
        "schemaVersion": 1, "partition": args.query_partition,
        "testSplitOpened": args.query_partition == "test",
        "sourceRepository": query[0].get("sourceRepository"),
        "sourceCommit": query[0].get("sourceCommit"),
        "license": query[0].get("license"),
        "trainingContentOverlap": 0,
        "inputSha256": {
            "checkpoint": sha256(args.checkpoint),
            "trainSplit": sha256(args.train_split),
            "querySplit": sha256(args.query_split),
            "queryMasks": sha256(args.query_masks),
        },
        "threshold": args.threshold, "sourceLuts": len(per_lut),
        "usedInterpolation": sum(row["usedInterpolation"] for row in per_lut),
        "coverageRange": [min(row["coverage"] for row in per_lut), max(row["coverage"] for row in per_lut)],
        "lutMacroSelectedDeltaE2000": float(np.mean([row["selectedDeltaE2000"] for row in per_lut])),
        "lutMacroInterpolationDeltaE2000": float(np.mean([row["interpolationDeltaE2000"] for row in per_lut])),
        "lutMacroMeanDifference": float(np.mean(differences)),
        "bootstrap95Ci": bootstrap_ci(differences, args.bootstrap_samples, args.seed),
        "mvpWins": sum(row["mvpDeltaE2000"] < row["interpolationDeltaE2000"] for row in per_lut),
        "perLut": per_lut,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({key: result[key] for key in result if key != "perLut"}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
