"""Apply one pre-frozen coverage fallback threshold without tuning it."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np


def bootstrap_ci(values: np.ndarray, samples: int, seed: int) -> list[float]:
    rng = np.random.default_rng(seed)
    indices = rng.integers(0, len(values), size=(samples, len(values)))
    means = values[indices].mean(axis=1)
    return [float(value) for value in np.percentile(means, (2.5, 97.5))]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--diagnosis", type=Path, required=True)
    parser.add_argument("--threshold", type=float, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--bootstrap-samples", type=int, default=20000)
    parser.add_argument("--seed", type=int, default=20260830)
    args = parser.parse_args()

    diagnosis = json.loads(args.diagnosis.read_text())
    if diagnosis.get("partition") not in (None, "validation"):
        raise ValueError("this evaluator only accepts validation evidence")
    rows = diagnosis["perLut"]
    evaluated = []
    for row in rows:
        fallback = row["observedCoverageMean"] < args.threshold
        interpolation = row["interpolationOverallDeltaE2000"]
        mvp = row["mvpOverallDeltaE2000"]
        selected = interpolation if fallback else mvp
        evaluated.append({
            "sourceLut": row["sourceLut"],
            "group": row["group"],
            "coverage": row["observedCoverageMean"],
            "usedInterpolation": fallback,
            "selectedDeltaE2000": selected,
            "interpolationDeltaE2000": interpolation,
            "mvpDeltaE2000": mvp,
            "selectedMinusInterpolation": selected - interpolation,
        })

    differences = np.asarray(
        [row["selectedMinusInterpolation"] for row in evaluated], dtype=np.float64
    )
    by_group = {}
    for group in sorted({row["group"] for row in evaluated}):
        selected = [row for row in evaluated if row["group"] == group]
        by_group[group] = {
            "sourceLuts": len(selected),
            "usedInterpolation": sum(row["usedInterpolation"] for row in selected),
            "meanSelectedMinusInterpolation": float(np.mean([
                row["selectedMinusInterpolation"] for row in selected
            ])),
        }

    result = {
        "schemaVersion": 1,
        "partition": "validation",
        "testSplitOpened": False,
        "method": "single application of pre-frozen coverage threshold",
        "threshold": args.threshold,
        "thresholdWasTunedInThisRun": False,
        "sourceLuts": len(evaluated),
        "usedInterpolation": sum(row["usedInterpolation"] for row in evaluated),
        "lutMacroSelectedDeltaE2000": float(np.mean([
            row["selectedDeltaE2000"] for row in evaluated
        ])),
        "lutMacroInterpolationDeltaE2000": float(np.mean([
            row["interpolationDeltaE2000"] for row in evaluated
        ])),
        "lutMacroMeanDifference": float(np.mean(differences)),
        "bootstrap95Ci": bootstrap_ci(differences, args.bootstrap_samples, args.seed),
        "byGroup": by_group,
        "perLut": evaluated,
        "decision": "descriptive_only",
        "caveat": (
            "Threshold 0.03 originated from exploratory LOO on this same validation set. "
            "This one-time frozen application measures behavior but cannot independently "
            "validate or promote the fallback."
        ),
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({
        key: result[key]
        for key in (
            "threshold", "usedInterpolation", "lutMacroSelectedDeltaE2000",
            "lutMacroInterpolationDeltaE2000", "lutMacroMeanDifference",
            "bootstrap95Ci", "byGroup", "decision",
        )
    }, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
