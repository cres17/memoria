"""Diagnose axis-v2 validation failures without reading the test partition."""

from __future__ import annotations

import argparse
import json
from collections import defaultdict
from pathlib import Path

import numpy as np


def rank(values: np.ndarray) -> np.ndarray:
    order = np.argsort(values, kind="stable")
    ranks = np.empty(len(values), dtype=np.float64)
    ranks[order] = np.arange(len(values), dtype=np.float64)
    for value in np.unique(values):
        selected = values == value
        ranks[selected] = ranks[selected].mean()
    return ranks


def spearman(left: list[float], right: list[float]) -> float | None:
    if len(left) < 3:
        return None
    left_rank = rank(np.asarray(left, dtype=np.float64))
    right_rank = rank(np.asarray(right, dtype=np.float64))
    if left_rank.std() == 0 or right_rank.std() == 0:
        return None
    return float(np.corrcoef(left_rank, right_rank)[0, 1])


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mvp-report", type=Path, required=True)
    parser.add_argument("--baseline-report", type=Path, required=True)
    parser.add_argument("--split-path", type=Path, required=True)
    parser.add_argument("--mask-rows", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    mvp = json.loads(args.mvp_report.read_text())
    baseline = json.loads(args.baseline_report.read_text())
    interpolation = baseline["policies"]["lut_family_holdout"]["models"]["interpolation"]
    mvp_by_lut = {row["source_lut"]: row for row in mvp["lut_macro"]["per_lut"]}
    baseline_by_lut = {
        row["source_lut"]: row for row in interpolation["lut_macro"]["per_lut"]
    }
    coverage_by_id = {
        row["id"]: row["observed_cube_fraction"]
        for row in (json.loads(line) for line in args.mask_rows.read_text().splitlines() if line)
    }
    records_by_lut: dict[str, list[dict]] = defaultdict(list)
    for line in args.split_path.read_text().splitlines():
        if not line:
            continue
        record = json.loads(line)
        if record["split"] == "validation":
            records_by_lut[record["sourceLut"]].append(record)

    rows = []
    for source in sorted(mvp_by_lut):
        model = mvp_by_lut[source]
        reference = baseline_by_lut[source]
        records = records_by_lut[source]
        coverage = [coverage_by_id[record["id"]] for record in records]
        rows.append({
            "sourceLut": source,
            "group": model["group"],
            "samples": len(records),
            "observedCoverageMean": float(np.mean(coverage)),
            "observedCoverageMin": float(np.min(coverage)),
            "mvpOverallDeltaE2000": model["overall_delta_e2000"],
            "interpolationOverallDeltaE2000": reference["overall_delta_e2000"],
            "overallDifference": model["overall_delta_e2000"] - reference["overall_delta_e2000"],
            "observedDifference": model["observed_delta_e2000"] - reference["observed_delta_e2000"],
            "unobservedDifference": model["unobserved_delta_e2000"] - reference["unobserved_delta_e2000"],
        })

    group_summary = {}
    for group in sorted({row["group"] for row in rows}):
        selected = [row for row in rows if row["group"] == group]
        group_summary[group] = {
            "sourceLuts": len(selected),
            "mvpWins": sum(row["overallDifference"] < 0 for row in selected),
            "overallDifferenceMean": float(np.mean([row["overallDifference"] for row in selected])),
            "observedDifferenceMean": float(np.mean([row["observedDifference"] for row in selected])),
            "unobservedDifferenceMean": float(np.mean([row["unobservedDifference"] for row in selected])),
            "observedCoverageMean": float(np.mean([row["observedCoverageMean"] for row in selected])),
        }

    differences = [row["overallDifference"] for row in rows]
    result = {
        "schemaVersion": 1,
        "partition": "validation",
        "testSplitOpened": False,
        "sourceLuts": len(rows),
        "groupSummary": group_summary,
        "exploratorySpearman": {
            "coverageVsMvpMinusInterpolation": spearman(
                [row["observedCoverageMean"] for row in rows], differences
            ),
            "interpolationDifficultyVsMvpMinusInterpolation": spearman(
                [row["interpolationOverallDeltaE2000"] for row in rows], differences
            ),
            "sampleCountVsMvpMinusInterpolation": spearman(
                [float(row["samples"]) for row in rows], differences
            ),
        },
        "worstForMvp": sorted(rows, key=lambda row: row["overallDifference"], reverse=True)[:5],
        "bestForMvp": sorted(rows, key=lambda row: row["overallDifference"])[:5],
        "perLut": rows,
        "caveat": "Exploratory only: validation contains 10 source LUTs, so correlations are not promotion evidence.",
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({
        "groupSummary": group_summary,
        "exploratorySpearman": result["exploratorySpearman"],
        "worstForMvp": [
            {"sourceLut": Path(row["sourceLut"]).name, "difference": row["overallDifference"]}
            for row in result["worstForMvp"][:3]
        ],
    }, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
