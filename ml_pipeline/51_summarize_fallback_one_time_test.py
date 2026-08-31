"""Summarize the immutable one-time test report without rescoring the test set."""

from __future__ import annotations

import argparse
import json
from collections import defaultdict
from pathlib import Path

import numpy as np


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--test-report", type=Path, required=True)
    parser.add_argument("--split", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    report = json.loads(args.test_report.read_text())
    if report.get("partition") != "test" or not report.get("testSplitOpened"):
        raise ValueError("expected an immutable one-time test report")
    groups = {
        row["sourceLut"]: row["samplingGroup"]
        for row in (json.loads(line) for line in args.split.read_text().splitlines() if line)
        if row["split"] == "test"
    }
    by_group = defaultdict(list)
    for row in report["perLut"]:
        by_group[groups[row["sourceLut"]]].append(row)
    summary = {}
    for group, rows in sorted(by_group.items()):
        summary[group] = {
            "sourceLuts": len(rows),
            "usedInterpolation": sum(row["usedInterpolation"] for row in rows),
            "meanCoverage": float(np.mean([row["coverage"] for row in rows])),
            "meanSelectedMinusInterpolation": float(np.mean([
                row["selectedMinusInterpolation"] for row in rows
            ])),
            "meanForcedMvpMinusInterpolation": float(np.mean([
                row["mvpDeltaE2000"] - row["interpolationDeltaE2000"] for row in rows
            ])),
        }
    result = {
        "schemaVersion": 1,
        "sourceReportSha256": report["inputSha256"],
        "threshold": report["threshold"],
        "sourceLuts": report["sourceLuts"],
        "usedInterpolation": report["usedInterpolation"],
        "lutMacroMeanDifference": report["lutMacroMeanDifference"],
        "bootstrap95Ci": report["bootstrap95Ci"],
        "strictG4Passed": report["bootstrap95Ci"][1] < 0,
        "byGroup": summary,
        "decision": "promote_to_g5_deployment_parity_only",
        "threeCharacterReleaseRatingKo": "조건부",
        "caveat": "Test was evaluated once. Do not tune or rescore threshold/model on this partition.",
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
