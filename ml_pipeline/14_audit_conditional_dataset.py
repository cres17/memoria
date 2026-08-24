"""Audit whether the generated LUT triplets support conditional LUT generation.

The existing dataset was created for LUT-target regression.  This tool does
not change it: it records the integrity, reuse, and hue-coverage facts needed
before creating the conditional generation MVP split.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from collections import Counter, defaultdict
from datetime import UTC, datetime
from pathlib import Path

import numpy as np
from PIL import Image


PIPELINE_DIR = Path(__file__).resolve().parent
DEFAULT_DATASET_DIR = PIPELINE_DIR / "data" / "dataset"
DEFAULT_REPORT_PATH = PIPELINE_DIR / "reports" / "dataset_audit.json"
LUT_DIM = 65
LUT_BYTE_SIZE = LUT_DIM ** 3 * 3 * np.dtype(np.float16).itemsize
SOURCE_GROUP_BY_KIND = {
    "cube": "crawled",
    "bin": "app",
    "canon_clog2": "canon",
    "canon_clog3": "canon",
}


class UnionFind:
    def __init__(self):
        self.parent = {}

    def find(self, item: str) -> str:
        parent = self.parent.setdefault(item, item)
        if parent != item:
            self.parent[item] = self.find(parent)
        return self.parent[item]

    def union(self, left: str, right: str) -> None:
        left_root = self.find(left)
        right_root = self.find(right)
        if left_root != right_root:
            self.parent[right_root] = left_root


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def summarize_counts(values: list[int]) -> dict:
    if not values:
        return {"count": 0, "min": None, "max": None, "mean": None}
    array = np.asarray(values, dtype=np.float64)
    return {
        "count": int(array.size),
        "min": int(array.min()),
        "max": int(array.max()),
        "mean": float(array.mean()),
    }


def rgb_to_hsv_bins(image: np.ndarray, bins: int, min_saturation: float) -> tuple[np.ndarray, float]:
    """Return hue-bin pixel counts and mean value for one RGB image."""
    rgb = image.astype(np.float32) / 255.0
    maximum = rgb.max(axis=2)
    minimum = rgb.min(axis=2)
    delta = maximum - minimum

    hue = np.zeros_like(maximum)
    nonzero = delta > 1e-6
    red = nonzero & (maximum == rgb[..., 0])
    green = nonzero & (maximum == rgb[..., 1])
    blue = nonzero & (maximum == rgb[..., 2])
    hue[red] = ((rgb[..., 1][red] - rgb[..., 2][red]) / delta[red]) % 6.0
    hue[green] = ((rgb[..., 2][green] - rgb[..., 0][green]) / delta[green]) + 2.0
    hue[blue] = ((rgb[..., 0][blue] - rgb[..., 1][blue]) / delta[blue]) + 4.0
    hue /= 6.0

    saturation = np.zeros_like(maximum)
    nonblack = maximum > 1e-6
    saturation[nonblack] = delta[nonblack] / maximum[nonblack]
    observed = (saturation >= min_saturation) & (maximum > 0.03)
    hue_indices = np.minimum((hue[observed] * bins).astype(np.int64), bins - 1)
    return np.bincount(hue_indices, minlength=bins), float(maximum.mean())


def read_manifest(dataset_dir: Path) -> tuple[list[dict], list[dict]]:
    manifest_path = dataset_dir / "manifest.jsonl"
    records = []
    errors = []
    for line_number, line in enumerate(manifest_path.read_text().splitlines(), start=1):
        if not line.strip():
            continue
        try:
            record = json.loads(line)
        except json.JSONDecodeError as error:
            errors.append({"line": line_number, "error": f"invalid_json: {error.msg}"})
            continue
        required = {"id", "sourceImage", "sourceLut", "lutKind", "inputDomain", "samplingGroup", "samplingMode"}
        missing = sorted(required - set(record))
        if missing:
            errors.append({"line": line_number, "error": "missing_keys", "keys": missing})
            continue
        record["_line"] = line_number
        records.append(record)
    return records, errors


def audit_dataset(dataset_dir: Path, bins: int, min_saturation: float, hash_files: bool) -> dict:
    manifest_path = dataset_dir / "manifest.jsonl"
    if not manifest_path.exists():
        raise FileNotFoundError(f"manifest is missing: {manifest_path}")

    records, manifest_errors = read_manifest(dataset_dir)
    group_counts = Counter()
    kind_counts = Counter()
    domain_counts = Counter()
    source_lut_records = defaultdict(list)
    source_image_luts = defaultdict(set)
    source_image_counts = Counter()
    ids = Counter()
    validation_errors = []
    missing_files = []
    invalid_lut_sizes = []
    source_lut_missing = []
    neutral_hashes = defaultdict(list)
    lut_hashes = defaultdict(list)
    hue_pixel_counts = np.zeros(bins, dtype=np.int64)
    hue_image_counts = np.zeros(bins, dtype=np.int64)
    observed_bins_per_image = []
    brightness_means = []
    image_read_errors = []

    for record in records:
        sample_id = str(record["id"])
        ids[sample_id] += 1
        kind = record["lutKind"]
        group = record["samplingGroup"]
        domain = record["inputDomain"]
        expected_group = SOURCE_GROUP_BY_KIND.get(kind)
        expected_domain = "srgb_composed" if kind.startswith("canon_") else "srgb"
        if expected_group is None:
            validation_errors.append({"id": sample_id, "error": "unknown_lut_kind", "lut_kind": kind})
        elif group != expected_group:
            validation_errors.append({"id": sample_id, "error": "unexpected_group", "expected": expected_group, "actual": group})
        if domain != expected_domain:
            validation_errors.append({"id": sample_id, "error": "unexpected_input_domain", "expected": expected_domain, "actual": domain})

        group_counts[group] += 1
        kind_counts[kind] += 1
        domain_counts[domain] += 1
        source_lut_records[str(record["sourceLut"])].append(record)
        source_image_counts[str(record["sourceImage"])] += 1
        source_image_luts[str(record["sourceImage"])].add(str(record["sourceLut"]))

        neutral_path = dataset_dir / "neutral" / f"{sample_id}.jpg"
        graded_path = dataset_dir / "graded" / f"{sample_id}.jpg"
        lut_path = dataset_dir / "luts" / f"{sample_id}.bin"
        for label, path in (("neutral", neutral_path), ("graded", graded_path), ("lut", lut_path)):
            if not path.exists():
                missing_files.append({"id": sample_id, "kind": label, "path": str(path)})
        if lut_path.exists() and lut_path.stat().st_size != LUT_BYTE_SIZE:
            invalid_lut_sizes.append({"id": sample_id, "size": lut_path.stat().st_size, "expected": LUT_BYTE_SIZE})
        source_lut_path = Path(record["sourceLut"])
        if not source_lut_path.exists():
            source_lut_missing.append(str(source_lut_path))

        if hash_files and neutral_path.exists():
            neutral_hashes[file_sha256(neutral_path)].append(sample_id)
        if hash_files and lut_path.exists():
            lut_hashes[file_sha256(lut_path)].append(sample_id)
        if graded_path.exists():
            try:
                with Image.open(graded_path) as image:
                    pixels = np.asarray(image.convert("RGB"))
                bin_counts, brightness = rgb_to_hsv_bins(pixels, bins, min_saturation)
                hue_pixel_counts += bin_counts
                hue_image_counts += bin_counts > 0
                observed_bins_per_image.append(int(np.count_nonzero(bin_counts)))
                brightness_means.append(brightness)
            except (OSError, ValueError) as error:
                image_read_errors.append({"id": sample_id, "path": str(graded_path), "error": str(error)})

    duplicate_ids = sorted(sample_id for sample_id, count in ids.items() if count > 1)
    source_counts_by_group = {}
    sample_counts_by_lut = {}
    source_lut_group_conflicts = []
    for source_lut, lut_records in source_lut_records.items():
        groups = {record["samplingGroup"] for record in lut_records}
        if len(groups) != 1:
            source_lut_group_conflicts.append({"source_lut": source_lut, "groups": sorted(groups)})
        group = next(iter(groups))
        source_counts_by_group.setdefault(group, 0)
        source_counts_by_group[group] += 1
        sample_counts_by_lut[source_lut] = len(lut_records)

    reused_source_images = [
        {"source_image": image, "sample_count": count}
        for image, count in source_image_counts.items()
        if count > 1
    ]
    reused_source_images.sort(key=lambda item: (-item["sample_count"], item["source_image"]))
    exact_neutral_duplicates = [
        {"sha256": digest, "sample_ids": sample_ids[:20], "sample_count": len(sample_ids)}
        for digest, sample_ids in neutral_hashes.items()
        if len(sample_ids) > 1
    ]
    exact_neutral_duplicates.sort(key=lambda item: (-item["sample_count"], item["sha256"]))
    exact_lut_duplicates = [
        {"sha256": digest, "sample_ids": sample_ids[:20], "sample_count": len(sample_ids)}
        for digest, sample_ids in lut_hashes.items()
        if len(sample_ids) > 1
    ]
    exact_lut_duplicates.sort(key=lambda item: (-item["sample_count"], item["sha256"]))

    source_lut_summary = {
        group: {
            "unique_luts": source_counts_by_group.get(group, 0),
            "samples_per_lut": summarize_counts([
                len(lut_records)
                for lut_records in source_lut_records.values()
                if lut_records[0]["samplingGroup"] == group
            ]),
        }
        for group in sorted(group_counts)
    }
    split_graph = UnionFind()
    for source_image, source_luts in source_image_luts.items():
        image_node = f"image:{source_image}"
        for source_lut in source_luts:
            split_graph.union(image_node, f"lut:{source_lut}")
    components = defaultdict(lambda: {"source_images": set(), "source_luts": set(), "sample_count": 0})
    for source_image, source_luts in source_image_luts.items():
        root = split_graph.find(f"image:{source_image}")
        component = components[root]
        component["source_images"].add(source_image)
        component["source_luts"].update(source_luts)
        component["sample_count"] += source_image_counts[source_image]
    split_components = [
        {
            "source_image_count": len(component["source_images"]),
            "source_lut_count": len(component["source_luts"]),
            "sample_count": component["sample_count"],
        }
        for component in components.values()
    ]
    split_components.sort(key=lambda item: (-item["sample_count"], -item["source_lut_count"]))
    report = {
        "schema_version": 1,
        "generated_at_utc": datetime.now(UTC).isoformat(),
        "dataset_dir": str(dataset_dir),
        "manifest_path": str(manifest_path),
        "settings": {
            "hue_bins": bins,
            "min_saturation": min_saturation,
            "file_hashes": hash_files,
            "expected_lut_byte_size": LUT_BYTE_SIZE,
        },
        "summary": {
            "manifest_records": len(records),
            "manifest_errors": len(manifest_errors),
            "validation_errors": len(validation_errors),
            "missing_files": len(missing_files),
            "invalid_lut_sizes": len(invalid_lut_sizes),
            "duplicate_ids": len(duplicate_ids),
            "unique_source_luts": len(source_lut_records),
            "unique_source_images": len(source_image_counts),
            "source_image_reuse_count": len(reused_source_images),
            "exact_duplicate_neutral_groups": len(exact_neutral_duplicates),
            "exact_duplicate_lut_groups": len(exact_lut_duplicates),
        },
        "distribution": {
            "samples_by_group": dict(sorted(group_counts.items())),
            "samples_by_lut_kind": dict(sorted(kind_counts.items())),
            "samples_by_input_domain": dict(sorted(domain_counts.items())),
            "source_luts_by_group": source_lut_summary,
        },
        "integrity": {
            "manifest_errors": manifest_errors[:100],
            "validation_errors": validation_errors[:100],
            "missing_files": missing_files[:100],
            "invalid_lut_sizes": invalid_lut_sizes[:100],
            "duplicate_ids": duplicate_ids[:100],
            "missing_source_lut_paths": sorted(set(source_lut_missing))[:100],
            "source_lut_group_conflicts": source_lut_group_conflicts[:100],
            "graded_image_read_errors": image_read_errors[:100],
        },
        "leakage_risks": {
            "rule": "All samples sharing source_lut or source_image must remain in one split.",
            "reused_source_images": {
                "count": len(reused_source_images),
                "top": reused_source_images[:20],
            },
            "exact_duplicate_neutral_files": {
                "count": len(exact_neutral_duplicates),
                "top": exact_neutral_duplicates[:20],
            },
            "exact_duplicate_lut_files": {
                "count": len(exact_lut_duplicates),
                "top": exact_lut_duplicates[:20],
            },
            "strict_split_components": {
                "definition": "Connected components in the bipartite graph of source_image and source_lut. "
                              "A strict split keeping both values isolated must assign each component to one split.",
                "component_count": len(split_components),
                "largest_component": split_components[0] if split_components else None,
                "components": split_components[:20],
            },
        },
        "hue_coverage_from_graded_references": {
            "definition": "HSV hue bins with saturation >= min_saturation and value > 0.03.",
            "pixel_count_by_bin": hue_pixel_counts.tolist(),
            "image_count_by_bin": hue_image_counts.tolist(),
            "observed_bins_per_image": summarize_counts(observed_bins_per_image),
            "mean_value_per_image": {
                "count": len(brightness_means),
                "min": float(min(brightness_means)) if brightness_means else None,
                "max": float(max(brightness_means)) if brightness_means else None,
                "mean": float(np.mean(brightness_means)) if brightness_means else None,
            },
        },
        "next_actions": [
            "Build source_lut/source_image grouped train-validation-test manifests before training.",
            "Implement a per-reference hue coverage mask for observed-versus-unobserved cube evaluation.",
            "Add perceptual duplicate detection before using source_image reuse as the final scene grouping rule.",
        ],
    }
    return report


def main() -> None:
    parser = argparse.ArgumentParser(description="Audit generated LUT triplets for conditional LUT generation.")
    parser.add_argument("--dataset-dir", type=Path, default=DEFAULT_DATASET_DIR)
    parser.add_argument("--output", type=Path, default=DEFAULT_REPORT_PATH)
    parser.add_argument("--hue-bins", type=int, default=24)
    parser.add_argument("--min-saturation", type=float, default=0.05)
    parser.add_argument("--skip-file-hashes", action="store_true")
    parser.add_argument("--fail-on-errors", action="store_true")
    args = parser.parse_args()
    if args.hue_bins <= 0:
        parser.error("--hue-bins must be positive")
    if not 0.0 <= args.min_saturation <= 1.0:
        parser.error("--min-saturation must be in [0, 1]")

    report = audit_dataset(
        args.dataset_dir.resolve(),
        bins=args.hue_bins,
        min_saturation=args.min_saturation,
        hash_files=not args.skip_file_hashes,
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    summary = report["summary"]
    print(
        "dataset audit complete "
        f"records={summary['manifest_records']} "
        f"unique_luts={summary['unique_source_luts']} "
        f"unique_source_images={summary['unique_source_images']} "
        f"errors={summary['manifest_errors'] + summary['validation_errors'] + summary['missing_files'] + summary['invalid_lut_sizes']} "
        f"report={args.output}"
    )
    if args.fail_on_errors and any((
        summary["manifest_errors"],
        summary["validation_errors"],
        summary["missing_files"],
        summary["invalid_lut_sizes"],
        summary["duplicate_ids"],
    )):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
