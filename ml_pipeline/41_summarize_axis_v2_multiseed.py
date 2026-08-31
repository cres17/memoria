"""Summarize validation-only axis-v2 seed runs without opening the test split."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report-dir", type=Path, required=True)
    parser.add_argument("--comparison-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--seeds", type=int, nargs="+", required=True)
    args = parser.parse_args()

    runs = []
    for seed in args.seeds:
        train = json.loads(
            (args.report_dir / f"axis-v2-smooth010-seed-{seed}_train_report.json").read_text()
        )
        comparison = json.loads(
            (args.comparison_dir / f"axis_v2_001_seed_{seed}_validation_comparison.json").read_text()
        )
        runs.append({
            "seed": seed,
            "completedEpochs": train["completed_epochs"],
            "bestEpoch": train["best_epoch"],
            "bestValidationCubeLoss": train["best_validation_cube_loss"],
            "stoppedEarly": train["stopped_early"],
            "sampleMeanDifference": comparison["sampleMeanDifference"],
            "lutMacroPairedMeanDifference": comparison["lutMacroPairedMeanDifference"],
            "lutMacroPairedBootstrap95Ci": comparison["lutMacroPairedBootstrap95Ci"],
            "lutsWhereMvpWins": comparison["lutsWhereMvpWins"],
            "passedStrictGate": comparison["passedStrictGate"],
        })

    ordered = sorted(runs, key=lambda row: row["lutMacroPairedMeanDifference"])
    representative = ordered[len(ordered) // 2]
    macro_differences = np.asarray(
        [row["lutMacroPairedMeanDifference"] for row in runs], dtype=np.float64
    )
    passed = [row for row in runs if row["passedStrictGate"]]
    result = {
        "schemaVersion": 1,
        "selectionData": "validation only",
        "testSplitOpened": False,
        "runs": runs,
        "summary": {
            "seeds": len(runs),
            "strictGatePasses": len(passed),
            "sampleMeanImprovedSeeds": sum(row["sampleMeanDifference"] < 0 for row in runs),
            "lutMacroMeanDifferenceMean": float(macro_differences.mean()),
            "lutMacroMeanDifferenceStd": float(macro_differences.std(ddof=0)),
            "medianRepresentativeSeed": representative["seed"],
            "passedG4": bool(passed),
            "decision": (
                "select a passing seed for deployment parity"
                if passed
                else "stop before test/deployment; diagnose reference identifiability, domain gap, and source-group quality"
            ),
        },
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result["summary"], indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
