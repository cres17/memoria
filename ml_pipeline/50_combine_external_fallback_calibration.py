"""Combine independent high/low coverage branch reports into one gate."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np


def bootstrap_ci(values: np.ndarray, samples: int, seed: int) -> list[float]:
    rng = np.random.default_rng(seed)
    indices = rng.integers(0, len(values), size=(samples, len(values)))
    return [float(x) for x in np.percentile(values[indices].mean(axis=1), (2.5, 97.5))]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--high", type=Path, required=True)
    parser.add_argument("--low", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--bootstrap-samples", type=int, default=50000)
    parser.add_argument("--seed", type=int, default=20260828)
    args = parser.parse_args()
    high = json.loads(args.high.read_text())
    low = json.loads(args.low.read_text())
    if high["threshold"] != low["threshold"] or high["testSplitOpened"] or low["testSplitOpened"]:
        raise ValueError("incompatible or test-contaminated calibration reports")
    rows = high["perLut"] + low["perLut"]
    differences = np.asarray([row["selectedMinusInterpolation"] for row in rows])
    low_misroutes = sum(not row["usedInterpolation"] for row in low["perLut"])
    high_misroutes = sum(row["usedInterpolation"] for row in high["perLut"])
    ci = bootstrap_ci(differences, args.bootstrap_samples, args.seed)
    gate = ci[1] < 0 and low_misroutes == 0 and high_misroutes == 0
    result = {
        "schemaVersion": 1, "testSplitOpened": False,
        "threshold": high["threshold"], "sourceLuts": len(rows),
        "highCoverageSourceLuts": high["sourceLuts"],
        "lowCoverageSourceLuts": low["sourceLuts"],
        "trainingContentOverlap": high["trainingContentOverlap"] + low["trainingContentOverlap"],
        "lowCoverageRoutingRecall": 1.0 - low_misroutes / low["sourceLuts"],
        "highCoverageRoutingRecall": 1.0 - high_misroutes / high["sourceLuts"],
        "lutMacroSelectedDeltaE2000": float(np.mean([row["selectedDeltaE2000"] for row in rows])),
        "lutMacroInterpolationDeltaE2000": float(np.mean([row["interpolationDeltaE2000"] for row in rows])),
        "lutMacroMeanDifference": float(np.mean(differences)),
        "bootstrap95Ci": ci,
        "calibrationGatePassed": gate,
        "decision": "eligible_for_one_time_test" if gate else "hold",
        "sourceReports": [str(args.high), str(args.low)],
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
