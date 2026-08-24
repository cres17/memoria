"""Common Color Cube evaluator for conditional 3D LUT generation."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

import numpy as np


PIPELINE_DIR = Path(__file__).resolve().parent
DEFAULT_MASK_ARCHIVE = PIPELINE_DIR / "reports" / "hue_masks" / "hue_coverage_17.npz"


def cube_colors(dim: int) -> np.ndarray:
    values = np.linspace(0.0, 1.0, dim, dtype=np.float32)
    red, green, blue = np.meshgrid(values, values, values, indexing="ij")
    return np.stack((red, green, blue), axis=-1).reshape(-1, 3)


def identity_lut(dim: int) -> np.ndarray:
    return cube_colors(dim).reshape(dim, dim, dim, 3)


def load_lut(path: Path) -> np.ndarray:
    values = np.fromfile(path, dtype=np.float16).astype(np.float32)
    points = values.size // 3
    dim = round(points ** (1.0 / 3.0))
    if dim ** 3 * 3 != values.size:
        raise ValueError(f"{path} is not a cubic float16 RGB LUT")
    return values.reshape(dim, dim, dim, 3)


def apply_lut(colors: np.ndarray, lut: np.ndarray) -> np.ndarray:
    """Trilinear LUT application without output clipping."""
    dim = lut.shape[0] - 1
    coordinates = np.clip(colors, 0.0, 1.0) * dim
    lower = np.floor(coordinates).astype(np.int64)
    lower = np.clip(lower, 0, dim - 1)
    upper = np.minimum(lower + 1, dim)
    fraction = coordinates - lower
    red0, green0, blue0 = lower[..., 0], lower[..., 1], lower[..., 2]
    red1, green1, blue1 = upper[..., 0], upper[..., 1], upper[..., 2]
    fr, fg, fb = fraction[..., 0:1], fraction[..., 1:2], fraction[..., 2:3]
    return (
        lut[red0, green0, blue0] * (1 - fr) * (1 - fg) * (1 - fb)
        + lut[red1, green0, blue0] * fr * (1 - fg) * (1 - fb)
        + lut[red0, green1, blue0] * (1 - fr) * fg * (1 - fb)
        + lut[red1, green1, blue0] * fr * fg * (1 - fb)
        + lut[red0, green0, blue1] * (1 - fr) * (1 - fg) * fb
        + lut[red1, green0, blue1] * fr * (1 - fg) * fb
        + lut[red0, green1, blue1] * (1 - fr) * fg * fb
        + lut[red1, green1, blue1] * fr * fg * fb
    )


def rgb_to_lab(rgb: np.ndarray) -> np.ndarray:
    clipped = np.clip(rgb, 0.0, 1.0)
    linear = np.where(clipped <= 0.04045, clipped / 12.92, ((clipped + 0.055) / 1.055) ** 2.4)
    matrix = np.array(
        [[0.4124564, 0.3575761, 0.1804375], [0.2126729, 0.7151522, 0.0721750], [0.0193339, 0.1191920, 0.9503041]],
        dtype=np.float32,
    )
    xyz = linear @ matrix.T / np.array([0.95047, 1.0, 1.08883], dtype=np.float32)
    transformed = np.where(xyz > 0.008856, np.cbrt(xyz), 7.787 * xyz + 16.0 / 116.0)
    return np.stack(
        (116.0 * transformed[..., 1] - 16.0, 500.0 * (transformed[..., 0] - transformed[..., 1]),
         200.0 * (transformed[..., 1] - transformed[..., 2])),
        axis=-1,
    )


def delta_e2000(lab_a: np.ndarray, lab_b: np.ndarray) -> np.ndarray:
    """Vectorized CIEDE2000 implementation for Lab arrays with final axis 3."""
    light_a, a_a, b_a = np.moveaxis(lab_a, -1, 0)
    light_b, a_b, b_b = np.moveaxis(lab_b, -1, 0)
    chroma_a = np.hypot(a_a, b_a)
    chroma_b = np.hypot(a_b, b_b)
    mean_chroma = (chroma_a + chroma_b) / 2.0
    adjustment = 0.5 * (1.0 - np.sqrt(mean_chroma ** 7 / (mean_chroma ** 7 + 25.0 ** 7)))
    a_prime_a = (1.0 + adjustment) * a_a
    a_prime_b = (1.0 + adjustment) * a_b
    chroma_prime_a = np.hypot(a_prime_a, b_a)
    chroma_prime_b = np.hypot(a_prime_b, b_b)
    hue_a = np.mod(np.degrees(np.arctan2(b_a, a_prime_a)), 360.0)
    hue_b = np.mod(np.degrees(np.arctan2(b_b, a_prime_b)), 360.0)
    delta_light = light_b - light_a
    delta_chroma = chroma_prime_b - chroma_prime_a
    hue_delta = hue_b - hue_a
    hue_delta = np.where(chroma_prime_a * chroma_prime_b == 0, 0.0, hue_delta)
    hue_delta = np.where(hue_delta > 180.0, hue_delta - 360.0, hue_delta)
    hue_delta = np.where(hue_delta < -180.0, hue_delta + 360.0, hue_delta)
    delta_hue = 2.0 * np.sqrt(chroma_prime_a * chroma_prime_b) * np.sin(np.radians(hue_delta / 2.0))
    mean_light = (light_a + light_b) / 2.0
    mean_chroma_prime = (chroma_prime_a + chroma_prime_b) / 2.0
    hue_sum = hue_a + hue_b
    hue_abs = np.abs(hue_a - hue_b)
    mean_hue = np.where(
        chroma_prime_a * chroma_prime_b == 0,
        hue_sum,
        np.where(hue_abs <= 180.0, hue_sum / 2.0, np.where(hue_sum < 360.0, (hue_sum + 360.0) / 2.0, (hue_sum - 360.0) / 2.0)),
    )
    weight_t = (
        1.0 - 0.17 * np.cos(np.radians(mean_hue - 30.0))
        + 0.24 * np.cos(np.radians(2.0 * mean_hue))
        + 0.32 * np.cos(np.radians(3.0 * mean_hue + 6.0))
        - 0.20 * np.cos(np.radians(4.0 * mean_hue - 63.0))
    )
    scale_light = 1.0 + 0.015 * (mean_light - 50.0) ** 2 / np.sqrt(20.0 + (mean_light - 50.0) ** 2)
    scale_chroma = 1.0 + 0.045 * mean_chroma_prime
    scale_hue = 1.0 + 0.015 * mean_chroma_prime * weight_t
    rotation = 30.0 * np.exp(-((mean_hue - 275.0) / 25.0) ** 2)
    interaction = -2.0 * np.sqrt(mean_chroma_prime ** 7 / (mean_chroma_prime ** 7 + 25.0 ** 7)) * np.sin(np.radians(2.0 * rotation))
    return np.sqrt(
        (delta_light / scale_light) ** 2
        + (delta_chroma / scale_chroma) ** 2
        + (delta_hue / scale_hue) ** 2
        + interaction * (delta_chroma / scale_chroma) * (delta_hue / scale_hue)
    )


def summarize(values: np.ndarray) -> dict:
    if values.size == 0:
        return {"count": 0, "mean": None, "max": None}
    return {"count": int(values.size), "mean": float(values.mean()), "max": float(values.max())}


def lut_stability(lut: np.ndarray) -> dict:
    differences = [np.diff(lut, axis=axis).reshape(-1, 3) for axis in range(3)]
    magnitudes = np.concatenate([np.linalg.norm(delta, axis=1) for delta in differences])
    luminance = lut[..., 0] * 0.2126 + lut[..., 1] * 0.7152 + lut[..., 2] * 0.0722
    monotonic_differences = [np.diff(luminance, axis=axis).reshape(-1) for axis in range(3)]
    monotonic_values = np.concatenate(monotonic_differences)
    out_of_gamut = (lut < 0.0) | (lut > 1.0)
    return {
        "smoothness_neighbor_l2": summarize(magnitudes),
        "monotonicity_luminance_violation_ratio": float(np.mean(monotonic_values < -1e-6)),
        "out_of_gamut_value_ratio": float(out_of_gamut.mean()),
        "out_of_gamut_node_ratio": float(np.mean(np.any(out_of_gamut, axis=-1))),
    }


def hsv_to_rgb(hue: np.ndarray, saturation: np.ndarray, value: np.ndarray) -> np.ndarray:
    sector = np.floor(hue * 6.0).astype(np.int64) % 6
    fraction = hue * 6.0 - np.floor(hue * 6.0)
    p = value * (1.0 - saturation)
    q = value * (1.0 - fraction * saturation)
    t = value * (1.0 - (1.0 - fraction) * saturation)
    choices = np.stack(
        (
            np.stack((value, t, p), axis=-1),
            np.stack((q, value, p), axis=-1),
            np.stack((p, value, t), axis=-1),
            np.stack((p, q, value), axis=-1),
            np.stack((t, p, value), axis=-1),
            np.stack((value, p, q), axis=-1),
        ),
        axis=0,
    )
    return choices[sector, np.arange(sector.size)]


def hue_continuity(lut: np.ndarray, hue_steps: int = 72) -> dict:
    saturation_values, value_values, hue_values = np.meshgrid(
        np.array([0.25, 0.5, 0.75, 1.0], dtype=np.float32),
        np.array([0.25, 0.5, 0.75, 1.0], dtype=np.float32),
        np.arange(hue_steps, dtype=np.float32) / hue_steps,
        indexing="ij",
    )
    output = apply_lut(
        hsv_to_rgb(hue_values.reshape(-1), saturation_values.reshape(-1), value_values.reshape(-1)),
        lut,
    )
    lab = rgb_to_lab(output).reshape(4, 4, hue_steps, 3)
    jumps = np.linalg.norm(lab - np.roll(lab, -1, axis=2), axis=-1).reshape(-1)
    return summarize(jumps)


def load_mask(path: Path, sample_id: str, cube_dim: int) -> np.ndarray:
    with np.load(path) as archive:
        ids = archive["ids"].astype(str)
        masks = archive["observed_cube_mask"]
        archive_dim = int(archive["cube_dim"])
    if archive_dim != cube_dim:
        raise ValueError(f"mask cube dimension {archive_dim} does not match evaluator cube dimension {cube_dim}")
    matches = np.where(ids == sample_id)[0]
    if matches.size != 1:
        raise ValueError(f"sample id {sample_id} is not uniquely present in {path}")
    return masks[matches[0]].astype(bool)


def evaluate_lut_pair(prediction: np.ndarray, target: np.ndarray, cube_dim: int, observed_mask: np.ndarray | None) -> dict:
    colors = cube_colors(cube_dim)
    prediction_cube_raw = apply_lut(colors, prediction)
    target_cube_raw = apply_lut(colors, target)
    # Dataset generation and application clamp rendered RGB. Keep raw LUT nodes
    # for the OOG metric, but compare the transform users actually receive.
    prediction_cube = np.clip(prediction_cube_raw, 0.0, 1.0)
    target_cube = np.clip(target_cube_raw, 0.0, 1.0)
    rgb_error = prediction_cube - target_cube
    delta_e = delta_e2000(rgb_to_lab(prediction_cube), rgb_to_lab(target_cube))
    metrics = {
        "cube_dim": cube_dim,
        "comparison_output_clipped_to_srgb": True,
        "overall": {
            "rgb_mae": float(np.abs(rgb_error).mean()),
            "rgb_mse": float(np.square(rgb_error).mean()),
            "rgb_rmse": float(np.sqrt(np.square(rgb_error).mean())),
            "delta_e2000": summarize(delta_e),
        },
        "prediction_lut_quality": lut_stability(prediction),
        "target_lut_quality": lut_stability(target),
        "prediction_hue_continuity_delta_e76": hue_continuity(prediction),
        "target_hue_continuity_delta_e76": hue_continuity(target),
    }
    if observed_mask is not None:
        if observed_mask.shape != (colors.shape[0],):
            raise ValueError(f"observed mask has shape {observed_mask.shape}; expected {(colors.shape[0],)}")
        metrics["observed_cube"] = {
            "coverage_fraction": float(observed_mask.mean()),
            "rgb_mae": float(np.abs(rgb_error[observed_mask]).mean()) if observed_mask.any() else None,
            "rgb_rmse": float(np.sqrt(np.square(rgb_error[observed_mask]).mean())) if observed_mask.any() else None,
            "delta_e2000": summarize(delta_e[observed_mask]),
        }
        unobserved = ~observed_mask
        metrics["unobserved_cube"] = {
            "coverage_fraction": float(unobserved.mean()),
            "rgb_mae": float(np.abs(rgb_error[unobserved]).mean()) if unobserved.any() else None,
            "rgb_rmse": float(np.sqrt(np.square(rgb_error[unobserved]).mean())) if unobserved.any() else None,
            "delta_e2000": summarize(delta_e[unobserved]),
        }
    return metrics


def main() -> None:
    parser = argparse.ArgumentParser(description="Evaluate a predicted LUT against a target LUT on a Color Cube.")
    parser.add_argument("--target-lut", type=Path, required=True)
    parser.add_argument("--prediction-lut", type=Path)
    parser.add_argument("--identity-prediction", action="store_true")
    parser.add_argument("--cube-dim", type=int, default=17)
    parser.add_argument("--sample-id")
    parser.add_argument("--mask-archive", type=Path, default=DEFAULT_MASK_ARCHIVE)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if args.cube_dim <= 1:
        parser.error("--cube-dim must be greater than 1")
    if bool(args.prediction_lut) == bool(args.identity_prediction):
        parser.error("provide exactly one of --prediction-lut or --identity-prediction")
    if args.sample_id is None and args.mask_archive.exists():
        parser.error("--sample-id is required when using a mask archive")

    target = load_lut(args.target_lut)
    prediction = identity_lut(args.cube_dim) if args.identity_prediction else load_lut(args.prediction_lut)
    mask = load_mask(args.mask_archive, args.sample_id, args.cube_dim) if args.sample_id else None
    report = evaluate_lut_pair(prediction, target, args.cube_dim, mask)
    report["inputs"] = {
        "target_lut": str(args.target_lut),
        "prediction_lut": "identity" if args.identity_prediction else str(args.prediction_lut),
        "sample_id": args.sample_id,
        "mask_archive": str(args.mask_archive) if args.sample_id else None,
    }
    payload = json.dumps(report, indent=2, sort_keys=True) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(payload)
    print(payload, end="")


if __name__ == "__main__":
    main()
