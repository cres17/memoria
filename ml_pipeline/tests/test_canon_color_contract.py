from __future__ import annotations

import sys
import unittest
from pathlib import Path

import numpy as np


PIPELINE_DIR = Path(__file__).resolve().parents[1]
if str(PIPELINE_DIR) not in sys.path:
    sys.path.insert(0, str(PIPELINE_DIR))

from canon_color_contract import (  # noqa: E402
    SRGB_TO_CINEMA_GAMUT,
    linear_to_canon_log,
    srgb_to_canon_log,
)


class CanonColorContractTest(unittest.TestCase):
    def test_gamut_matrix_preserves_neutral_axis(self) -> None:
        np.testing.assert_allclose(
            SRGB_TO_CINEMA_GAMUT @ np.ones(3),
            np.ones(3),
            atol=1e-12,
            rtol=0.0,
        )

    def test_srgb_primaries_are_contained_by_cinema_gamut(self) -> None:
        self.assertGreaterEqual(float(SRGB_TO_CINEMA_GAMUT.min()), 0.0)
        self.assertLessEqual(float(SRGB_TO_CINEMA_GAMUT.max()), 1.0)

    def test_canon_black_anchors_match_aces_reference(self) -> None:
        black = np.zeros((1, 3), dtype=np.float32)
        np.testing.assert_allclose(
            linear_to_canon_log(black, "canon_clog2"),
            0.092864125,
            atol=1e-7,
            rtol=0.0,
        )
        np.testing.assert_allclose(
            linear_to_canon_log(black, "canon_clog3"),
            0.12512219,
            atol=1e-7,
            rtol=0.0,
        )

    def test_canon_log3_uses_linear_to_log_piecewise_branches(self) -> None:
        values = np.asarray(((-0.02, 0.0, 0.02),), dtype=np.float32) * 0.9
        actual = linear_to_canon_log(values, "canon_clog3")
        expected = np.asarray((
            -0.36726845 * np.log10(1.0 + 14.98325 * 0.02) + 0.12783901,
            0.12512219,
            0.36726845 * np.log10(14.98325 * 0.02 + 1.0) + 0.12240537,
        ))
        np.testing.assert_allclose(actual[0], expected, atol=1e-7, rtol=0.0)

    def test_encoded_srgb_stays_inside_cube_domain(self) -> None:
        probes = np.asarray(
            ((0, 0, 0), (1, 1, 1), (1, 0, 0), (0, 1, 0), (0, 0, 1)),
            dtype=np.float32,
        )
        for version in ("canon_clog2", "canon_clog3"):
            encoded = srgb_to_canon_log(probes, version)
            self.assertGreaterEqual(float(encoded.min()), 0.0)
            self.assertLessEqual(float(encoded.max()), 1.0)


if __name__ == "__main__":
    unittest.main()
