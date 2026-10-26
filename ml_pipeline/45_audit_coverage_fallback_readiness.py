"""Audit whether coverage fallback has an independent calibration set.

The audit is deliberately read-only and does not inspect model scores from the
test partition.  It distinguishes unused physical files from genuinely unseen
LUT content by SHA-256 so copied LUT packages cannot be counted as independent
calibration evidence.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from collections import Counter, defaultdict
from pathlib import Path

import numpy as np


SUPPORTED_LUT_SUFFIXES = {".bin", ".cube"}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_jsonl(path: Path) -> list[dict]:
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


def source_summary(split_rows: list[dict], coverage_rows: list[dict]) -> dict[str, dict]:
    coverage_by_id = {row["id"]: float(row["observed_cube_fraction"]) for row in coverage_rows}
    grouped: dict[str, list[dict]] = defaultdict(list)
    for row in split_rows:
        grouped[row["sourceLut"]].append(row)

    result = {}
    for source_lut, rows in grouped.items():
        split_values = {row["split"] for row in rows}
        groups = {row["samplingGroup"] for row in rows}
        hashes = {row["sourceLutSha256"] for row in rows}
        if len(split_values) != 1 or len(groups) != 1 or len(hashes) != 1:
            raise ValueError(f"inconsistent source LUT metadata: {source_lut}")
        split = next(iter(split_values))
        # Test coverage is intentionally not summarized.  The split remains unopened.
        coverage = None
        if split != "test":
            values = [coverage_by_id[row["id"]] for row in rows]
            coverage = float(np.mean(values))
        result[source_lut] = {
            "split": split,
            "group": next(iter(groups)),
            "sha256": next(iter(hashes)),
            "records": len(rows),
            "meanObservedCoverage": coverage,
        }
    return result


def catalog_files(directories: list[Path]) -> list[Path]:
    files = []
    for directory in directories:
        if not directory.exists():
            continue
        files.extend(
            path
            for path in directory.rglob("*")
            if path.is_file() and path.suffix.lower() in SUPPORTED_LUT_SUFFIXES
        )
    return sorted(set(path.resolve() for path in files))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--split", type=Path, required=True)
    parser.add_argument("--coverage", type=Path, required=True)
    parser.add_argument("--fallback-report", type=Path, required=True)
    parser.add_argument("--catalog-dir", type=Path, action="append", default=[])
    parser.add_argument("--threshold", type=float, default=0.03)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    sources = source_summary(load_jsonl(args.split), load_jsonl(args.coverage))
    fallback = json.loads(args.fallback_report.read_text())
    used_hashes = {row["sha256"] for row in sources.values()}

    catalog = catalog_files(args.catalog_dir)
    catalog_rows = []
    for path in catalog:
        file_hash = sha256(path)
        catalog_rows.append({
            "path": str(path),
            "sha256": file_hash,
            "alreadyRepresentedByContent": file_hash in used_hashes,
        })
    unseen_hashes = sorted({
        row["sha256"] for row in catalog_rows if not row["alreadyRepresentedByContent"]
    })

    app_sources = [row for row in sources.values() if row["group"] == "app"]
    app_by_split = {}
    for split in ("train", "validation", "test"):
        selected = [row for row in app_sources if row["split"] == split]
        known_coverage = [
            row for row in selected if row["meanObservedCoverage"] is not None
        ]
        app_by_split[split] = {
            "sourceLuts": len(selected),
            "coverageInspected": len(known_coverage),
            "belowFrozenThreshold": sum(
                row["meanObservedCoverage"] < args.threshold for row in known_coverage
            ),
            "eligibleForIndependentCalibration": 0,
            "reason": (
                "already used for model fitting" if split == "train" else
                "already used for threshold exploration" if split == "validation" else
                "reserved unopened test partition"
            ),
        }

    threshold_counts = fallback.get("selectedThresholdCounts", {})
    result = {
        "schemaVersion": 1,
        "decision": "not_ready",
        "threeCharacterRatingKo": "조건부",
        "testSplitOpened": False,
        "frozenCandidateThreshold": args.threshold,
        "datasetSourceLuts": len(sources),
        "appSourceLuts": len(app_sources),
        "appBySplit": app_by_split,
        "catalog": {
            "directories": [str(path.resolve()) for path in args.catalog_dir],
            "physicalFiles": len(catalog_rows),
            "uniqueContentHashes": len({row["sha256"] for row in catalog_rows}),
            "contentAlreadyRepresented": sum(
                row["alreadyRepresentedByContent"] for row in catalog_rows
            ),
            "independentUnseenContentHashes": len(unseen_hashes),
            "unseenHashes": unseen_hashes,
        },
        "thresholdRobustness": {
            "validationSourceLuts": fallback.get("sourceLuts"),
            "looSelectedThresholdCounts": threshold_counts,
            "modalThreshold": max(
                threshold_counts,
                key=lambda value: threshold_counts[value],
                default=None,
            ),
            "pairedMeanDifference": fallback.get("lutMacroMeanDifference"),
            "bootstrap95Ci": fallback.get("bootstrap95Ci"),
        },
        "blockingFindings": [
            "No unseen LUT content is available in the local app/crawled/synthetic source catalogs.",
            "All 24 train app LUTs are contaminated for calibration and all 3 validation app LUTs were used in threshold exploration.",
            "The 3 test app LUTs remain reserved and must not be used to tune the threshold.",
            "The exploratory 95% CI still includes zero, so candidate B has not passed G4.",
        ],
        "nextAdmissionRule": {
            "requiredEvidence": (
                "Acquire a separately sourced, license-recorded app-like LUT calibration set "
                "containing both coverage < 0.03 and coverage >= 0.03 cases."
            ),
            "freezeBeforeScoring": [
                "threshold = 0.03",
                "coverage extractor settings and SHA-256",
                "MVP checkpoint SHA-256",
                "interpolation implementation SHA-256",
                "LUT-family deduplication threshold",
            ],
            "promotionGate": (
                "On the independent calibration LUTs, LUT-macro selected-minus-interpolation "
                "must be <= 0 and its paired bootstrap 95% CI upper bound must be < 0; "
                "monochrome/strong-tone strata may not regress."
            ),
        },
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({
        "decision": result["decision"],
        "threeCharacterRatingKo": result["threeCharacterRatingKo"],
        "catalog": result["catalog"],
        "appBySplit": result["appBySplit"],
        "thresholdRobustness": result["thresholdRobustness"],
    }, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
