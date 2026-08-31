"""Canon Log / Cinema Gamut input contract used by dataset generation.

The Canon look files in ``LUT/`` declare Canon Log 2 or Canon Log 3 encoded
Cinema Gamut input.  App images are sRGB, so both the RGB primaries and the
transfer function must be converted before indexing those LUTs.

The Cinema Gamut primaries and Canon Log transfer functions below follow the
ACES Input and Color Space Conversion reference transforms published by the
Academy Software Foundation / ACES project.
"""

from __future__ import annotations

import numpy as np


SRGB_PRIMARIES = np.asarray(
    ((0.6400, 0.3300), (0.3000, 0.6000), (0.1500, 0.0600)),
    dtype=np.float64,
)
CINEMA_GAMUT_PRIMARIES = np.asarray(
    ((0.7400, 0.2700), (0.1700, 1.1400), (0.0800, -0.1000)),
    dtype=np.float64,
)
D65_WHITE = np.asarray((0.3127, 0.3290), dtype=np.float64)


def _rgb_to_xyz_matrix(primaries: np.ndarray, white: np.ndarray) -> np.ndarray:
    """Return the linear-light RGB-to-XYZ matrix for xy primaries and white."""
    xyz_columns = []
    for x, y in primaries:
        xyz_columns.append((x / y, 1.0, (1.0 - x - y) / y))
    unscaled = np.asarray(xyz_columns, dtype=np.float64).T
    xw, yw = white
    white_xyz = np.asarray((xw / yw, 1.0, (1.0 - xw - yw) / yw))
    scales = np.linalg.solve(unscaled, white_xyz)
    return unscaled * scales


SRGB_TO_CINEMA_GAMUT = (
    np.linalg.inv(_rgb_to_xyz_matrix(CINEMA_GAMUT_PRIMARIES, D65_WHITE))
    @ _rgb_to_xyz_matrix(SRGB_PRIMARIES, D65_WHITE)
).astype(np.float64)


def srgb_to_linear(values: np.ndarray) -> np.ndarray:
    values = np.asarray(values, dtype=np.float64)
    return np.where(
        values <= 0.04045,
        values / 12.92,
        ((values + 0.055) / 1.055) ** 2.4,
    )


def linear_to_canon_log(values: np.ndarray, log_version: str) -> np.ndarray:
    """Encode scene-linear Cinema Gamut values using the ACES Canon curves."""
    values = np.asarray(values, dtype=np.float64) / 0.9
    if log_version == "canon_clog2":
        encoded = np.empty_like(values)
        negative = values < 0.0
        encoded[negative] = (
            -0.24136077 * np.log10(1.0 - 87.099375 * values[negative])
            + 0.092864125
        )
        encoded[~negative] = (
            0.24136077 * np.log10(87.099375 * values[~negative] + 1.0)
            + 0.092864125
        )
    elif log_version == "canon_clog3":
        encoded = np.empty_like(values)
        negative = values < -0.014
        linear = (values >= -0.014) & (values <= 0.014)
        positive = values > 0.014
        encoded[negative] = (
            -0.36726845 * np.log10(1.0 - 14.98325 * values[negative])
            + 0.12783901
        )
        encoded[linear] = 1.9754798 * values[linear] + 0.12512219
        encoded[positive] = (
            0.36726845 * np.log10(14.98325 * values[positive] + 1.0)
            + 0.12240537
        )
    else:
        raise ValueError(f"unsupported Canon log version: {log_version}")
    return encoded.astype(np.float32)


def srgb_to_canon_log(values: np.ndarray, log_version: str) -> np.ndarray:
    """Convert encoded sRGB values to Canon Log / Cinema Gamut LUT input."""
    linear_srgb = srgb_to_linear(values)
    linear_cinema_gamut = linear_srgb @ SRGB_TO_CINEMA_GAMUT.T
    encoded = linear_to_canon_log(linear_cinema_gamut, log_version)
    return np.clip(encoded, 0.0, 1.0).astype(np.float32)
