"""Assemble conditional-LUT baselines and MVP results into one honest schema."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


PIPELINE_DIR = Path(__file__).resolve().parent
REPORT_DIR = PIPELINE_DIR / "reports"
DEFAULT_OUTPUT = REPORT_DIR / "baselines" / "conditional_generation_validation_comparison_report_001.json"
DEFAULT_MVP_REPORT = REPORT_DIR / "mvp" / "mvp-fixed-lr-4epoch-001_validation_protocol_report.json"


def read_json(path: Path) -> dict:
    if not path.exists():
        raise FileNotFoundError(path)
    return json.loads(path.read_text())


def available(result: dict, source: Path, partitions: list[str]) -> dict:
    return {"status": "available", "source_report": str(source), "partitions": partitions, "metrics": result}


def not_run(reason: str, required_artifact: str) -> dict:
    return {"status": "not_run", "reason": reason, "required_artifact": required_artifact}


def main() -> None:
    parser = argparse.ArgumentParser(description="Build one contract-explicit conditional LUT comparison report.")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--mvp-report", type=Path, default=DEFAULT_MVP_REPORT)
    parser.add_argument("--experiment-id", default="COMPARISON-PROTOCOL-001")
    args = parser.parse_args()
    baseline_path = REPORT_DIR / "baselines" / "lut_holdout_validation_baseline_report.json"
    retrieval_path = REPORT_DIR / "baselines" / "lut_holdout_validation_retrieval_report.json"
    mvp_path = args.mvp_report
    baseline = read_json(baseline_path)
    retrieval = read_json(retrieval_path)
    mvp = read_json(mvp_path)

    policy = "lut_holdout"
    policies = {
        policy: {
            "contract": "source LUT unseen; validation partition only; 343 samples and 12 source LUTs",
            "identity": available(
                baseline["policies"][policy]["models"]["identity"], baseline_path, ["validation"]
            ),
            "v2_pca_legacy": available(
                baseline["policies"][policy]["models"]["v2_pca"], baseline_path, ["validation"]
            ),
            "retrieval": available(
                retrieval["policies"][policy]["models"]["retrieval"], retrieval_path, ["validation"]
            ),
            "interpolation_top3": available(
                retrieval["policies"][policy]["models"]["interpolation"], retrieval_path, ["validation"]
            ),
            "conditional_lut_mvp": available(
                {
                    "overall": mvp["overall"],
                    "lut_macro": mvp["lut_macro"],
                    "by_group": mvp["by_group"],
                    "samples": mvp["samples"],
                },
                mvp_path,
                ["validation"],
            ),
        }
    }
    report = {
        "schema_version": 2,
        "experiment_id": args.experiment_id,
        "renderer_contract": "accuracy compares trilinear LUT outputs clamped to [0,1] sRGB; raw LUT OOG is a separate safety metric",
        "cube_dim": 17,
        "models": {
            "identity": "non-learning baseline",
            "v2_pca_legacy": "legacy PCA coefficient predictor; not the proposed generation method",
            "retrieval": "leakage-safe train-candidate lookup baseline",
            "interpolation_top3": "leakage-safe top-3 retrieved LUT interpolation baseline",
            "conditional_lut_mvp": "bounded direct Style Code to 17^3 LUT generator",
        },
        "policies": policies,
        "metric_views": {
            "sample_weighted": "Every reference scene has equal weight.",
            "lut_macro": "Every held-out source LUT has equal weight after averaging its scenes.",
        },
        "comparability_rule": "All headline values in this report use the LUT-holdout validation partition only. Report both sample-weighted and LUT-macro metrics.",
        "mvp_training_protocol": mvp.get("training_protocol", {}),
        "mvp_training_protocol_caveat": (
            "The included MVP checkpoint uses the epoch-aware full-coverage sampler, full-validation "
            "sample-weighted Cube selection, and a separate held-out Style monitor."
            if mvp.get("training_protocol", {}).get("training_sampler")
            == "epoch_aware_full_coverage_source_pairs"
            else "The included MVP checkpoint predates the full-coverage epoch-aware sampler fix. "
            "Its evaluation is valid, but it must be retrained under the corrected protocol before model selection."
        ),
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(f"conditional generation comparison report complete -> {args.output}")


if __name__ == "__main__":
    main()
