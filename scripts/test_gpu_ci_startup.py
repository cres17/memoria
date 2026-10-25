"""Exercise real child-process startup recovery without Flutter or a simulator."""
import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location("gpu_ci", Path(__file__).with_name("run_ios_gpu_ci.py"))
gpu_ci = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gpu_ci)


class StartupRecovery(unittest.TestCase):
    def run_child(self, source, **options):
        with tempfile.TemporaryDirectory() as directory:
            result = gpu_ci.run_test({}, 1, command=[sys.executable, "-u", "-c", source],
                                     log_dir=Path(directory), **options)
            self.assertTrue((Path(directory) / "ios-gpu-integration.attempt-1.log").is_file())
            return result

    def test_built_app_that_never_starts_is_terminated_and_retryable(self):
        result, retry = self.run_child("import time; print('Xcode build done.'); time.sleep(10)", startup_timeout=0.1)
        self.assertNotEqual(result, 0)
        self.assertTrue(retry)

    def test_test_assertion_failure_is_not_retryable(self):
        result, retry = self.run_child("import sys; print('Xcode build done.'); print('00:00 +0: iOS Metal parity'); sys.exit(1)")
        self.assertEqual(result, 1)
        self.assertFalse(retry)

    def test_started_successful_test_passes(self):
        result, retry = self.run_child("print('Xcode build done.'); print('00:00 +0: iOS Metal parity')")
        self.assertEqual(result, 0)
        self.assertFalse(retry)

    def test_overall_timeout_is_not_a_startup_retry(self):
        result, retry = self.run_child("import time; print('build not completed'); time.sleep(10)", process_timeout=0.1)
        self.assertNotEqual(result, 0)
        self.assertFalse(retry)


if __name__ == "__main__":
    unittest.main()
