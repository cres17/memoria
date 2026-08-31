from __future__ import annotations

import importlib
import sys
import tempfile
import unittest
from pathlib import Path

import numpy as np


PIPELINE_DIR = Path(__file__).resolve().parents[1]
if str(PIPELINE_DIR) not in sys.path:
    sys.path.insert(0, str(PIPELINE_DIR))

from lut_axis_contract import (  # noqa: E402
    from_r_fastest_values,
    load_float16_lut,
    save_float16_lut,
    to_r_fastest_values,
)


generator = importlib.import_module("2_generate_dataset")
evaluator = importlib.import_module("17_evaluate_conditional_lut")
v2 = importlib.import_module("11_train_basis_v2")


def identity_lut(dim: int) -> np.ndarray:
    values = np.linspace(0.0, 1.0, dim, dtype=np.float32)
    red, green, blue = np.meshgrid(values, values, values, indexing="ij")
    return np.stack((red, green, blue), axis=-1)


class LutAxisContractTest(unittest.TestCase):
    def test_r_fastest_flat_positions_match_app_formula(self) -> None:
        dim = 3
        lut = np.zeros((dim, dim, dim, 3), dtype=np.float32)
        for red in range(dim):
            for green in range(dim):
                for blue in range(dim):
                    lut[red, green, blue] = (red, green, blue)

        flat = to_r_fastest_values(lut).reshape(-1)
        for red in range(dim):
            for green in range(dim):
                for blue in range(dim):
                    base = (red + green * dim + blue * dim * dim) * 3
                    np.testing.assert_array_equal(
                        flat[base : base + 3], (red, green, blue)
                    )

    def test_float16_round_trip_preserves_rgb_axes(self) -> None:
        expected = identity_lut(5)
        with tempfile.TemporaryDirectory(prefix="memoria-axis-test-") as directory:
            path = Path(directory) / "identity.bin"
            save_float16_lut(expected, path)
            actual = load_float16_lut(path, expected_dim=5)
        np.testing.assert_allclose(actual, expected, atol=1e-3, rtol=0.0)

    def test_dataset_bin_and_cube_loaders_return_rgb_axes(self) -> None:
        dim = 3
        expected = identity_lut(dim)
        persisted = to_r_fastest_values(expected, dtype=np.float16)
        with tempfile.TemporaryDirectory(prefix="memoria-axis-test-") as directory:
            root = Path(directory)
            bin_path = root / "identity.bin"
            cube_path = root / "identity.cube"
            persisted.tofile(bin_path)
            cube_path.write_text(
                "LUT_3D_SIZE 3\n"
                + "\n".join(" ".join(str(float(value)) for value in row) for row in persisted)
                + "\n"
            )

            original_dim = generator.LUT_DIM
            generator.LUT_DIM = dim
            try:
                loaded_bin = generator.load_bin_lut(str(bin_path))
                loaded_cube = generator.load_cube_lut(str(cube_path))
            finally:
                generator.LUT_DIM = original_dim

        np.testing.assert_allclose(loaded_bin, expected, atol=1e-3, rtol=0.0)
        np.testing.assert_allclose(loaded_cube, expected, atol=1e-3, rtol=0.0)

    def test_primary_and_mixed_probes_survive_evaluator_load(self) -> None:
        dim = 5
        expected = identity_lut(dim)
        probes = np.asarray(
            ((1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0), (0.75, 0.25, 0.10)),
            dtype=np.float32,
        )
        values = to_r_fastest_values(expected, dtype=np.float16)
        canonical = from_r_fastest_values(values, dim=dim)
        outputs = evaluator.apply_lut(probes, canonical)
        np.testing.assert_allclose(outputs, probes, atol=1e-3, rtol=0.0)

    def test_active_v2_baseline_loaders_preserve_rgb_axes(self) -> None:
        expected = identity_lut(v2.LUT_DIM)
        indices = np.linspace(0, v2.LUT_DIM - 1, v2.BASIS_DIM).round().astype(np.int64)
        expected_small = expected[np.ix_(indices, indices, indices)]
        with tempfile.TemporaryDirectory(prefix="memoria-axis-test-") as directory:
            path = Path(directory) / "identity.bin"
            save_float16_lut(expected, path)
            full = v2.load_lut_tensor(path).numpy()
            small = v2.load_small_lut(path).reshape(v2.BASIS_DIM, v2.BASIS_DIM, v2.BASIS_DIM, 3)

        np.testing.assert_allclose(full, expected, atol=1e-3, rtol=0.0)
        np.testing.assert_allclose(small, expected_small, atol=1e-3, rtol=0.0)


if __name__ == "__main__":
    unittest.main()
