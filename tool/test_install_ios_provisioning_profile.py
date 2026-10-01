import base64
import copy
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from install_ios_provisioning_profile import configure_release_signing, install_profile


PROFILE = {
    "UUID": "12345678-1234-1234-1234-123456789ABC",
    "TeamIdentifier": ["TESTTEAM01"],
    "Entitlements": {
        "application-identifier": "TESTTEAM01.com.example.memoria",
        "get-task-allow": False,
    },
}
PROJECT = {"objects": {
    "TARGET": {"isa": "PBXNativeTarget", "name": "Runner", "buildConfigurationList": "CONFIGS"},
    "CONFIGS": {"buildConfigurations": ["DEBUG", "RELEASE"]},
    "DEBUG": {"name": "Debug", "buildSettings": {}},
    "RELEASE": {"name": "Release", "buildSettings": {"PRODUCT_BUNDLE_IDENTIFIER": "com.example.memoria"}},
}}
SOURCE = '''DEBUG /* Debug */ = {
    buildSettings = {
        CODE_SIGN_IDENTITY = "Apple Development";
    };
    name = Debug;
};
RELEASE /* Release */ = {
    buildSettings = {
        DEVELOPMENT_TEAM = OLDTEAM001;
        PRODUCT_BUNDLE_IDENTIFIER = com.example.memoria;
    };
    name = Release;
};
'''


class SigningTests(unittest.TestCase):
    def test_installs_original_profile_under_validated_uuid(self):
        payload = b"test CMS payload"
        result = subprocess.CompletedProcess([], 0, plistlib.dumps(PROFILE))
        with tempfile.TemporaryDirectory() as temporary, patch(
            "install_ios_provisioning_profile.subprocess.run", return_value=result
        ):
            root = Path(temporary)
            installed = install_profile(base64.b64encode(payload), root, root / "Library")
            self.assertEqual(installed, PROFILE)
            files = list(root.rglob("*.mobileprovision"))
            self.assertEqual(len(files), 2)
            for file in files:
                self.assertEqual(file.name, PROFILE["UUID"] + ".mobileprovision")
                self.assertEqual(file.read_bytes(), payload)
                self.assertEqual(file.stat().st_mode & 0o777, 0o600)

    def test_rejects_invalid_base64_without_running_security(self):
        with tempfile.TemporaryDirectory() as root, patch(
            "install_ios_provisioning_profile.subprocess.run"
        ) as run:
            with self.assertRaises(ValueError):
                install_profile("not base64", root, root)
            run.assert_not_called()

    def test_release_signing_preserves_debug_and_sets_export_mapping(self):
        result = subprocess.CompletedProcess([], 0, json.dumps(PROJECT).encode())
        with tempfile.TemporaryDirectory() as temporary, patch(
            "install_ios_provisioning_profile.subprocess.run", return_value=result
        ):
            root = Path(temporary)
            project = root / "project.pbxproj"
            project.write_text(SOURCE)
            export = root / "exportOptions.plist"
            configure_release_signing(project, PROFILE, export)
            rewritten = project.read_text()
            self.assertEqual(rewritten.split("RELEASE")[0], SOURCE.split("RELEASE")[0])
            self.assertIn('CODE_SIGN_IDENTITY = "Apple Distribution";', rewritten)
            self.assertNotIn("OLDTEAM001", rewritten)
            self.assertIn("CODE_SIGN_STYLE = Manual;", rewritten)
            options = plistlib.loads(export.read_bytes())
            self.assertEqual(options["provisioningProfiles"], {"com.example.memoria": PROFILE["UUID"]})
            self.assertEqual(options["teamID"], "TESTTEAM01")

    def test_rejects_development_device_or_wrong_bundle_profiles_before_rewriting(self):
        result = subprocess.CompletedProcess([], 0, json.dumps(PROJECT).encode())
        for change in ("development", "device", "bundle"):
            profile = copy.deepcopy(PROFILE)
            if change == "development":
                profile["Entitlements"]["get-task-allow"] = True
            elif change == "device":
                profile["ProvisionedDevices"] = ["test-device"]
            else:
                profile["Entitlements"]["application-identifier"] = "TESTTEAM01.com.example.other"
            with self.subTest(change=change), tempfile.TemporaryDirectory() as temporary, patch(
                "install_ios_provisioning_profile.subprocess.run", return_value=result
            ):
                project = Path(temporary) / "project.pbxproj"
                project.write_text(SOURCE)
                with self.assertRaises(ValueError):
                    configure_release_signing(project, profile, Path(temporary) / "export.plist")
                self.assertEqual(project.read_text(), SOURCE)


if __name__ == "__main__":
    unittest.main()
