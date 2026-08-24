"""Build a LUT-family holdout split from clamped 17^3 LUT-output similarity.

Families are connected components of unique source LUTs whose 17^3 rendered
output RMSE is at most the configured threshold.  The split keeps an entire
family in one partition, so it measures generalization beyond near-duplicate
LUT looks without changing the source dataset or existing dual splits.
"""

from __future__ import annotations

import argparse
import importlib
import json
from collections import Counter, defaultdict
from pathlib import Path

import numpy as np


PIPELINE_DIR = Path(__file__).resolve().parent
DATASET_DIR = PIPELINE_DIR / "data" / "dataset"
OUTPUT_DIR = PIPELINE_DIR / "reports" / "splits"
SOURCE_GROUPS = ("crawled", "app", "canon")
mvp = importlib.import_module("20_train_conditional_lut_mvp")


class UnionFind:
    def __init__(self, size: int):
        self.parent = list(range(size))

    def find(self, item: int) -> int:
        while self.parent[item] != item:
            self.parent[item] = self.parent[self.parent[item]]
            item = self.parent[item]
        return item

    def union(self, left: int, right: int) -> None:
        left_root, right_root = self.find(left), self.find(right)
        if left_root != right_root:
            self.parent[right_root] = left_root


def read_manifest(path: Path) -> list[dict]:
    records = [json.loads(line) for line in path.read_text().splitlines() if line.strip()]
    required = {"id", "sourceLut", "samplingGroup"}
    if not records or any(required - record.keys() for record in records):
        raise ValueError("manifest must contain id, sourceLut, and samplingGroup")
    return records


def unique_lut_records(records: list[dict]) -> list[dict]:
    by_lut: dict[str, dict] = {}
    for record in records:
        previous = by_lut.setdefault(record["sourceLut"], record)
        if previous["samplingGroup"] != record["samplingGroup"]:
            raise ValueError(f"source LUT has conflicting groups: {record['sourceLut']}")
    return [by_lut[source_lut] for source_lut in sorted(by_lut)]


def family_components(records: list[dict], dataset_dir: Path, threshold: float) -> tuple[list[list[int]], np.ndarray]:
    luts = np.stack(
        [mvp.load_target_lut(dataset_dir / "luts" / f"{record['id']}.bin").reshape(-1) for record in records]
    )
    distances = np.sqrt(np.square(luts[:, None] - luts[None, :]).mean(axis=2))
    union_find = UnionFind(len(records))
    for left in range(len(records)):
        for right in range(left):
            if distances[left, right] <= threshold:
                union_find.union(left, right)
    components: dict[int, list[int]] = defaultdict(list)
    for index in range(len(records)):
        components[union_find.find(index)].append(index)
    return sorted(components.values(), key=lambda members: tuple(records[index]["sourceLut"] for index in members)), distances


def holdout_count(total: int, ratio: float, reserved: int) -> int:
    return min(total - reserved, max(1, round(total * ratio))) if total > reserved else 0


def assign_splits(families: list[dict], seed: int, validation_ratio: float, test_ratio: float) -> dict[str, str]:
    by_group: dict[str, list[dict]] = defaultdict(list)
    for family in families:
        groups = {member["samplingGroup"] for member in family["members"]}
        if len(groups) != 1:
            raise ValueError(f"family crosses source groups: {family['id']} -> {sorted(groups)}")
        by_group[next(iter(groups))].append(family)
    rng = np.random.default_rng(seed)
    assignment = {}
    for group in SOURCE_GROUPS:
        candidates = sorted(by_group[group], key=lambda family: family["id"])
        if len(candidates) < 3:
            raise ValueError(f"{group} needs at least three families for train/validation/test")
        shuffled = [candidates[index] for index in rng.permutation(len(candidates))]
        validation_count = holdout_count(len(shuffled), validation_ratio, reserved=2)
        test_count = holdout_count(len(shuffled), test_ratio, reserved=1 + validation_count)
        for family in shuffled[:validation_count]:
            assignment[family["id"]] = "validation"
        for family in shuffled[validation_count:validation_count + test_count]:
            assignment[family["id"]] = "test"
        for family in shuffled[validation_count + test_count:]:
            assignment[family["id"]] = "train"
    return assignment


def main() -> None:
    parser = argparse.ArgumentParser(description="Create a non-destructive LUT-family holdout split.")
    parser.add_argument("--dataset-dir", type=Path, default=DATASET_DIR)
    parser.add_argument("--output-dir", type=Path, default=OUTPUT_DIR)
    parser.add_argument("--seed", type=int, default=20260729)
    parser.add_argument("--distance-threshold", type=float, default=0.08)
    parser.add_argument("--validation-ratio", type=float, default=0.10)
    parser.add_argument("--test-ratio", type=float, default=0.10)
    args = parser.parse_args()
    if args.distance_threshold <= 0.0 or not 0.0 < args.validation_ratio < 1.0 or not 0.0 < args.test_ratio < 1.0:
        parser.error("threshold and ratios must be positive")
    if args.validation_ratio + args.test_ratio >= 1.0:
        parser.error("validation_ratio + test_ratio must be less than one")

    records = read_manifest(args.dataset_dir / "manifest.jsonl")
    unique_records = unique_lut_records(records)
    components, distances = family_components(unique_records, args.dataset_dir, args.distance_threshold)
    families = []
    family_by_lut = {}
    for number, component in enumerate(components, start=1):
        members = [unique_records[index] for index in component]
        family_id = f"family_{number:03d}"
        families.append({"id": family_id, "members": members})
        family_by_lut.update({member["sourceLut"]: family_id for member in members})
    split_by_family = assign_splits(families, args.seed, args.validation_ratio, args.test_ratio)
    output_records = [record | {"lutFamily": family_by_lut[record["sourceLut"]], "split": split_by_family[family_by_lut[record["sourceLut"]]]} for record in records]
    crossing = defaultdict(set)
    for record in output_records:
        crossing[record["lutFamily"]].add(record["split"])
    if any(len(splits) != 1 for splits in crossing.values()):
        raise RuntimeError("family leakage detected after split assignment")

    args.output_dir.mkdir(parents=True, exist_ok=True)
    manifest_path = args.output_dir / "conditional_lut_family_holdout.jsonl"
    report_path = args.output_dir / "conditional_lut_family_holdout_report.json"
    manifest_path.write_text("".join(json.dumps(record, sort_keys=True) + "\n" for record in output_records))
    finite = distances[np.triu_indices_from(distances, k=1)]
    report = {
        "schema_version": 1,
        "experiment_id": "LUT-FAMILY-HOLDOUT-001",
        "method": "connected components over clamped 17^3 LUT-output RMSE",
        "seed": args.seed,
        "distance_threshold": args.distance_threshold,
        "validation_ratio": args.validation_ratio,
        "test_ratio": args.test_ratio,
        "unique_source_luts": len(unique_records),
        "family_count": len(families),
        "family_sizes": dict(sorted(Counter(len(family["members"]) for family in families).items())),
        "pairwise_rmse_quantiles": {str(quantile): float(np.quantile(finite, quantile)) for quantile in (0.01, 0.05, 0.10, 0.25, 0.50)},
        "families": [{"id": family["id"], "source_luts": [member["sourceLut"] for member in family["members"]], "group": family["members"][0]["samplingGroup"], "split": split_by_family[family["id"]]} for family in families],
        "summary": {split: {"samples": sum(record["split"] == split for record in output_records), "families": sum(split_by_family[family["id"]] == split for family in families), "groups": dict(Counter(record["samplingGroup"] for record in output_records if record["split"] == split))} for split in ("train", "validation", "test")},
        "family_leakage_count": sum(len(splits) != 1 for splits in crossing.values()),
        "manifest": str(manifest_path),
    }
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(f"LUT family holdout complete -> {manifest_path} {report_path}")


if __name__ == "__main__":
    main()
