"""Compare deployable Dart algorithmic fallback LUTs with the G4 top-3 baseline."""

from __future__ import annotations

import argparse
import hashlib
import importlib
import json
from pathlib import Path

import numpy as np


retrieval = importlib.import_module("21_evaluate_retrieval_baselines")
evaluator = importlib.import_module("17_evaluate_conditional_lut")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def bootstrap_ci(values: np.ndarray, samples: int, seed: int) -> list[float]:
    rng = np.random.default_rng(seed)
    indices = rng.integers(0, len(values), size=(samples, len(values)))
    return [float(value) for value in np.percentile(values[indices].mean(axis=1), (2.5, 97.5))]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixture-manifest", type=Path, required=True)
    parser.add_argument("--train-dataset", type=Path, required=True)
    parser.add_argument("--train-split", type=Path, required=True)
    parser.add_argument("--query-dataset", type=Path, required=True)
    parser.add_argument("--query-masks", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--bootstrap-samples", type=int, default=20_000)
    parser.add_argument("--seed", type=int, default=20260829)
    args = parser.parse_args()

    fixtures = [
        json.loads(line)
        for line in args.fixture_manifest.read_text().splitlines()
        if line.strip()
    ]
    if len(fixtures) != 31 or len({row["sourceLut"] for row in fixtures}) != 31:
        raise ValueError("expected one fixture for each of 31 monochrome source LUTs")
    if any(float(row["referenceCoverage"]) >= 0.03 for row in fixtures):
        raise ValueError("fixture contains a reference that should not use fallback")

    train = retrieval.load_records(args.train_split, {"train"}, args.train_dataset)
    sources, centroids, train_luts = retrieval.build_lut_index(train)
    masks = retrieval.load_masks(args.query_masks)
    identity_lut = evaluator.identity_lut(17)
    per_lut = []
    for row in fixtures:
        sample_id = row["id"]
        image_path = args.query_dataset / "graded" / f"{sample_id}.jpg"
        _, interpolated = retrieval.retrieval_predictions(
            retrieval.image_feature(image_path), centroids, sources, train_luts, 3
        )
        generated_path = Path(row["generatedLut"])
        generated = evaluator.load_lut(generated_path)
        target = evaluator.load_lut(Path(row["targetLut"]))
        mask = masks[sample_id]
        algorithmic = evaluator.evaluate_lut_pair(generated, target, 17, mask)
        baseline = evaluator.evaluate_lut_pair(interpolated, target, 17, mask)
        identity = evaluator.evaluate_lut_pair(identity_lut, target, 17, mask)
        algorithmic_delta = algorithmic["overall"]["delta_e2000"]["mean"]
        baseline_delta = baseline["overall"]["delta_e2000"]["mean"]
        identity_delta = identity["overall"]["delta_e2000"]["mean"]
        per_lut.append({
            "id": sample_id,
            "sourceLut": row["sourceLut"],
            "referenceCoverage": row["referenceCoverage"],
            "generatedSha256": sha256(generated_path),
            "algorithmicDeltaE2000": algorithmic_delta,
            "interpolationDeltaE2000": baseline_delta,
            "identityDeltaE2000": identity_delta,
            "algorithmicMinusInterpolation": algorithmic_delta - baseline_delta,
        })

    differences = np.asarray(
        [row["algorithmicMinusInterpolation"] for row in per_lut],
        dtype=np.float64,
    )
    algorithmic_macro = float(np.mean([
        row["algorithmicDeltaE2000"] for row in per_lut
    ]))
    interpolation_macro = float(np.mean([
        row["interpolationDeltaE2000"] for row in per_lut
    ]))
    identity_macro = float(np.mean([
        row["identityDeltaE2000"] for row in per_lut
    ]))
    ci = bootstrap_ci(differences, args.bootstrap_samples, args.seed)
    passed = float(differences.mean()) <= 0.0 and ci[1] < 0.0
    result = {
        "schemaVersion": 1,
        "scope": "31 independent monochrome LUTs, one reference per LUT",
        "routingThreshold": 0.03,
        "sourceLuts": len(per_lut),
        "algorithmicLutMacroDeltaE2000": algorithmic_macro,
        "interpolationLutMacroDeltaE2000": interpolation_macro,
        "identityLutMacroDeltaE2000": identity_macro,
        "lutMacroMeanDifference": float(differences.mean()),
        "bootstrap95Ci": ci,
        "algorithmicWins": int(np.count_nonzero(differences < 0.0)),
        "strictFallbackGatePassed": passed,
        "decision": "eligible_for_extended_validation" if passed else "reject_algorithmic_fallback",
        "caveat": (
            "This evaluates one reference per LUT. It does not replace the prior 12-reference "
            "external calibration or authorize test-set rescoring."
        ),
        "perLut": per_lut,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({key: value for key, value in result.items() if key != "perLut"}, indent=2))
    return 0 if passed else 2


if __name__ == "__main__":
    raise SystemExit(main())
