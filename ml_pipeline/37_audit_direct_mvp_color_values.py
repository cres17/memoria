"""Audit production Direct MVP LUT color values against held-out targets.

This is an offline, deterministic colorimetric audit. It runs the exact TFLite
asset shipped by the app, reproduces the app's bilinear image preprocessing,
17^3 -> 65^3 interpolation, float16 persistence, and safety-strength fallback,
then compares the persisted LUT with held-out target LUTs and the leakage-safe
interpolation top-3 baseline.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib
import json
from collections import Counter, defaultdict
from pathlib import Path

import numpy as np
from PIL import Image, ImageOps
import tensorflow as tf


PIPELINE_DIR = Path(__file__).resolve().parent
REPO_DIR = PIPELINE_DIR.parent
MODEL = REPO_DIR / "assets" / "models" / "direct_mvp_color_transfer_fp16.tflite"
SPLIT = PIPELINE_DIR / "reports" / "splits" / "conditional_lut_family_holdout.jsonl"
MASK_ARCHIVE = PIPELINE_DIR / "reports" / "hue_masks" / "hue_coverage_17.npz"
OUTPUT = PIPELINE_DIR / "reports" / "validation" / "direct_mvp_color_value_audit_001.json"
DATASET_DIR = PIPELINE_DIR / "data" / "dataset"
CUBE_DIM = 17
PERSISTED_DIM = 65
MEAN = np.asarray((0.485, 0.456, 0.406), dtype=np.float32)[:, None, None]
STD = np.asarray((0.229, 0.224, 0.225), dtype=np.float32)[:, None, None]
STRENGTH_STEPS = (1.0, 0.75, 0.5, 0.25)
MODEL_NAMES = ("direct_actual", "direct_axis_corrected", "interpolation_top3")

evaluator = importlib.import_module("17_evaluate_conditional_lut")
retrieval = importlib.import_module("21_evaluate_retrieval_baselines")


SWATCHES = {
    "black": "#000000",
    "gray_25": "#404040",
    "gray_50": "#808080",
    "gray_75": "#BFBFBF",
    "white": "#FFFFFF",
    "skin_light": "#F2C6A0",
    "skin_medium": "#C68662",
    "skin_deep": "#7D4A35",
    "red": "#CC3333",
    "yellow": "#D9B32C",
    "green": "#4F9D55",
    "cyan": "#35A7A0",
    "blue": "#3569C8",
    "magenta": "#B54FA3",
    "sky": "#6FA8DC",
    "foliage": "#5B7F3A",
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_records() -> tuple[list[dict], list[dict]]:
    rows = []
    for line in SPLIT.read_text().splitlines():
        if not line:
            continue
        row = json.loads(line)
        row["image_path"] = DATASET_DIR / "graded" / f"{row['id']}.jpg"
        row["lut_path"] = DATASET_DIR / "luts" / f"{row['id']}.bin"
        rows.append(row)
    rows.sort(key=lambda item: item["id"])
    return (
        [row for row in rows if row["split"] == "train"],
        [row for row in rows if row["split"] == "test"],
    )


def load_app_input(path: Path) -> np.ndarray:
    with Image.open(path) as opened:
        image = ImageOps.exif_transpose(opened).convert("RGB")
        image = image.resize((256, 256), resample=Image.Resampling.BILINEAR)
    rgb = np.asarray(image, dtype=np.float32).transpose(2, 0, 1) / 255.0
    return ((rgb - MEAN) / STD)[None, ...]


def load_masks() -> dict[str, np.ndarray]:
    with np.load(MASK_ARCHIVE) as archive:
        if int(archive["cube_dim"]) != CUBE_DIM:
            raise RuntimeError("hue mask dimension does not match the model cube")
        return {
            str(sample_id): mask.astype(bool)
            for sample_id, mask in zip(archive["ids"].astype(str), archive["observed_cube_mask"])
        }


def upsample_and_quantize(lut: np.ndarray) -> np.ndarray:
    colors = evaluator.cube_colors(PERSISTED_DIM)
    values = np.clip(evaluator.apply_lut(colors, lut), 0.0, 1.0)
    return values.reshape(PERSISTED_DIM, PERSISTED_DIM, PERSISTED_DIM, 3).astype(np.float16).astype(np.float32)


def safety_report(lut: np.ndarray) -> dict[str, float | int | bool]:
    interior = lut[1:-1, 1:-1, 1:-1]
    clipped = (interior <= 0.0001) | (interior >= 0.9999)
    adjacent = np.concatenate([
        np.linalg.norm(np.diff(lut, axis=axis).reshape(-1, 3), axis=1)
        for axis in range(3)
    ])
    diagonal = lut[np.arange(PERSISTED_DIM), np.arange(PERSISTED_DIM), np.arange(PERSISTED_DIM)]
    luminance = diagonal @ np.asarray((0.2126, 0.7152, 0.0722), dtype=np.float32)
    primaries = np.asarray((lut[-1, 0, 0], lut[0, -1, 0], lut[0, 0, -1]))
    primary_chroma = primaries.max(axis=1) - primaries.min(axis=1)
    report = {
        "valid_encoding": True,
        "has_non_finite_values": bool(~np.isfinite(lut).all()),
        "interior_clip_ratio": float(clipped.mean()),
        "max_adjacent_delta": float(adjacent.max()),
        "neutral_luminance_range": float(luminance[-1] - luminance[0]),
        "neutral_inversions": int(np.sum(luminance[1:] + 0.001 < luminance[:-1])),
        "primary_min_chroma": float(primary_chroma.min()),
    }
    report["is_safe"] = bool(
        not report["has_non_finite_values"]
        and report["interior_clip_ratio"] <= 0.08
        and report["max_adjacent_delta"] <= 0.35
        and report["neutral_inversions"] == 0
        and report["neutral_luminance_range"] >= 0.55
        and report["primary_min_chroma"] >= 0.05
    )
    return report


def constrain_like_app(raw_lut: np.ndarray) -> tuple[np.ndarray, float, dict]:
    source = upsample_and_quantize(np.clip(raw_lut, 0.0, 1.0))
    identity = evaluator.identity_lut(PERSISTED_DIM).astype(np.float32)
    for strength in STRENGTH_STEPS:
        candidate = source if strength == 1.0 else identity + (source - identity) * strength
        candidate = candidate.astype(np.float16).astype(np.float32)
        report = safety_report(candidate)
        if report["is_safe"]:
            return candidate, strength, report
    identity = identity.astype(np.float16).astype(np.float32)
    return identity, 0.0, safety_report(identity)


def app_axis_lut(stored_lut: np.ndarray) -> np.ndarray:
    """Convert an R-fastest persisted buffer reshaped by NumPy into RGB axes."""
    return np.transpose(stored_lut, (2, 1, 0, 3))


def hex_to_rgb(value: str) -> np.ndarray:
    return np.asarray([int(value[index:index + 2], 16) for index in (1, 3, 5)], dtype=np.float32) / 255.0


def rgb_hex(rgb: np.ndarray) -> str:
    channels = np.clip(np.rint(rgb * 255.0), 0, 255).astype(np.uint8)
    return "#" + "".join(f"{int(channel):02X}" for channel in channels)


def metric_summary(delta_e: np.ndarray, rgb_error: np.ndarray) -> dict:
    flat_delta = delta_e.reshape(-1)
    flat_rgb = rgb_error.reshape(-1)
    return {
        "color_pairs": int(flat_delta.size),
        "delta_e2000": {
            "mean": float(flat_delta.mean()),
            "median": float(np.median(flat_delta)),
            "p95": float(np.percentile(flat_delta, 95)),
            "max": float(flat_delta.max()),
            "within_2_ratio": float(np.mean(flat_delta <= 2.0)),
            "within_5_ratio": float(np.mean(flat_delta <= 5.0)),
            "within_10_ratio": float(np.mean(flat_delta <= 10.0)),
        },
        "rgb_mae": float(np.abs(flat_rgb).mean()),
        "rgb_rmse": float(np.sqrt(np.square(flat_rgb).mean())),
    }


def bootstrap_mean_ci(values: np.ndarray, seed: int = 20260828, draws: int = 20000) -> list[float]:
    generator = np.random.default_rng(seed)
    indices = generator.integers(0, values.size, size=(draws, values.size))
    means = values[indices].mean(axis=1)
    return [float(np.percentile(means, 2.5)), float(np.percentile(means, 97.5))]


def main() -> None:
    parser = argparse.ArgumentParser(description="Extract and compare Direct MVP production LUT color values.")
    parser.add_argument("--model", type=Path, default=MODEL)
    parser.add_argument("--output", type=Path, default=OUTPUT)
    parser.add_argument("--max-samples", type=int)
    args = parser.parse_args()
    if args.max_samples is not None and args.max_samples <= 0:
        parser.error("max-samples must be positive")

    train_records, test_records = read_records()
    if args.max_samples is not None:
        test_records = test_records[:args.max_samples]
    masks = load_masks()

    interpreter = tf.lite.Interpreter(model_path=str(args.model), num_threads=2)
    interpreter.allocate_tensors()
    input_detail = interpreter.get_input_details()[0]
    output_detail = interpreter.get_output_details()[0]
    if tuple(input_detail["shape"]) != (1, 3, 256, 256):
        raise RuntimeError(f"unexpected input shape: {input_detail['shape']}")
    if tuple(output_detail["shape"]) != (1, CUBE_DIM, CUBE_DIM, CUBE_DIM, 3):
        raise RuntimeError(f"unexpected output shape: {output_detail['shape']}")

    sources, centroids, train_luts = retrieval.build_lut_index(train_records)
    cube_colors = evaluator.cube_colors(CUBE_DIM)
    swatch_names = list(SWATCHES)
    swatch_colors = np.stack([hex_to_rgb(SWATCHES[name]) for name in swatch_names])

    cube_delta = defaultdict(list)
    cube_rgb_error = defaultdict(list)
    observed_delta = defaultdict(list)
    unobserved_delta = defaultdict(list)
    swatch_delta = {model: defaultdict(list) for model in MODEL_NAMES}
    swatch_rgb_error = {model: defaultdict(list) for model in MODEL_NAMES}
    swatch_output = {model: defaultdict(list) for model in ("target", *MODEL_NAMES)}
    per_sample_delta = defaultdict(list)
    per_lut_delta = defaultdict(lambda: defaultdict(list))
    per_group_delta = defaultdict(lambda: defaultdict(list))
    strength_counts = {"direct_actual": Counter(), "direct_axis_corrected": Counter()}
    safety_values = {
        "direct_actual": defaultdict(list),
        "direct_axis_corrected": defaultdict(list),
    }
    historical_delta = []
    historical_rgb_error = []

    for index, record in enumerate(test_records, start=1):
        interpreter.set_tensor(input_detail["index"], load_app_input(record["image_path"]))
        interpreter.invoke()
        raw_lut = interpreter.get_tensor(output_detail["index"])[0].astype(np.float32)
        actual_lut, actual_strength, actual_report = constrain_like_app(raw_lut)
        corrected_lut, corrected_strength, corrected_report = constrain_like_app(app_axis_lut(raw_lut))
        for model_name, strength, report in (
            ("direct_actual", actual_strength, actual_report),
            ("direct_axis_corrected", corrected_strength, corrected_report),
        ):
            strength_counts[model_name][f"{strength:.2f}"] += 1
            for key, value in report.items():
                if isinstance(value, (int, float)) and not isinstance(value, bool):
                    safety_values[model_name][key].append(float(value))

        _, interpolation_lut = retrieval.retrieval_predictions(
            retrieval.image_feature(record["image_path"]), centroids, sources, train_luts, 3
        )
        target_lut = evaluator.load_lut(record["lut_path"])
        target_cube = np.clip(evaluator.apply_lut(cube_colors, target_lut), 0.0, 1.0)
        target_swatches = np.clip(evaluator.apply_lut(swatch_colors, target_lut), 0.0, 1.0)
        swatch_output["target"]["values"].append(target_swatches)

        historical_target_cube = np.clip(
            evaluator.apply_lut(cube_colors, app_axis_lut(target_lut)), 0.0, 1.0
        )
        historical_output_cube = np.clip(evaluator.apply_lut(cube_colors, raw_lut), 0.0, 1.0)
        historical_error = historical_output_cube - historical_target_cube
        historical_rgb_error.append(historical_error)
        historical_delta.append(evaluator.delta_e2000(
            evaluator.rgb_to_lab(historical_output_cube), evaluator.rgb_to_lab(historical_target_cube)
        ))

        candidates = {
            "direct_actual": actual_lut,
            "direct_axis_corrected": corrected_lut,
            "interpolation_top3": interpolation_lut,
        }
        mask = masks[record["id"]]
        for model_name, candidate in candidates.items():
            output_cube = np.clip(evaluator.apply_lut(cube_colors, candidate), 0.0, 1.0)
            rgb_error = output_cube - target_cube
            delta = evaluator.delta_e2000(evaluator.rgb_to_lab(output_cube), evaluator.rgb_to_lab(target_cube))
            cube_delta[model_name].append(delta)
            cube_rgb_error[model_name].append(rgb_error)
            observed_delta[model_name].append(delta[mask])
            unobserved_delta[model_name].append(delta[~mask])
            sample_mean = float(delta.mean())
            per_sample_delta[model_name].append(sample_mean)
            per_lut_delta[record["sourceLut"]][model_name].append(sample_mean)
            per_group_delta[record["samplingGroup"]][model_name].append(sample_mean)

            output_swatches = np.clip(evaluator.apply_lut(swatch_colors, candidate), 0.0, 1.0)
            delta_swatches = evaluator.delta_e2000(
                evaluator.rgb_to_lab(output_swatches), evaluator.rgb_to_lab(target_swatches)
            )
            swatch_output[model_name]["values"].append(output_swatches)
            for swatch_index, swatch_name in enumerate(swatch_names):
                swatch_delta[model_name][swatch_name].append(float(delta_swatches[swatch_index]))
                swatch_rgb_error[model_name][swatch_name].append(output_swatches[swatch_index] - target_swatches[swatch_index])

        if index % 50 == 0 or index == len(test_records):
            print(f"processed {index}/{len(test_records)}", flush=True)

    models = {}
    for model_name in MODEL_NAMES:
        delta = np.concatenate(cube_delta[model_name])
        rgb_error = np.concatenate(cube_rgb_error[model_name])
        models[model_name] = metric_summary(delta, rgb_error) | {
            "observed_delta_e2000": metric_summary(
                np.concatenate(observed_delta[model_name]), np.zeros((sum(value.size for value in observed_delta[model_name]), 1))
            )["delta_e2000"],
            "unobserved_delta_e2000": metric_summary(
                np.concatenate(unobserved_delta[model_name]), np.zeros((sum(value.size for value in unobserved_delta[model_name]), 1))
            )["delta_e2000"],
            "sample_mean_delta_e2000": {
                "mean": float(np.mean(per_sample_delta[model_name])),
                "median": float(np.median(per_sample_delta[model_name])),
                "p95": float(np.percentile(per_sample_delta[model_name], 95)),
            },
        }

    per_lut = []
    for source_lut, values in sorted(per_lut_delta.items()):
        row = {"source_lut": source_lut, "samples": len(values["direct_actual"])}
        for model_name, model_values in values.items():
            row[f"{model_name}_mean_delta_e2000"] = float(np.mean(model_values))
        row["actual_direct_minus_interpolation_delta_e2000"] = (
            row["direct_actual_mean_delta_e2000"] - row["interpolation_top3_mean_delta_e2000"]
        )
        row["axis_corrected_direct_minus_interpolation_delta_e2000"] = (
            row["direct_axis_corrected_mean_delta_e2000"] - row["interpolation_top3_mean_delta_e2000"]
        )
        per_lut.append(row)
    paired_lut_deltas = np.asarray([row["actual_direct_minus_interpolation_delta_e2000"] for row in per_lut])
    corrected_paired_lut_deltas = np.asarray([
        row["axis_corrected_direct_minus_interpolation_delta_e2000"] for row in per_lut
    ])

    swatches = []
    target_outputs = np.stack(swatch_output["target"]["values"], axis=0)
    model_outputs = {
        model_name: np.stack(swatch_output[model_name]["values"], axis=0)
        for model_name in MODEL_NAMES
    }
    for swatch_index, swatch_name in enumerate(swatch_names):
        row = {
            "name": swatch_name,
            "input_rgb_hex": SWATCHES[swatch_name],
            "target_mean_rgb_hex": rgb_hex(target_outputs[:, swatch_index].mean(axis=0)),
        }
        for model_name in MODEL_NAMES:
            deltas = np.asarray(swatch_delta[model_name][swatch_name])
            errors = np.asarray(swatch_rgb_error[model_name][swatch_name])
            row[model_name] = {
                "mean_rgb_hex": rgb_hex(model_outputs[model_name][:, swatch_index].mean(axis=0)),
                "delta_e2000_mean": float(deltas.mean()),
                "delta_e2000_median": float(np.median(deltas)),
                "delta_e2000_p95": float(np.percentile(deltas, 95)),
                "rgb_mae": float(np.abs(errors).mean()),
            }
        swatches.append(row)

    groups = {}
    for group, values in sorted(per_group_delta.items()):
        groups[group] = {
            model_name: {
                "samples": len(model_values),
                "sample_mean_delta_e2000": float(np.mean(model_values)),
                "sample_p95_delta_e2000": float(np.percentile(model_values, 95)),
            }
            for model_name, model_values in values.items()
        }

    result = {
        "schema_version": 1,
        "experiment_id": "DIRECT-MVP-COLOR-VALUE-AUDIT-001",
        "scope": "offline production-pipeline colorimetry; not a physical-device performance result",
        "population": {
            "split": "lut_family_holdout/test",
            "samples": len(test_records),
            "held_out_source_luts": len(per_lut),
            "groups": dict(Counter(row["samplingGroup"] for row in test_records)),
            "cube_nodes_per_sample": CUBE_DIM ** 3,
        },
        "artifacts": {
            "model": str(args.model),
            "model_sha256": sha256(args.model),
            "split": str(SPLIT),
            "split_sha256": sha256(SPLIT),
            "mask_archive": str(MASK_ARCHIVE),
            "mask_archive_sha256": sha256(MASK_ARCHIVE),
        },
        "method": {
            "input_preprocessing": "EXIF transpose, sRGB RGB decode, 256x256 bilinear resize, ImageNet normalization, NCHW float32",
            "production_postprocessing": "clamp 17^3 output, trilinear upsample to 65^3, float16 persistence, app safety gate, identity blend at 1.0/0.75/0.5/0.25 or identity fallback",
            "axis_contract": "In-memory LUTs use [R,G,B,channel]. Persisted LUTs are R-fastest and are converted by the shared Python loader before color application.",
            "target": "held-out 65^3 target LUT interpreted with the app's R-fastest contract, applied with trilinear interpolation, and clipped to sRGB",
            "baseline": "leakage-safe family-train interpolation top-3 using fixed HSV histogram/RGB moment retrieval, interpreted with the app's R-fastest contract",
            "color_space": "sRGB D65 converted to CIELAB; CIEDE2000",
            "bootstrap": "20,000 resamples of the 15 held-out source-LUT paired mean differences, seed 20260828",
            "swatch_note": "Synthetic sRGB probes are fixed diagnostics, not measured ColorChecker or human skin samples.",
        },
        "models": models,
        "historical_evaluator_reproduction": metric_summary(
            np.concatenate(historical_delta), np.concatenate(historical_rgb_error)
        ),
        "production_safety": {
            model_name: {
                "strength_counts": dict(sorted(strength_counts[model_name].items())),
                "identity_fallback_count": strength_counts[model_name].get("0.00", 0),
                "reduced_strength_count": sum(
                    count for strength, count in strength_counts[model_name].items()
                    if strength not in ("0.00", "1.00")
                ),
                "accepted_full_strength_count": strength_counts[model_name].get("1.00", 0),
                "accepted_report_ranges": {
                    key: {"min": float(np.min(values)), "mean": float(np.mean(values)), "max": float(np.max(values))}
                    for key, values in sorted(safety_values[model_name].items())
                },
            }
            for model_name in ("direct_actual", "direct_axis_corrected")
        },
        "paired_source_lut_comparison": {
            "source_luts": len(per_lut),
            "lut_macro_mean_delta_e2000": {
                model_name: float(np.mean([
                    row[f"{model_name}_mean_delta_e2000"] for row in per_lut
                ]))
                for model_name in MODEL_NAMES
            },
            "actual_direct": {
                "direct_wins": int(np.sum(paired_lut_deltas < 0)),
                "ties": int(np.sum(paired_lut_deltas == 0)),
                "interpolation_wins": int(np.sum(paired_lut_deltas > 0)),
                "mean_direct_minus_interpolation_delta_e2000": float(paired_lut_deltas.mean()),
                "median_direct_minus_interpolation_delta_e2000": float(np.median(paired_lut_deltas)),
                "bootstrap_95_ci": bootstrap_mean_ci(paired_lut_deltas),
            },
            "axis_corrected_direct": {
                "direct_wins": int(np.sum(corrected_paired_lut_deltas < 0)),
                "ties": int(np.sum(corrected_paired_lut_deltas == 0)),
                "interpolation_wins": int(np.sum(corrected_paired_lut_deltas > 0)),
                "mean_direct_minus_interpolation_delta_e2000": float(corrected_paired_lut_deltas.mean()),
                "median_direct_minus_interpolation_delta_e2000": float(np.median(corrected_paired_lut_deltas)),
                "bootstrap_95_ci": bootstrap_mean_ci(corrected_paired_lut_deltas),
            },
            "per_lut": per_lut,
        },
        "by_group": groups,
        "fixed_srgb_swatches": swatches,
        "limitations": [
            "The test corpus is synthetic training-pipeline data and does not establish real-camera generalization.",
            "CIEDE2000 measures target-transform reproduction, not aesthetic preference.",
            "The three skin probes are synthetic RGB coordinates and do not establish demographic skin-tone quality.",
            "The historical reproduction explicitly swaps the canonical target back to the legacy NumPy axis interpretation.",
            "Desktop TensorFlow Lite execution does not validate iOS or Android latency, memory, export, or permission behavior.",
        ],
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(f"color-value audit complete -> {args.output}")


if __name__ == "__main__":
    main()
