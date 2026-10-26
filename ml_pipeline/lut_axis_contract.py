"""Canonical 3D LUT tensor and persistence helpers for the ML pipeline.

In memory, LUT tensors always use ``[R, G, B, channel]`` axes. Persisted
``.bin`` and Adobe ``.cube`` values use the app's R-fastest coordinate order,
where the flattened RGB triple index is ``r + g*D + b*D*D``.
"""

from __future__ import annotations

from pathlib import Path

import numpy as np


AXIS_ORDER = "r_fastest_rgb"


def validate_lut(lut: np.ndarray, expected_dim: int | None = None) -> np.ndarray:
    array = np.asarray(lut)
    if array.ndim != 4 or array.shape[-1] != 3:
        raise ValueError(f"expected [R,G,B,3] LUT, got shape {array.shape}")
    if not (array.shape[0] == array.shape[1] == array.shape[2]):
        raise ValueError(f"expected cubic LUT, got shape {array.shape}")
    if expected_dim is not None and array.shape[0] != expected_dim:
        raise ValueError(f"expected {expected_dim}^3 LUT, got shape {array.shape}")
    return array


def infer_dimension(value_count: int) -> int:
    if value_count <= 0 or value_count % 3:
        raise ValueError(f"RGB LUT value count must be positive and divisible by 3: {value_count}")
    points = value_count // 3
    dim = round(points ** (1.0 / 3.0))
    if dim ** 3 != points:
        raise ValueError(f"RGB LUT does not contain a cubic number of nodes: {points}")
    return dim


def from_r_fastest_values(
    values: np.ndarray,
    *,
    dim: int | None = None,
    dtype: np.dtype | type = np.float32,
) -> np.ndarray:
    """Convert persisted R-fastest RGB triples to canonical [R,G,B,3]."""
    flat = np.asarray(values).reshape(-1)
    resolved_dim = infer_dimension(flat.size) if dim is None else dim
    if flat.size != resolved_dim ** 3 * 3:
        raise ValueError(
            f"expected {resolved_dim ** 3 * 3} values for {resolved_dim}^3 LUT, got {flat.size}"
        )
    stored_axes = flat.reshape(resolved_dim, resolved_dim, resolved_dim, 3)
    return np.transpose(stored_axes, (2, 1, 0, 3)).astype(dtype, copy=False)


def to_r_fastest_values(
    lut: np.ndarray,
    *,
    dtype: np.dtype | type | None = None,
) -> np.ndarray:
    """Convert canonical [R,G,B,3] axes to persisted R-fastest RGB triples."""
    canonical = validate_lut(lut)
    values = np.transpose(canonical, (2, 1, 0, 3)).reshape(-1, 3)
    return values.astype(dtype, copy=False) if dtype is not None else values


def load_float16_lut(path: str | Path, *, expected_dim: int | None = None) -> np.ndarray:
    values = np.fromfile(path, dtype=np.float16)
    return from_r_fastest_values(values, dim=expected_dim, dtype=np.float32)


def save_float16_lut(lut: np.ndarray, path: str | Path) -> None:
    to_r_fastest_values(lut, dtype=np.float16).tofile(path)
