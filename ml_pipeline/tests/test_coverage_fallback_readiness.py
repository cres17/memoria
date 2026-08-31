import importlib.util
import tempfile
import unittest
from pathlib import Path

import numpy as np
from PIL import Image


SCRIPT = Path(__file__).resolve().parents[1] / "45_audit_coverage_fallback_readiness.py"
SPEC = importlib.util.spec_from_file_location("coverage_fallback_readiness", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)

HALD_SCRIPT = Path(__file__).resolve().parents[1] / "49_generate_hald_monochrome_calibration.py"
HALD_SPEC = importlib.util.spec_from_file_location("hald_calibration", HALD_SCRIPT)
HALD_MODULE = importlib.util.module_from_spec(HALD_SPEC)
assert HALD_SPEC.loader is not None
HALD_SPEC.loader.exec_module(HALD_MODULE)


class CoverageFallbackReadinessTest(unittest.TestCase):
    def test_source_summary_never_opens_test_coverage(self):
        split_rows = [
            {
                "id": "train-1", "sourceLut": "/train.bin", "split": "train",
                "samplingGroup": "app", "sourceLutSha256": "a",
            },
            {
                "id": "test-1", "sourceLut": "/test.bin", "split": "test",
                "samplingGroup": "app", "sourceLutSha256": "b",
            },
        ]
        # Deliberately omit the test row. The audit must not require it.
        summary = MODULE.source_summary(
            split_rows,
            [{"id": "train-1", "observed_cube_fraction": 0.02}],
        )
        self.assertEqual(summary["/train.bin"]["meanObservedCoverage"], 0.02)
        self.assertIsNone(summary["/test.bin"]["meanObservedCoverage"])

    def test_catalog_deduplicates_paths(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            (root / "one.bin").write_bytes(b"lut")
            (root / "ignore.txt").write_text("not a lut")
            self.assertEqual(MODULE.catalog_files([root, root]), [(root / "one.bin").resolve()])

    def test_hald_loader_uses_r_fastest_contract(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "hald.png"
            # Level 2 => cube dimension 4 and 8x8 image. Red-fastest flat order.
            values = np.arange(64, dtype=np.uint8).reshape(8, 8)
            Image.fromarray(values, mode="L").save(path)
            lut = HALD_MODULE.load_hald_lut(path)
            self.assertEqual(lut.shape, (4, 4, 4, 3))
            self.assertAlmostEqual(float(lut[1, 0, 0, 0]), 1.0 / 255.0)
            self.assertAlmostEqual(float(lut[0, 1, 0, 0]), 4.0 / 255.0)
            self.assertAlmostEqual(float(lut[0, 0, 1, 0]), 16.0 / 255.0)


if __name__ == "__main__":
    unittest.main()
