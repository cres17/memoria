"""Keep unattended CI separate from opt-in device evidence procedures."""
from pathlib import Path
import subprocess
import unittest


class DeviceTestSelectionTest(unittest.TestCase):
    def test_ci_list_retains_feature_gate_and_excludes_manual_procedures(self):
        root = Path(__file__).resolve().parents[1]
        selected = subprocess.check_output(
            ["bash", "scripts/run_device_tests.sh", "--list"],
            cwd=root,
            text=True,
        ).splitlines()
        self.assertIn("integration_test/editor_features_device_test.dart", selected)
        self.assertEqual(len(selected), len(set(selected)))
        for target in selected:
            self.assertTrue((root / target).is_file(), target)
            source = (root / target).read_text()
            self.assertNotIn("requires a physical iOS device", source, target)
        manual = {
            "create_filter_blackbox_device_test",
            "direct_mvp_device_performance_test",
            "editor_4k_export_device_test",
            "ios_portrait_memory_device_test",
            "ios_share_completion_device_test",
            "photo_permission_matrix_device_test",
            "ios_gpu_ops_test",
        }
        self.assertTrue(manual.isdisjoint(Path(p).stem for p in selected))


if __name__ == "__main__":
    unittest.main()
