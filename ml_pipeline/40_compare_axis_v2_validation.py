"""Compare an axis-v2 MVP validation report with its interpolation baseline."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np


PIPELINE_DIR = Path(__file__).resolve().parent


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mvp-report", type=Path, required=True)
    parser.add_argument("--baseline-report", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--bootstrap-samples", type=int, default=20_000)
    parser.add_argument("--seed", type=int, default=20260828)
    args = parser.parse_args()

    mvp = json.loads(args.mvp_report.read_text())
    baseline = json.loads(args.baseline_report.read_text())
    interpolation = baseline["policies"]["lut_family_holdout"]["models"]["interpolation"]
    mvp_luts = {
        row["source_lut"]: row["overall_delta_e2000"]
        for row in mvp["lut_macro"]["per_lut"]
    }
    baseline_luts = {
        row["source_lut"]: row["overall_delta_e2000"]
        for row in interpolation["lut_macro"]["per_lut"]
    }
    if mvp_luts.keys() != baseline_luts.keys():
        raise ValueError("MVP and interpolation reports do not contain the same source LUTs")
    sources = sorted(mvp_luts)
    differences = np.asarray(
        [mvp_luts[source] - baseline_luts[source] for source in sources], dtype=np.float64
    )
    rng = np.random.default_rng(args.seed)
    sampled = rng.choice(differences, size=(args.bootstrap_samples, len(differences)), replace=True)
    bootstrap_means = sampled.mean(axis=1)
    ci_low, ci_high = np.quantile(bootstrap_means, (0.025, 0.975))
    mvp_sample = mvp["overall"]["overall"]["delta_e2000"]["mean"]
    interpolation_sample = interpolation["overall"]["overall"]["delta_e2000"]["mean"]
    result = {
        "schemaVersion": 1,
        "partition": mvp["partition"],
        "sourceLuts": len(sources),
        "bootstrapSamples": args.bootstrap_samples,
        "seed": args.seed,
        "primaryMetric": "MVP minus interpolation LUT-macro mean DeltaE2000",
        "mvpSampleMeanDeltaE2000": mvp_sample,
        "interpolationSampleMeanDeltaE2000": interpolation_sample,
        "sampleMeanDifference": mvp_sample - interpolation_sample,
        "mvpLutMacroMeanDeltaE2000": float(np.mean(list(mvp_luts.values()))),
        "interpolationLutMacroMeanDeltaE2000": float(np.mean(list(baseline_luts.values()))),
        "lutMacroPairedMeanDifference": float(differences.mean()),
        "lutMacroPairedBootstrap95Ci": [float(ci_low), float(ci_high)],
        "lutsWhereMvpWins": int(np.count_nonzero(differences < 0.0)),
        "passedStrictGate": bool(ci_high < 0.0),
        "perLut": [
            {
                "sourceLut": source,
                "mvpDeltaE2000": mvp_luts[source],
                "interpolationDeltaE2000": baseline_luts[source],
                "difference": mvp_luts[source] - baseline_luts[source],
            }
            for source in sources
        ],
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({key: result[key] for key in (
        "sampleMeanDifference",
        "lutMacroPairedMeanDifference",
        "lutMacroPairedBootstrap95Ci",
        "lutsWhereMvpWins",
        "passedStrictGate",
    )}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
