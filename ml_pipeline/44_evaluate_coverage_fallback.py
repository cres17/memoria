"""Evaluate an MVP/interpolation coverage fallback with LUT-level LOO selection.

This is a validation-only pilot.  For each held-out validation LUT, the
coverage threshold is selected using all other validation LUTs, then applied
to the held-out LUT.  It therefore avoids scoring a LUT with a threshold fit
to that same LUT, but remains too small for production promotion.
"""

from __future__ import annotations

import argparse
import json
from collections import Counter, defaultdict
from pathlib import Path

import numpy as np


THRESHOLDS = (0.0, 0.0025, 0.005, 0.0075, 0.01, 0.015, 0.02, 0.03, 0.05, 0.075, 0.10, 1.0)


def selected_error(row: dict, threshold: float) -> float:
    return (
        row["mvpOverallDeltaE2000"]
        if row["observedCoverageMean"] >= threshold
        else row["interpolationOverallDeltaE2000"]
    )


def bootstrap_ci(values: np.ndarray, samples: int, seed: int) -> list[float]:
    rng = np.random.default_rng(seed)
    means = np.empty(samples, dtype=np.float64)
    for offset in range(0, samples, 1000):
        count = min(1000, samples - offset)
        indices = rng.integers(0, len(values), size=(count, len(values)))
        means[offset : offset + count] = values[indices].mean(axis=1)
    return [float(value) for value in np.percentile(means, (2.5, 97.5))]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--diagnosis", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--bootstrap-samples", type=int, default=20000)
    parser.add_argument("--seed", type=int, default=20260830)
    args = parser.parse_args()

    diagnosis = json.loads(args.diagnosis.read_text())
    rows = diagnosis["perLut"]
    if len(rows) < 3:
        raise ValueError("coverage fallback requires at least three validation LUTs")

    loo_rows = []
    for heldout_index, heldout in enumerate(rows):
        calibration = [row for index, row in enumerate(rows) if index != heldout_index]
        scores = {
            threshold: float(np.mean([selected_error(row, threshold) for row in calibration]))
            for threshold in THRESHOLDS
        }
        # Prefer the more conservative threshold when calibration scores tie.
        threshold = min(THRESHOLDS, key=lambda value: (scores[value], -value))
        fallback = heldout["observedCoverageMean"] < threshold
        selected = selected_error(heldout, threshold)
        loo_rows.append({
            "sourceLut": heldout["sourceLut"],
            "group": heldout["group"],
            "coverage": heldout["observedCoverageMean"],
            "selectedThreshold": threshold,
            "usedInterpolation": fallback,
            "selectedDeltaE2000": selected,
            "interpolationDeltaE2000": heldout["interpolationOverallDeltaE2000"],
            "mvpDeltaE2000": heldout["mvpOverallDeltaE2000"],
            "selectedMinusInterpolation": selected - heldout["interpolationOverallDeltaE2000"],
        })

    differences = np.asarray([row["selectedMinusInterpolation"] for row in loo_rows])
    by_group = {}
    for group in sorted({row["group"] for row in loo_rows}):
        selected = [row for row in loo_rows if row["group"] == group]
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
        "method": "leave-one-source-LUT-out coverage-threshold selection",
        "coverageDefinition": "mean observed 17^3 cube fraction across reference images for a source LUT",
        "thresholdGrid": list(THRESHOLDS),
        "sourceLuts": len(loo_rows),
        "selectedThresholdCounts": dict(sorted(Counter(
            str(row["selectedThreshold"]) for row in loo_rows
        ).items())),
        "usedInterpolation": sum(row["usedInterpolation"] for row in loo_rows),
        "lutMacroSelectedDeltaE2000": float(np.mean([
            row["selectedDeltaE2000"] for row in loo_rows
        ])),
        "lutMacroInterpolationDeltaE2000": float(np.mean([
            row["interpolationDeltaE2000"] for row in loo_rows
        ])),
        "lutMacroMeanDifference": float(np.mean(differences)),
        "bootstrap95Ci": bootstrap_ci(differences, args.bootstrap_samples, args.seed),
        "byGroup": by_group,
        "perLut": loo_rows,
        "caveat": (
            "Exploratory validation-only LOO on 12 LUTs. A fixed threshold must be calibrated "
            "on separate LUT families before test or deployment."
        ),
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({
        key: result[key]
        for key in (
            "selectedThresholdCounts",
            "usedInterpolation",
            "lutMacroSelectedDeltaE2000",
            "lutMacroInterpolationDeltaE2000",
            "lutMacroMeanDifference",
            "bootstrap95Ci",
            "byGroup",
        )
    }, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
