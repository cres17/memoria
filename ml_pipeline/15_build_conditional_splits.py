"""Create non-destructive evaluation splits for conditional LUT generation.

The current data forms one connected graph when both source images and source
LUTs are isolated.  It therefore cannot provide one strict split for both
unseen-style and unseen-scene evaluation.  This script writes two explicit
contracts instead of hiding that trade-off:

* lut_holdout: unseen source LUTs, while source images may overlap.
* image_holdout: unseen source images, while source LUTs may overlap.
"""

from __future__ import annotations

import argparse
import json
from collections import Counter, defaultdict
from pathlib import Path

import numpy as np


PIPELINE_DIR = Path(__file__).resolve().parent
DEFAULT_DATASET_DIR = PIPELINE_DIR / "data" / "dataset"
DEFAULT_OUTPUT_DIR = PIPELINE_DIR / "reports" / "splits"
SOURCE_GROUPS = ("crawled", "app", "canon")


def read_manifest(dataset_dir: Path) -> list[dict]:
    path = dataset_dir / "manifest.jsonl"
    if not path.exists():
        raise FileNotFoundError(f"manifest is missing: {path}")
    records = []
    for line_number, line in enumerate(path.read_text().splitlines(), start=1):
        if not line.strip():
            continue
        record = json.loads(line)
        required = {"id", "sourceImage", "sourceLut", "samplingGroup"}
        missing = sorted(required - set(record))
        if missing:
            raise ValueError(f"{path}:{line_number} is missing {missing}")
        records.append(record)
    if not records:
        raise ValueError(f"{path} has no records")
    return records


def holdout_count(total: int, ratio: float, reserved: int) -> int:
    if total <= reserved:
        return 0
    return min(total - reserved, max(1, round(total * ratio)))


def summarize(records: list[dict]) -> dict:
    by_split = defaultdict(list)
    for record in records:
        by_split[record["split"]].append(record)
    summary = {}
    for split, split_records in sorted(by_split.items()):
        summary[split] = {
            "records": len(split_records),
            "groups": dict(sorted(Counter(record["samplingGroup"] for record in split_records).items())),
            "unique_source_luts": len({record["sourceLut"] for record in split_records}),
            "unique_source_images": len({record["sourceImage"] for record in split_records}),
        }
    return summary


def cross_split_values(records: list[dict], key: str) -> dict:
    splits_by_value = defaultdict(set)
    for record in records:
        splits_by_value[record[key]].add(record["split"])
    crossing = {
        value: sorted(splits)
        for value, splits in splits_by_value.items()
        if len(splits) > 1
    }
    return {
        "count": len(crossing),
        "examples": [
            {"value": value, "splits": splits}
            for value, splits in sorted(crossing.items())[:20]
        ],
    }


def make_lut_holdout(records: list[dict], seed: int, validation_ratio: float, test_ratio: float) -> list[dict]:
    luts_by_group = defaultdict(list)
    seen = set()
    for record in records:
        source_lut = record["sourceLut"]
        if source_lut not in seen:
            luts_by_group[record["samplingGroup"]].append(source_lut)
            seen.add(source_lut)

    rng = np.random.default_rng(seed)
    split_by_lut = {}
    for group in SOURCE_GROUPS:
        source_luts = sorted(luts_by_group[group])
        if len(source_luts) < 3:
            raise ValueError(f"{group} needs at least 3 LUTs for train/validation/test holdout")
        shuffled = [source_luts[index] for index in rng.permutation(len(source_luts))]
        validation_count = holdout_count(len(shuffled), validation_ratio, reserved=2)
        test_count = holdout_count(len(shuffled), test_ratio, reserved=1 + validation_count)
        for source_lut in shuffled[:validation_count]:
            split_by_lut[source_lut] = "validation"
        for source_lut in shuffled[validation_count:validation_count + test_count]:
            split_by_lut[source_lut] = "test"
        for source_lut in shuffled[validation_count + test_count:]:
            split_by_lut[source_lut] = "train"
    return [record | {"split": split_by_lut[record["sourceLut"]]} for record in records]


def make_image_holdout(records: list[dict], seed: int, validation_ratio: float, test_ratio: float) -> list[dict]:
    source_images = sorted({record["sourceImage"] for record in records})
    if len(source_images) < 3:
        raise ValueError("at least 3 source images are required for train/validation/test holdout")
    rng = np.random.default_rng(seed)
    shuffled = [source_images[index] for index in rng.permutation(len(source_images))]
    validation_count = holdout_count(len(shuffled), validation_ratio, reserved=2)
    test_count = holdout_count(len(shuffled), test_ratio, reserved=1 + validation_count)
    split_by_image = {}
    for source_image in shuffled[:validation_count]:
        split_by_image[source_image] = "validation"
    for source_image in shuffled[validation_count:validation_count + test_count]:
        split_by_image[source_image] = "test"
    for source_image in shuffled[validation_count + test_count:]:
        split_by_image[source_image] = "train"
    return [record | {"split": split_by_image[record["sourceImage"]]} for record in records]


def write_jsonl(path: Path, records: list[dict]) -> None:
    path.write_text("".join(json.dumps(record, sort_keys=True) + "\n" for record in records))


def main() -> None:
    parser = argparse.ArgumentParser(description="Build LUT-holdout and image-holdout conditional generation splits.")
    parser.add_argument("--dataset-dir", type=Path, default=DEFAULT_DATASET_DIR)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
    parser.add_argument("--seed", type=int, default=20260728)
    parser.add_argument("--validation-ratio", type=float, default=0.10)
    parser.add_argument("--test-ratio", type=float, default=0.10)
    args = parser.parse_args()
    if not 0.0 < args.validation_ratio < 1.0 or not 0.0 < args.test_ratio < 1.0:
        parser.error("validation/test ratios must be in (0, 1)")
    if args.validation_ratio + args.test_ratio >= 1.0:
        parser.error("validation_ratio + test_ratio must be less than 1")

    records = read_manifest(args.dataset_dir.resolve())
    lut_holdout = make_lut_holdout(records, args.seed, args.validation_ratio, args.test_ratio)
    image_holdout = make_image_holdout(records, args.seed, args.validation_ratio, args.test_ratio)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    lut_path = args.output_dir / "conditional_lut_holdout.jsonl"
    image_path = args.output_dir / "conditional_image_holdout.jsonl"
    report_path = args.output_dir / "conditional_split_report.json"
    write_jsonl(lut_path, lut_holdout)
    write_jsonl(image_path, image_holdout)
    report = {
        "schema_version": 1,
        "seed": args.seed,
        "validation_ratio": args.validation_ratio,
        "test_ratio": args.test_ratio,
        "source_manifest": str(args.dataset_dir / "manifest.jsonl"),
        "policies": {
            "lut_holdout": {
                "purpose": "Measure generalization to unseen LUT styles.",
                "isolation_guarantee": "source_lut never crosses splits; source_image may cross.",
                "summary": summarize(lut_holdout),
                "cross_split_source_luts": cross_split_values(lut_holdout, "sourceLut"),
                "cross_split_source_images": cross_split_values(lut_holdout, "sourceImage"),
                "manifest": str(lut_path),
            },
            "image_holdout": {
                "purpose": "Measure generalization to unseen scene content.",
                "isolation_guarantee": "source_image never crosses splits; source_lut may cross.",
                "summary": summarize(image_holdout),
                "cross_split_source_luts": cross_split_values(image_holdout, "sourceLut"),
                "cross_split_source_images": cross_split_values(image_holdout, "sourceImage"),
                "manifest": str(image_path),
            },
        },
        "limitation": (
            "The audit found one connected source_image/source_lut component, so this dataset "
            "cannot create a non-empty split that isolates both values at once."
        ),
    }
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(
        f"conditional splits complete lut_holdout={lut_path} image_holdout={image_path} "
        f"report={report_path}"
    )


if __name__ == "__main__":
    main()
