"""Build a contract-explicit comparison for the LUT-family holdout experiment."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


PIPELINE_DIR = Path(__file__).resolve().parent
REPORT_DIR = PIPELINE_DIR / "reports"
POLICY = "lut_family_holdout"
DEFAULT_OUTPUT = REPORT_DIR / "baselines" / "family_holdout_generation_comparison_report_001.json"


def read_json(path: Path) -> dict:
    if not path.exists():
        raise FileNotFoundError(path)
    return json.loads(path.read_text())


def source(path: Path, metrics: dict) -> dict:
    return {"status": "available", "source_report": str(path), "metrics": metrics}


def baseline_models(partition: str) -> dict:
    identity_path = REPORT_DIR / "baselines" / f"family_identity_{partition}_baseline_report.json"
    retrieval_path = REPORT_DIR / "baselines" / f"family_retrieval_{partition}_baseline_report.json"
    identity = read_json(identity_path)["policies"][POLICY]["models"]["identity"]
    retrieval = read_json(retrieval_path)["policies"][POLICY]["models"]
    return {
        "identity": source(identity_path, identity),
        "retrieval": source(retrieval_path, retrieval["retrieval"]),
        "interpolation_top3": source(retrieval_path, retrieval["interpolation"]),
    }


def family_v2_model(partition: str) -> dict:
    report_path = REPORT_DIR / "baselines" / f"family_v2_{partition}_baseline_report.json"
    report = read_json(report_path)
    return source(
        report_path,
        report["policies"][POLICY]["models"]["v2_pca"],
    ) | {"checkpoint": report["v2_checkpoint"]}


def main() -> None:
    parser = argparse.ArgumentParser(description="Build the family-holdout comparison report.")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    partitions = {}
    for partition in ("validation", "test"):
        mvp_path = REPORT_DIR / "mvp" / f"mvp-family-holdout-smooth-010-001_{partition}_report.json"
        mvp = read_json(mvp_path)
        models = baseline_models(partition)
        models["conditional_lut_mvp_smooth_001"] = source(
            mvp_path,
            {
                "overall": mvp["overall"],
                "lut_macro": mvp["lut_macro"],
                "by_group": mvp["by_group"],
                "samples": mvp["samples"],
            },
        )
        direct_aux_path = REPORT_DIR / "mvp" / f"mvp-family-direct-structured-aux-010-001_{partition}_report.json"
        direct_aux = read_json(direct_aux_path)
        models["conditional_lut_mvp_parallel_structured_aux_010"] = source(
            direct_aux_path,
            {
                "overall": direct_aux["overall"],
                "lut_macro": direct_aux["lut_macro"],
                "by_group": direct_aux["by_group"],
                "samples": direct_aux["samples"],
            },
        )
        semantic_path = REPORT_DIR / "mvp" / f"mvp-family-semantic-pooled-001_{partition}_report.json"
        semantic = read_json(semantic_path)
        models["conditional_lut_mvp_semantic_pooled_001"] = source(
            semantic_path,
            {"overall": semantic["overall"], "lut_macro": semantic["lut_macro"], "by_group": semantic["by_group"], "samples": semantic["samples"]},
        )
        tone_curve_path = REPORT_DIR / "mvp" / f"mvp-family-tone-curve-001_{partition}_report.json"
        tone_curve = read_json(tone_curve_path)
        models["conditional_tone_curve_only"] = source(
            tone_curve_path,
            {
                "overall": tone_curve["overall"],
                "lut_macro": tone_curve["lut_macro"],
                "by_group": tone_curve["by_group"],
                "samples": tone_curve["samples"],
            },
        )
        hue_anchor_path = REPORT_DIR / "mvp" / f"mvp-family-tone-hue-anchor-006-001_{partition}_report.json"
        hue_anchor = read_json(hue_anchor_path)
        models["conditional_tone_curve_hue_anchor_006"] = source(
            hue_anchor_path,
            {
                "overall": hue_anchor["overall"],
                "lut_macro": hue_anchor["lut_macro"],
                "by_group": hue_anchor["by_group"],
                "samples": hue_anchor["samples"],
            },
        )
        supervised_hue_anchor_path = REPORT_DIR / "mvp" / f"mvp-family-tone-hue-anchor-006-sup-001_{partition}_report.json"
        supervised_hue_anchor = read_json(supervised_hue_anchor_path)
        models["conditional_tone_curve_hue_anchor_006_supervised"] = source(
            supervised_hue_anchor_path,
            {
                "overall": supervised_hue_anchor["overall"],
                "lut_macro": supervised_hue_anchor["lut_macro"],
                "by_group": supervised_hue_anchor["by_group"],
                "samples": supervised_hue_anchor["samples"],
            },
        )
        models["v2_pca_family_train"] = family_v2_model(partition)
        partitions[partition] = {"samples": mvp["samples"], "models": models}
    report = {
        "schema_version": 1,
        "experiment_id": "FAMILY-HOLDOUT-COMPARISON-001",
        "policy": POLICY,
        "contract": {
            "family_definition": "connected components of clamped 17^3 LUT-output RMSE at threshold 0.08",
            "family_split": "52 train / 7 validation / 7 test families; zero family leakage",
            "candidate_rule": "retrieval and interpolation search only the 94 source LUTs in the family-train partition",
            "mvp_training": "bounded direct 17^3 MVP, smoothness weight 0.01, trained only on the family-train partition",
            "mvp_parallel_structured_aux_training": "same direct full-LUT decoder plus a non-rendering 17-point Tone Curve/six-anchor Style Code auxiliary head with target Smooth L1 weight 0.10",
            "mvp_semantic_pooled_training": "same direct full-LUT decoder plus six-class semantic probability area features fused into Style Code; selected MediaPipe masks are checksum-pinned",
            "tone_curve_training": "17-point monotone luminance Tone Curve only; no hue-specific residual, trained only on the family-train partition",
            "tone_curve_hue_anchor_training": "17-point monotone luminance Tone Curve plus 6 circular saturation-scaled RGB hue anchors; trained only on the family-train partition",
            "tone_curve_hue_anchor_supervised_training": "same six-anchor decoder with model-compatible target-derived Tone Curve and anchor Smooth L1 supervision weight 0.10",
            "v2_training": "17^3 PCA basis and coefficient predictor fitted/trained only on the family-train partition",
            "model_selection": "validation only; test is reported after the fixed 8-epoch protocol and checkpoint-selection rule",
        },
        "metric_views": {
            "sample_weighted": "Every reference scene has equal weight.",
            "lut_macro": "Every held-out source LUT has equal weight after averaging its scenes.",
        },
        "partitions": partitions,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(f"family-holdout comparison report complete -> {args.output}")


if __name__ == "__main__":
    main()
