"""Fit a personalized filter directly from before/after photo pairs.

This script does not look for a matching source LUT. It learns the edit from
paired examples by fitting:
  1. a global affine color transform, then
  2. a coarse residual LUT in 3D RGB space.

The final artifact is a safe 65^3 float16 LUT plus a portable recipe JSON.

Usage examples:
  python 13_fit_personal_filter.py --pair before.jpg after.jpg
  python 13_fit_personal_filter.py --manifest pairs.jsonl --output-dir exports/personal
  python 13_fit_personal_filter.py --demo --output-dir /tmp/personal-filter-demo
"""

from __future__ import annotations

import argparse
import json
import math
import tempfile
import uuid
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image, ImageOps


PIPELINE_DIR = Path(__file__).resolve().parent
DEFAULT_OUTPUT_ROOT = PIPELINE_DIR / "exports" / "personalized_filters"
DEFAULT_LUT_DIM = 65
DEFAULT_RESIDUAL_DIM = 17
DEFAULT_SAMPLE_LIMIT_PER_PAIR = 50_000
DEFAULT_RIDGE = 0.01
DEFAULT_SMOOTH_PASSES = 2
DEFAULT_RESIDUAL_CLIP = 0.35
DEFAULT_SEED = 20260721


@dataclass(frozen=True)
class PairExample:
    before_path: Path
    after_path: Path
    weight: float = 1.0


@dataclass(frozen=True)
class SafetyReport:
    valid_encoding: bool
    has_non_finite_values: bool
    interior_clip_ratio: float
    max_adjacent_delta: float
    neutral_luminance_range: float
    neutral_inversions: int
    primary_min_chroma: float

    @property
    def is_safe(self) -> bool:
        return (
            self.valid_encoding
            and not self.has_non_finite_values
            and self.interior_clip_ratio <= 0.08
            and self.max_adjacent_delta <= 0.35
            and self.neutral_inversions == 0
            and self.neutral_luminance_range >= 0.55
            and self.primary_min_chroma >= 0.05
        )

    def to_json(self) -> dict[str, object]:
        return {
            "validEncoding": self.valid_encoding,
            "hasNonFiniteValues": self.has_non_finite_values,
            "interiorClipRatio": self.interior_clip_ratio,
            "maxAdjacentDelta": self.max_adjacent_delta,
            "neutralLuminanceRange": self.neutral_luminance_range,
            "neutralInversions": self.neutral_inversions,
            "primaryMinChroma": self.primary_min_chroma,
            "isSafe": self.is_safe,
        }


def load_image(path: Path) -> np.ndarray:
    with Image.open(path) as image:
        image = ImageOps.exif_transpose(image).convert("RGB")
    return np.asarray(image, dtype=np.float32) / 255.0


def maybe_resize_after(before: np.ndarray, after: np.ndarray, align_mode: str) -> np.ndarray:
    if before.shape == after.shape:
        return after
    if align_mode == "strict":
        raise ValueError(
            f"image sizes do not match: before={before.shape[:2]}, after={after.shape[:2]}"
        )
    image = Image.fromarray(np.clip(after * 255.0, 0, 255).astype(np.uint8))
    resized = image.resize((before.shape[1], before.shape[0]), Image.Resampling.LANCZOS)
    return np.asarray(resized, dtype=np.float32) / 255.0


def read_manifest(manifest_path: Path) -> list[PairExample]:
    pairs: list[PairExample] = []
    for line_number, line in enumerate(manifest_path.read_text().splitlines(), start=1):
        if not line.strip():
            continue
        try:
            row = json.loads(line)
            before = row["before"]
            after = row["after"]
            weight = float(row.get("weight", 1.0))
        except (KeyError, TypeError, ValueError, json.JSONDecodeError) as error:
            raise ValueError(
                f"{manifest_path}:{line_number} is not a valid pair manifest: {error}"
            ) from error

        before_path = Path(before)
        after_path = Path(after)
        if not before_path.is_absolute():
            before_path = (manifest_path.parent / before_path).resolve()
        if not after_path.is_absolute():
            after_path = (manifest_path.parent / after_path).resolve()
        pairs.append(PairExample(before_path=before_path, after_path=after_path, weight=weight))

    if not pairs:
        raise ValueError(f"{manifest_path} does not contain any pairs")
    return pairs


def build_demo_pair(output_dir: Path) -> list[PairExample]:
    output_dir.mkdir(parents=True, exist_ok=True)
    before_path = output_dir / "demo_before.png"
    after_path = output_dir / "demo_after.png"

    width = height = 192
    x = np.linspace(0.0, 1.0, width, dtype=np.float32)
    y = np.linspace(0.0, 1.0, height, dtype=np.float32)
    xx, yy = np.meshgrid(x, y)

    before = np.stack(
        [
            0.12 + 0.72 * xx + 0.05 * np.sin(yy * math.pi * 2.0),
            0.18 + 0.62 * yy + 0.05 * np.cos(xx * math.pi * 2.0),
            0.10 + 0.52 * (1.0 - xx * 0.7) + 0.08 * np.sin((xx + yy) * math.pi),
        ],
        axis=-1,
    )
    before = np.clip(before, 0.0, 1.0)

    affine = np.array(
        [
            [1.08, -0.05, -0.02],
            [0.03, 1.02, -0.03],
            [0.01, 0.05, 0.92],
        ],
        dtype=np.float32,
    )
    bias = np.array([0.025, 0.010, -0.012], dtype=np.float32)
    after = before @ affine.T + bias
    after[..., 0] += 0.035 * before[..., 1] * (1.0 - before[..., 0])
    after[..., 1] += 0.020 * (1.0 - before[..., 2]) * before[..., 1]
    after[..., 2] -= 0.018 * before[..., 0] * (1.0 - before[..., 2])
    after = np.clip(after, 0.0, 1.0) ** np.array([0.98, 0.99, 1.02], dtype=np.float32)

    Image.fromarray(np.clip(before * 255.0, 0, 255).astype(np.uint8)).save(before_path)
    Image.fromarray(np.clip(after * 255.0, 0, 255).astype(np.uint8)).save(after_path)

    return [PairExample(before_path=before_path, after_path=after_path, weight=1.0)]


def collect_samples(
    pairs: list[PairExample],
    *,
    align_mode: str,
    seed: int,
    sample_limit_per_pair: int,
) -> tuple[np.ndarray, np.ndarray, np.ndarray, list[dict[str, object]]]:
    rng = np.random.default_rng(seed)
    x_samples = []
    y_samples = []
    weights = []
    pair_stats: list[dict[str, object]] = []

    for pair in pairs:
        before = load_image(pair.before_path)
        after = load_image(pair.after_path)
        after = maybe_resize_after(before, after, align_mode)

        before_flat = before.reshape(-1, 3)
        after_flat = after.reshape(-1, 3)
        total = before_flat.shape[0]
        take = min(total, sample_limit_per_pair)
        if take < total:
            indices = rng.choice(total, size=take, replace=False)
            before_flat = before_flat[indices]
            after_flat = after_flat[indices]

        chroma = before_flat.max(axis=1) - before_flat.min(axis=1)
        sample_weights = pair.weight * (0.65 + 0.35 * chroma)

        x_samples.append(before_flat.astype(np.float32))
        y_samples.append(after_flat.astype(np.float32))
        weights.append(sample_weights.astype(np.float32))
        pair_stats.append(
            {
                "beforeSize": [int(before.shape[1]), int(before.shape[0])],
                "afterSize": [int(after.shape[1]), int(after.shape[0])],
                "sampleCount": int(take),
                "weight": float(pair.weight),
            }
        )

    return (
        np.concatenate(x_samples, axis=0),
        np.concatenate(y_samples, axis=0),
        np.concatenate(weights, axis=0),
        pair_stats,
    )


def fit_affine(x: np.ndarray, y: np.ndarray, weights: np.ndarray, ridge: float) -> tuple[np.ndarray, np.ndarray, float]:
    design = np.concatenate([x, np.ones((x.shape[0], 1), dtype=np.float32)], axis=1)
    sqrt_w = np.sqrt(weights).astype(np.float32)[:, None]
    weighted_design = design * sqrt_w
    weighted_target = y * sqrt_w

    gram = weighted_design.T @ weighted_design
    reg = np.diag(np.array([ridge, ridge, ridge, ridge * 0.1], dtype=np.float32))
    rhs = weighted_design.T @ weighted_target
    theta = np.linalg.solve(gram + reg, rhs)
    matrix = theta[:3].T.astype(np.float32)
    bias = theta[3].astype(np.float32)

    predictions = x @ matrix.T + bias
    residual = predictions - y
    weighted_rmse = math.sqrt(float(np.average(np.sum(residual**2, axis=1), weights=weights)))
    return matrix, bias, weighted_rmse


def trilinear_sample(grid: np.ndarray, coords: np.ndarray) -> np.ndarray:
    dim = grid.shape[0]
    scaled = np.clip(coords, 0.0, 1.0) * (dim - 1)
    base = np.floor(scaled).astype(np.int64)
    frac = scaled - base
    upper = np.minimum(base + 1, dim - 1)

    b0, g0, r0 = base.T
    b1, g1, r1 = upper.T
    fb, fg, fr = frac.T

    c000 = grid[b0, g0, r0]
    c100 = grid[b1, g0, r0]
    c010 = grid[b0, g1, r0]
    c110 = grid[b1, g1, r0]
    c001 = grid[b0, g0, r1]
    c101 = grid[b1, g0, r1]
    c011 = grid[b0, g1, r1]
    c111 = grid[b1, g1, r1]

    return (
        c000 * (1 - fb)[:, None] * (1 - fg)[:, None] * (1 - fr)[:, None]
        + c100 * fb[:, None] * (1 - fg)[:, None] * (1 - fr)[:, None]
        + c010 * (1 - fb)[:, None] * fg[:, None] * (1 - fr)[:, None]
        + c110 * fb[:, None] * fg[:, None] * (1 - fr)[:, None]
        + c001 * (1 - fb)[:, None] * (1 - fg)[:, None] * fr[:, None]
        + c101 * fb[:, None] * (1 - fg)[:, None] * fr[:, None]
        + c011 * (1 - fb)[:, None] * fg[:, None] * fr[:, None]
        + c111 * fb[:, None] * fg[:, None] * fr[:, None]
    )


def blur_axis(arr: np.ndarray, axis: int) -> np.ndarray:
    pad_width = [(0, 0)] * arr.ndim
    pad_width[axis] = (1, 1)
    padded = np.pad(arr, pad_width, mode="edge")
    left = [slice(None)] * arr.ndim
    center = [slice(None)] * arr.ndim
    right = [slice(None)] * arr.ndim
    left[axis] = slice(0, -2)
    center[axis] = slice(1, -1)
    right[axis] = slice(2, None)
    return (padded[tuple(left)] + 2.0 * padded[tuple(center)] + padded[tuple(right)]) / 4.0


def smooth_residual_grid(sum_grid: np.ndarray, weight_grid: np.ndarray, passes: int) -> tuple[np.ndarray, np.ndarray]:
    smoothed_sum = sum_grid
    smoothed_weight = weight_grid
    for _ in range(passes):
        for axis in range(3):
            smoothed_sum = blur_axis(smoothed_sum, axis)
            smoothed_weight = blur_axis(smoothed_weight, axis)
    return smoothed_sum, smoothed_weight


def fit_residual_grid(
    x: np.ndarray,
    residual: np.ndarray,
    weights: np.ndarray,
    *,
    residual_dim: int,
    smooth_passes: int,
    residual_clip: float,
) -> tuple[np.ndarray, np.ndarray]:
    sum_grid = np.zeros((residual_dim, residual_dim, residual_dim, 3), dtype=np.float64)
    weight_grid = np.zeros((residual_dim, residual_dim, residual_dim), dtype=np.float64)

    coords = np.clip(x[:, [2, 1, 0]], 0.0, 1.0) * (residual_dim - 1)
    base = np.floor(coords).astype(np.int64)
    frac = coords - base
    upper = np.minimum(base + 1, residual_dim - 1)

    for db in (0, 1):
        ib = upper[:, 0] if db else base[:, 0]
        wb = frac[:, 0] if db else 1.0 - frac[:, 0]
        for dg in (0, 1):
            ig = upper[:, 1] if dg else base[:, 1]
            wg = frac[:, 1] if dg else 1.0 - frac[:, 1]
            for dr in (0, 1):
                ir = upper[:, 2] if dr else base[:, 2]
                wr = frac[:, 2] if dr else 1.0 - frac[:, 2]
                w = weights * wb * wg * wr
                np.add.at(weight_grid, (ib, ig, ir), w)
                for channel in range(3):
                    np.add.at(sum_grid[..., channel], (ib, ig, ir), residual[:, channel] * w)

    smoothed_sum, smoothed_weight = smooth_residual_grid(sum_grid, weight_grid, smooth_passes)
    residual_grid = smoothed_sum / np.maximum(smoothed_weight[..., None], 1e-8)
    residual_grid = np.clip(residual_grid, -residual_clip, residual_clip).astype(np.float32)
    return residual_grid, smoothed_weight.astype(np.float32)


def upsample_residual_grid(residual_grid: np.ndarray, target_dim: int) -> np.ndarray:
    src_dim = residual_grid.shape[0]
    coords = np.linspace(0.0, 1.0, target_dim, dtype=np.float32)
    bb, gg, rr = np.meshgrid(coords, coords, coords, indexing="ij")
    scaled = np.stack([bb, gg, rr], axis=-1).reshape(-1, 3)
    sampled = trilinear_sample(residual_grid, scaled)
    return sampled.reshape(target_dim, target_dim, target_dim, 3).astype(np.float32)


def build_identity_lut(dim: int) -> np.ndarray:
    axis = np.linspace(0.0, 1.0, dim, dtype=np.float32)
    bb, gg, rr = np.meshgrid(axis, axis, axis, indexing="ij")
    return np.stack([rr, gg, bb], axis=-1)


def build_lut(matrix: np.ndarray, bias: np.ndarray, residual_grid: np.ndarray, lut_dim: int) -> np.ndarray:
    identity = build_identity_lut(lut_dim)
    affine = np.clip(identity @ matrix.T + bias, 0.0, 1.0)
    residual = upsample_residual_grid(residual_grid, lut_dim)
    return np.clip(affine + residual, 0.0, 1.0).astype(np.float32)


def inspect_lut_safety(lut: np.ndarray) -> SafetyReport:
    valid_encoding = lut.ndim == 4 and lut.shape[-1] == 3 and lut.shape[0] == lut.shape[1] == lut.shape[2]
    if not valid_encoding:
        return SafetyReport(
            valid_encoding=False,
            has_non_finite_values=True,
            interior_clip_ratio=1.0,
            max_adjacent_delta=float("inf"),
            neutral_luminance_range=0.0,
            neutral_inversions=1,
            primary_min_chroma=0.0,
        )

    has_non_finite_values = not np.isfinite(lut).all()
    if has_non_finite_values:
        return SafetyReport(
            valid_encoding=True,
            has_non_finite_values=True,
            interior_clip_ratio=1.0,
            max_adjacent_delta=float("inf"),
            neutral_luminance_range=0.0,
            neutral_inversions=1,
            primary_min_chroma=0.0,
        )

    interior = lut[1:-1, 1:-1, 1:-1]
    if interior.size == 0:
        interior_clip_ratio = 1.0
    else:
        interior_clip_ratio = float(
            np.mean((interior <= 0.0001) | (interior >= 0.9999))
        )

    max_adjacent_delta = 0.0
    for axis in range(3):
        delta = np.linalg.norm(np.diff(lut, axis=axis), axis=-1)
        if delta.size:
            max_adjacent_delta = max(max_adjacent_delta, float(delta.max()))

    diag_idx = np.arange(lut.shape[0])
    neutral = lut[diag_idx, diag_idx, diag_idx]
    luminance = 0.2126 * neutral[:, 0] + 0.7152 * neutral[:, 1] + 0.0722 * neutral[:, 2]
    neutral_inversions = int(np.sum(luminance[1:] + 0.001 < luminance[:-1]))
    neutral_luminance_range = float(luminance[-1] - luminance[0])

    def chroma_at(b: int, g: int, r: int) -> float:
        pixel = lut[b, g, r]
        return float(np.max(pixel) - np.min(pixel))

    primary_min_chroma = min(
        chroma_at(lut.shape[0] - 1, 0, 0),
        chroma_at(0, lut.shape[0] - 1, 0),
        chroma_at(0, 0, lut.shape[0] - 1),
    )

    return SafetyReport(
        valid_encoding=True,
        has_non_finite_values=False,
        interior_clip_ratio=interior_clip_ratio,
        max_adjacent_delta=max_adjacent_delta,
        neutral_luminance_range=neutral_luminance_range,
        neutral_inversions=neutral_inversions,
        primary_min_chroma=primary_min_chroma,
    )


def blend_lut_with_identity(lut: np.ndarray, strength: float) -> np.ndarray:
    identity = build_identity_lut(lut.shape[0])
    return np.clip(identity + (lut - identity) * strength, 0.0, 1.0).astype(np.float32)


def constrain_lut(
    lut: np.ndarray,
    *,
    strength_steps: tuple[float, ...] = (1.0, 0.75, 0.5, 0.25),
) -> tuple[np.ndarray, float, SafetyReport, str | None]:
    original_report = inspect_lut_safety(lut)
    if not original_report.valid_encoding or original_report.has_non_finite_values:
        identity = build_identity_lut(lut.shape[0]).astype(np.float32)
        return identity, 0.0, inspect_lut_safety(identity), "lut_safety_identity_fallback"

    for strength in strength_steps:
        candidate = lut if strength == 1.0 else blend_lut_with_identity(lut, strength)
        report = inspect_lut_safety(candidate)
        if report.is_safe:
            return candidate, strength, report, (
                None if strength == 1.0 else "lut_safety_strength_reduced"
            )

    identity = build_identity_lut(lut.shape[0]).astype(np.float32)
    return identity, 0.0, inspect_lut_safety(identity), "lut_safety_identity_fallback"


def sample_lut(lut: np.ndarray, x: np.ndarray) -> np.ndarray:
    # LUT tensors are stored in (b, g, r) axis order, while callers pass RGB.
    return trilinear_sample(lut, np.clip(x[:, [2, 1, 0]], 0.0, 1.0))


def evaluate_fit(
    x: np.ndarray,
    y: np.ndarray,
    matrix: np.ndarray,
    bias: np.ndarray,
    lut: np.ndarray,
) -> dict[str, float]:
    affine_pred = np.clip(x @ matrix.T + bias, 0.0, 1.0)
    lut_pred = sample_lut(lut, x)

    affine_diff = affine_pred - y
    lut_diff = lut_pred - y

    affine_mse = float(np.mean(np.sum(affine_diff**2, axis=1)))
    lut_mse = float(np.mean(np.sum(lut_diff**2, axis=1)))
    affine_mae = float(np.mean(np.abs(affine_diff)))
    lut_mae = float(np.mean(np.abs(lut_diff)))
    improvement = math.sqrt(max(affine_mse, 0.0)) - math.sqrt(max(lut_mse, 0.0))

    return {
        "sampleCount": int(x.shape[0]),
        "affineRMSE": float(math.sqrt(max(affine_mse, 0.0))),
        "affineMAE": affine_mae,
        "lutRMSE": float(math.sqrt(max(lut_mse, 0.0))),
        "lutMAE": lut_mae,
        "rmseImprovement": float(improvement),
    }


def fit_personal_filter(
    pairs: list[PairExample],
    *,
    output_dir: Path,
    lut_dim: int,
    residual_dim: int,
    sample_limit_per_pair: int,
    ridge: float,
    smooth_passes: int,
    residual_clip: float,
    align_mode: str,
    seed: int,
) -> dict[str, object]:
    x, y, weights, pair_stats = collect_samples(
        pairs,
        align_mode=align_mode,
        seed=seed,
        sample_limit_per_pair=sample_limit_per_pair,
    )

    matrix, bias, affine_rmse = fit_affine(x, y, weights, ridge)
    affine_pred = np.clip(x @ matrix.T + bias, 0.0, 1.0)
    residual = y - affine_pred
    residual_grid, occupancy = fit_residual_grid(
        x,
        residual,
        weights,
        residual_dim=residual_dim,
        smooth_passes=smooth_passes,
        residual_clip=residual_clip,
    )
    lut = build_lut(matrix, bias, residual_grid, lut_dim)
    lut, applied_strength, safety_report, fallback_reason = constrain_lut(lut)
    fit_metrics = evaluate_fit(x, y, matrix, bias, lut)

    output_dir.mkdir(parents=True, exist_ok=True)
    lut_path = output_dir / "lut.bin"
    thumbnail_path = output_dir / "thumbnail.jpg"
    recipe_path = output_dir / "recipe.json"
    report_path = output_dir / "fit_report.json"

    lut.astype(np.float16).tofile(lut_path)

    with Image.open(pairs[0].after_path) as image:
        image = ImageOps.exif_transpose(image).convert("RGB")
        thumb = image.copy()
        thumb.thumbnail((256, 256), Image.Resampling.LANCZOS)
        if thumb.width != thumb.height:
            side = min(thumb.width, thumb.height)
            left = (thumb.width - side) // 2
            top = (thumb.height - side) // 2
            thumb = thumb.crop((left, top, left + side, top + side))
        thumb.save(thumbnail_path, quality=88)

    coverage = float(np.mean(occupancy > 0.0))
    mean_samples_per_cell = float(np.mean(occupancy))
    max_samples_per_cell = float(np.max(occupancy))
    design = np.concatenate([x, np.ones((x.shape[0], 1), dtype=np.float32)], axis=1)
    aff_cond = float(np.linalg.cond(design.T @ design))

    recipe = {
        "version": 1,
        "colorSpace": "sRGB",
        "lutDimension": lut_dim,
        "lutAxisOrder": "r_fastest_rgb",
        "renderOrder": "lut_then_adjust_then_intensity",
        "engineVersion": "personal_filter_fit_v1",
        "generatorType": "personalized_pair_fit",
        "lutStrength": applied_strength,
        "referenceCount": len(pairs),
        "safetyMetrics": safety_report.to_json(),
        "fallbackReason": fallback_reason,
        "modelId": "affine_plus_residual_lut",
        "modelVersion": "v1",
    }

    report = {
        "pairCount": len(pairs),
        "pairs": pair_stats,
        "sampleCount": int(x.shape[0]),
        "affineMatrix": matrix.tolist(),
        "affineBias": bias.tolist(),
        "affineConditionNumber": aff_cond,
        "coverage": coverage,
        "meanSamplesPerCell": mean_samples_per_cell,
        "maxSamplesPerCell": max_samples_per_cell,
        "residualDim": residual_dim,
        "lutDim": lut_dim,
        "ridge": ridge,
        "smoothPasses": smooth_passes,
        "residualClip": residual_clip,
        "fitMetrics": fit_metrics,
        "safetyMetrics": safety_report.to_json(),
        "appliedStrength": applied_strength,
        "fallbackReason": fallback_reason,
    }

    recipe_path.write_text(json.dumps(recipe, indent=2) + "\n")
    report_path.write_text(json.dumps(report, indent=2) + "\n")

    return {
        "presetId": output_dir.name,
        "lutPath": str(lut_path),
        "thumbnailPath": str(thumbnail_path),
        "generatorType": "personalized_pair_fit",
        "lutStrength": applied_strength,
        "safetyMetrics": safety_report.to_json(),
        "fallbackReason": fallback_reason,
        "fitReport": report,
        "filterRecipe": recipe,
    }


def parse_pairs(args: argparse.Namespace) -> list[PairExample]:
    if args.demo:
        return build_demo_pair(Path(tempfile.mkdtemp(prefix="memoria-personal-filter-demo-")))

    pairs: list[PairExample] = []
    if args.manifest:
        pairs.extend(read_manifest(Path(args.manifest)))
    if args.pair:
        for before, after in args.pair:
            pairs.append(PairExample(Path(before).resolve(), Path(after).resolve(), 1.0))
    if not pairs:
        raise ValueError("provide at least one --pair or --manifest, or use --demo")
    return pairs


def run_demo(args: argparse.Namespace) -> None:
    demo_root = Path(tempfile.mkdtemp(prefix="memoria-personal-filter-demo-"))
    pairs = build_demo_pair(demo_root)
    output_dir = Path(args.output_dir) if args.output_dir else demo_root / "output"
    result = fit_personal_filter(
        pairs,
        output_dir=output_dir,
        lut_dim=args.lut_dim,
        residual_dim=args.residual_dim,
        sample_limit_per_pair=args.sample_limit_per_pair,
        ridge=args.ridge,
        smooth_passes=args.smooth_passes,
        residual_clip=args.residual_clip,
        align_mode=args.align_mode,
        seed=args.seed,
    )
    print(json.dumps(
        {
            "mode": "demo",
            "outputDir": str(output_dir),
            "presetId": result["presetId"],
            "lutStrength": result["lutStrength"],
            "affineRMSE": result["fitReport"]["fitMetrics"]["affineRMSE"],
            "lutRMSE": result["fitReport"]["fitMetrics"]["lutRMSE"],
            "safetyIsSafe": result["fitReport"]["safetyMetrics"]["isSafe"],
        },
        indent=2,
    ))
    print(f"wrote demo artifacts to {output_dir}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Fit a personalized filter from before/after pairs.")
    parser.add_argument("--manifest", help="JSONL manifest with before, after, and optional weight fields.")
    parser.add_argument(
        "--pair",
        action="append",
        nargs=2,
        metavar=("BEFORE", "AFTER"),
        help="Aligned before/after image pair. Repeatable.",
    )
    parser.add_argument(
        "--output-dir",
        help="Directory for lut.bin, recipe.json, fit_report.json, and thumbnail.jpg.",
    )
    parser.add_argument("--lut-dim", type=int, default=DEFAULT_LUT_DIM)
    parser.add_argument("--residual-dim", type=int, default=DEFAULT_RESIDUAL_DIM)
    parser.add_argument("--sample-limit-per-pair", type=int, default=DEFAULT_SAMPLE_LIMIT_PER_PAIR)
    parser.add_argument("--ridge", type=float, default=DEFAULT_RIDGE)
    parser.add_argument("--smooth-passes", type=int, default=DEFAULT_SMOOTH_PASSES)
    parser.add_argument("--residual-clip", type=float, default=DEFAULT_RESIDUAL_CLIP)
    parser.add_argument(
        "--align-mode",
        choices=("strict", "resize_after"),
        default="resize_after",
        help="How to handle before/after size mismatches.",
    )
    parser.add_argument("--seed", type=int, default=DEFAULT_SEED)
    parser.add_argument("--demo", action="store_true", help="Build a synthetic demo pair and fit it.")
    args = parser.parse_args()

    if args.demo:
        run_demo(args)
        return

    pairs = parse_pairs(args)
    output_dir = Path(args.output_dir) if args.output_dir else DEFAULT_OUTPUT_ROOT / uuid.uuid4().hex[:12]
    result = fit_personal_filter(
        pairs,
        output_dir=output_dir,
        lut_dim=args.lut_dim,
        residual_dim=args.residual_dim,
        sample_limit_per_pair=args.sample_limit_per_pair,
        ridge=args.ridge,
        smooth_passes=args.smooth_passes,
        residual_clip=args.residual_clip,
        align_mode=args.align_mode,
        seed=args.seed,
    )
    print(json.dumps(
        {
            "outputDir": str(output_dir),
            "presetId": result["presetId"],
            "lutPath": result["lutPath"],
            "thumbnailPath": result["thumbnailPath"],
            "generatorType": result["generatorType"],
            "lutStrength": result["lutStrength"],
            "safetyIsSafe": result["safetyMetrics"]["isSafe"],
            "fallbackReason": result["fallbackReason"],
            "affineRMSE": result["fitReport"]["fitMetrics"]["affineRMSE"],
            "lutRMSE": result["fitReport"]["fitMetrics"]["lutRMSE"],
        },
        indent=2,
    ))


if __name__ == "__main__":
    main()
