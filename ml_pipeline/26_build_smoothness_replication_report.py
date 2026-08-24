"""Aggregate paired smoothness-weight replications under the corrected MVP protocol.

The decision rule is intentionally conservative: weight 0.04 is selected only
when it improves both sample-weighted and LUT-macro DeltaE for every paired
seed.  Otherwise the candidates are a practical tie and the lower 0.01 weight
is retained.
"""

from __future__ import annotations

import argparse
import json
import statistics
from pathlib import Path


PIPELINE_DIR = Path(__file__).resolve().parent
MVP_REPORT_DIR = PIPELINE_DIR / "reports" / "mvp"
DEFAULT_OUTPUT = PIPELINE_DIR / "reports" / "baselines" / "smoothness_multiseed_replication_report_001.json"

PAIRED_RUNS = (
    {
        "seed": 20260729,
        "weight_001": "mvp-protocol-image-weight-000-001",
        "weight_004": "mvp-protocol-smoothness-weight-040-001",
    },
    {
        "seed": 20260730,
        "weight_001": "mvp-repl-smooth-010-seed-20260730-001",
        "weight_004": "mvp-repl-smooth-040-seed-20260730-001",
    },
    {
        "seed": 20260731,
        "weight_001": "mvp-repl-smooth-010-seed-20260731-001",
        "weight_004": "mvp-repl-smooth-040-seed-20260731-001",
    },
)


def read_json(path: Path) -> dict:
    if not path.exists():
        raise FileNotFoundError(path)
    return json.loads(path.read_text())


def scalar_summary(values: list[float]) -> dict[str, float | int]:
    return {
        "count": len(values),
        "mean": float(statistics.fmean(values)),
        "std_population": float(statistics.pstdev(values)),
        "min": float(min(values)),
        "max": float(max(values)),
    }


def extract_metrics(run_name: str) -> tuple[dict, dict, dict[str, str]]:
    evaluation_path = MVP_REPORT_DIR / f"{run_name}_validation_report.json"
    bottleneck_path = MVP_REPORT_DIR / f"{run_name}_bottleneck_report.json"
    evaluation = read_json(evaluation_path)
    bottleneck = read_json(bottleneck_path)
    overall = evaluation["overall"]
    metrics = {
        "sample_delta_e2000": overall["overall"]["delta_e2000"]["mean"],
        "observed_delta_e2000": overall["observed_cube"]["delta_e2000"]["mean"],
        "unobserved_delta_e2000": overall["unobserved_cube"]["delta_e2000"]["mean"],
        "lut_macro_delta_e2000": evaluation["lut_macro"]["overall_delta_e2000"]["mean"],
        "prediction_smoothness_neighbor_l2_mean": overall["prediction_lut_quality"]["smoothness_neighbor_l2_mean"],
        "variance_retention_ratio": bottleneck["variance_retention_ratio"],
    }
    return metrics, evaluation.get("training_protocol", {}), {
        "evaluation": str(evaluation_path),
        "bottleneck": str(bottleneck_path),
    }


def summarize_candidate(rows: list[dict], metric: str) -> dict[str, float | int]:
    return scalar_summary([row[metric] for row in rows])


def main() -> None:
    parser = argparse.ArgumentParser(description="Build a paired smoothness replication report.")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()

    candidate_rows = {"0.01": [], "0.04": []}
    paired_deltas: list[dict] = []
    artifact_paths: list[dict] = []
    training_protocols: list[dict] = []
    for pair in PAIRED_RUNS:
        metrics_001, protocol_001, paths_001 = extract_metrics(pair["weight_001"])
        metrics_004, protocol_004, paths_004 = extract_metrics(pair["weight_004"])
        candidate_rows["0.01"].append({"seed": pair["seed"], "run": pair["weight_001"]} | metrics_001)
        candidate_rows["0.04"].append({"seed": pair["seed"], "run": pair["weight_004"]} | metrics_004)
        paired_deltas.append(
            {
                "seed": pair["seed"],
                "definition": "weight_004_minus_weight_001; lower DeltaE and roughness are better",
                **{metric: metrics_004[metric] - metrics_001[metric] for metric in metrics_001},
            }
        )
        artifact_paths.append({"seed": pair["seed"], "weight_001": paths_001, "weight_004": paths_004})
        training_protocols.extend([protocol_001, protocol_004])

    metrics = tuple(candidate_rows["0.01"][0].keys() - {"seed", "run"})
    candidate_summary = {
        weight: {metric: summarize_candidate(rows, metric) for metric in sorted(metrics)}
        for weight, rows in candidate_rows.items()
    }
    paired_summary = {
        metric: scalar_summary([row[metric] for row in paired_deltas]) for metric in sorted(metrics)
    }
    all_pairs_improve_accuracy = all(
        row["sample_delta_e2000"] < 0 and row["lut_macro_delta_e2000"] < 0 for row in paired_deltas
    )
    decision = (
        {
            "selected_smoothness_weight": 0.04,
            "status": "robust_improvement",
            "reason": "0.04 lowered both sample-weighted and LUT-macro DeltaE in every paired seed.",
        }
        if all_pairs_improve_accuracy
        else {
            "selected_smoothness_weight": 0.01,
            "status": "practical_tie",
            "reason": "0.04 did not lower both sample-weighted and LUT-macro DeltaE in every paired seed; retain the lower regularization weight.",
        }
    )
    report = {
        "schema_version": 1,
        "experiment_id": "MVP-SMOOTHNESS-MULTISEED-REPLICATION-001",
        "purpose": "separate single-seed smoothness-weight effects from seed noise under the corrected full-coverage MVP protocol",
        "comparison_contract": {
            "partition": "validation",
            "samples": 343,
            "source_luts": 12,
            "weights": [0.01, 0.04],
            "paired_seeds": [pair["seed"] for pair in PAIRED_RUNS],
            "selection_rule": "select 0.04 only if each paired seed lowers both sample-weighted and LUT-macro DeltaE; otherwise practical tie and select 0.01",
        },
        "candidate_runs": candidate_rows,
        "candidate_summary": candidate_summary,
        "paired_deltas_weight_004_minus_weight_001": paired_deltas,
        "paired_delta_summary": paired_summary,
        "decision": decision,
        "training_protocols": training_protocols,
        "source_artifacts": artifact_paths,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(f"smoothness replication report complete -> {args.output}")


if __name__ == "__main__":
    main()
