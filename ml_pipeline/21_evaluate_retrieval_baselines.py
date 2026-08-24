"""Measure LUT retrieval and interpolation baselines without candidate leakage.

The feature is intentionally simple (global HSV histogram and RGB moments).
This is a lower-bound comparison for conditional LUT generation, not the
project's proposed model or a production retrieval system.
"""

from __future__ import annotations

import argparse
import importlib
import json
from collections import defaultdict
from pathlib import Path

import numpy as np
from PIL import Image


PIPELINE_DIR = Path(__file__).resolve().parent
DATASET_DIR = PIPELINE_DIR / "data" / "dataset"
SPLIT_DIR = PIPELINE_DIR / "reports" / "splits"
MASK_PATH = PIPELINE_DIR / "reports" / "hue_masks" / "hue_coverage_17.npz"
REPORT_DIR = PIPELINE_DIR / "reports" / "baselines"
CUBE_DIM = 17

evaluator = importlib.import_module("17_evaluate_conditional_lut")
baseline = importlib.import_module("18_evaluate_conditional_baselines")
POLICIES = ("lut_holdout", "image_holdout", "lut_family_holdout")


def load_records(path: Path, partitions: set[str]) -> list[dict]:
    records = []
    for line in path.read_text().splitlines():
        if not line:
            continue
        record = json.loads(line)
        if record["split"] in partitions:
            record["image_path"] = DATASET_DIR / "graded" / f"{record['id']}.jpg"
            record["lut_path"] = DATASET_DIR / "luts" / f"{record['id']}.bin"
            records.append(record)
    records.sort(key=lambda item: item["id"])
    if not records:
        raise ValueError(f"no records selected from {path}")
    return records


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


def image_feature(path: Path) -> np.ndarray:
    with Image.open(path) as image:
        rgb = np.asarray(image.convert("RGB").resize((128, 128)), dtype=np.float32) / 255.0
    hsv = rgb_to_hsv(rgb).reshape(-1, 3)
    histogram, _ = np.histogramdd(
        hsv, bins=(12, 4, 3), range=((0.0, 1.0), (0.0, 1.0), (0.0, 1.0))
    )
    histogram = histogram.reshape(-1).astype(np.float32)
    histogram /= max(histogram.sum(), 1.0)
    moments = np.concatenate((rgb.reshape(-1, 3).mean(axis=0), rgb.reshape(-1, 3).std(axis=0))).astype(np.float32)
    feature = np.concatenate((histogram, moments))
    return feature / max(np.linalg.norm(feature), 1e-12)


def build_lut_index(train_records: list[dict]) -> tuple[list[str], np.ndarray, dict[str, np.ndarray]]:
    features_by_source: dict[str, list[np.ndarray]] = defaultdict(list)
    lut_by_source: dict[str, np.ndarray] = {}
    for record in train_records:
        source_lut = record["sourceLut"]
        features_by_source[source_lut].append(image_feature(record["image_path"]))
        lut_by_source.setdefault(source_lut, evaluator.load_lut(record["lut_path"]))
    sources = sorted(features_by_source)
    centroids = []
    for source in sources:
        centroid = np.mean(features_by_source[source], axis=0)
        centroids.append(centroid / max(np.linalg.norm(centroid), 1e-12))
    return sources, np.stack(centroids), lut_by_source


def retrieval_predictions(feature: np.ndarray, centroids: np.ndarray, source_luts: list[str], luts: dict[str, np.ndarray], top_k: int) -> tuple[np.ndarray, np.ndarray]:
    similarities = centroids @ feature
    order = np.argsort(-similarities)
    nearest = luts[source_luts[int(order[0])]]
    selected = order[:top_k]
    # Temperature is fixed for comparability; interpolation is bounded because target rendering is bounded.
    weights = np.exp((similarities[selected] - similarities[selected].max()) / 0.07)
    weights /= weights.sum()
    interpolated = sum(float(weight) * luts[source_luts[int(index)]] for weight, index in zip(weights, selected))
    return nearest, np.clip(interpolated, 0.0, 1.0)


def load_masks() -> dict[str, np.ndarray]:
    with np.load(MASK_PATH) as archive:
        if int(archive["cube_dim"]) != CUBE_DIM:
            raise RuntimeError("mask dimension does not match retrieval evaluator")
        return {str(sample): mask.astype(bool) for sample, mask in zip(archive["ids"].astype(str), archive["observed_cube_mask"])}


def evaluate_policy(
    policy: str,
    partitions: set[str],
    max_samples: int | None,
    top_k: int,
    masks: dict[str, np.ndarray],
) -> dict:
    all_records = load_records(SPLIT_DIR / f"conditional_{policy}.jsonl", {"train", "validation", "test"})
    train_records = [record for record in all_records if record["split"] == "train"]
    query_records = [record for record in all_records if record["split"] in partitions]
    if max_samples is not None:
        query_records = query_records[:max_samples]
    sources, centroids, train_luts = build_lut_index(train_records)
    reports = {"retrieval": [], "interpolation": []}
    for record in query_records:
        predicted_retrieval, predicted_interpolation = retrieval_predictions(
            image_feature(record["image_path"]), centroids, sources, train_luts, top_k
        )
        target = evaluator.load_lut(record["lut_path"])
        for name, prediction in (("retrieval", predicted_retrieval), ("interpolation", predicted_interpolation)):
            reports[name].append(
                evaluator.evaluate_lut_pair(prediction, target, CUBE_DIM, masks[record["id"]])
                | {
                    "id": record["id"],
                    "group": record["samplingGroup"],
                    "source_lut": record["sourceLut"],
                }
            )
    return {
        "policy": policy,
        "train_samples": len(train_records),
        "query_samples": len(query_records),
        "candidate_luts": len(sources),
        "models": {
            name: {
                "overall": baseline.aggregate(items),
                "lut_macro": baseline.aggregate_by_source_lut(items),
                "by_group": {
                    group: baseline.aggregate([item for item in items if item["group"] == group])
                    for group in ("crawled", "app", "canon")
                },
            }
            for name, items in reports.items()
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Evaluate leakage-safe LUT retrieval baselines.")
    parser.add_argument("--policies", nargs="+", choices=POLICIES, default=("lut_holdout", "image_holdout"))
    parser.add_argument("--top-k", type=int, default=3)
    parser.add_argument(
        "--partitions",
        nargs="+",
        choices=("validation", "test"),
        default=("validation", "test"),
    )
    parser.add_argument("--max-samples", type=int)
    parser.add_argument("--output", type=Path, default=REPORT_DIR / "retrieval_baseline_report.json")
    args = parser.parse_args()
    if args.top_k <= 0 or args.max_samples is not None and args.max_samples <= 0:
        parser.error("top-k and max-samples must be positive")
    masks = load_masks()
    report = {
        "schema_version": 1,
        "feature": "normalized 12x4x3 HSV histogram plus RGB mean/std on graded reference",
        "candidate_contract": "each policy searches only source LUTs present in that policy's train partition",
        "interpolation_top_k": args.top_k,
        "partitions": list(args.partitions),
        "policies": {
            policy: evaluate_policy(policy, set(args.partitions), args.max_samples, args.top_k, masks)
            for policy in args.policies
        },
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(f"retrieval baselines complete -> {args.output}")


if __name__ == "__main__":
    main()
