"""Install a base64-encoded CI profile without printing signing material."""

import base64
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile
import uuid


def install_profile(encoded_profile, staging_directory, library_directory):
    if isinstance(encoded_profile, bytes):
        encoded_profile = encoded_profile.decode("ascii")
    profile_bytes = base64.b64decode("".join(encoded_profile.split()), validate=True)
    with tempfile.TemporaryDirectory(dir=staging_directory) as temporary:
        source = Path(temporary) / "profile.mobileprovision"
        source.write_bytes(profile_bytes)
        source.chmod(0o600)
        result = subprocess.run(
            ["security", "cms", "-D", "-i", str(source)],
            check=True,
            capture_output=True,
        )
        profile = plistlib.loads(result.stdout)
        # Validate before using the UUID as a filename.
        profile_uuid = str(uuid.UUID(profile["UUID"])).upper()
        for relative_directory in (
            "MobileDevice/Provisioning Profiles",
            "Developer/Xcode/UserData/Provisioning Profiles",
        ):
            destination_directory = Path(library_directory) / relative_directory
            destination_directory.mkdir(parents=True, exist_ok=True)
            destination = destination_directory / f"{profile_uuid}.mobileprovision"
            with tempfile.NamedTemporaryFile(dir=destination_directory, delete=False) as output:
                pending = Path(output.name)
                output.write(profile_bytes)
            try:
                pending.replace(destination)
            finally:
                pending.unlink(missing_ok=True)
        return profile


def configure_release_signing(project_path, profile, export_options_path):
    """Override only Runner Release signing in the disposable CI checkout."""
    profile_uuid = str(uuid.UUID(profile["UUID"])).upper()
    team_id = profile["TeamIdentifier"][0]
    if not re.fullmatch(r"[A-Z0-9]{10}", team_id):
        raise ValueError("Invalid signing team")
    if profile["Entitlements"].get("get-task-allow", False):
        raise ValueError("A distribution profile is required")
    if "ProvisionedDevices" in profile or profile.get("ProvisionsAllDevices", False):
        raise ValueError("An App Store profile is required")

    result = subprocess.run(
        ["plutil", "-convert", "json", "-o", "-", str(project_path)],
        check=True, capture_output=True,
    )
    objects = json.loads(result.stdout)["objects"]
    runner = next(item for item in objects.values()
                  if item.get("isa") == "PBXNativeTarget" and item.get("name") == "Runner")
    configuration_ids = objects[runner["buildConfigurationList"]]["buildConfigurations"]
    release_id = next(item for item in configuration_ids if objects[item]["name"] == "Release")
    bundle_id = objects[release_id]["buildSettings"]["PRODUCT_BUNDLE_IDENTIFIER"]
    profile_bundle_id = profile["Entitlements"]["application-identifier"].partition(".")[2]
    if bundle_id != profile_bundle_id:
        raise ValueError("Profile does not match the Runner bundle identifier")

    source = Path(project_path).read_text()
    pattern = re.compile(
        rf"(?P<start>\b{re.escape(release_id)} /\* Release \*/ = \{{.*?buildSettings = \{{)"
        r"(?P<settings>.*?)(?P<end>\n\s*\};)", re.DOTALL,
    )
    matches = list(pattern.finditer(source))
    if len(matches) != 1:
        raise ValueError("Runner Release configuration could not be located")
    match = matches[0]
    settings = match["settings"]
    replacements = {
        "CODE_SIGN_STYLE": "Manual",
        "CODE_SIGN_IDENTITY": '"Apple Distribution"',
        '"CODE_SIGN_IDENTITY[sdk=iphoneos*]"': '"Apple Distribution"',
        "DEVELOPMENT_TEAM": team_id,
        "PROVISIONING_PROFILE_SPECIFIER": profile_uuid,
    }
    for key, value in replacements.items():
        setting = re.compile(rf"(?m)^\s*{re.escape(key)}\s*=\s*[^\n;]*;")
        settings = setting.sub("", settings)
        settings += f"\n\t\t\t\t{key} = {value};"
    source = source[:match.start()] + match["start"] + settings + match["end"] + source[match.end():]
    Path(project_path).write_text(source)
    Path(export_options_path).write_bytes(plistlib.dumps({
        "method": "app-store-connect",
        "signingStyle": "manual",
        "signingCertificate": "Apple Distribution",
        "teamID": team_id,
        "provisioningProfiles": {bundle_id: profile_uuid},
        "uploadSymbols": True,
    }))


def main():
    try:
        profile = install_profile(
            os.environ["IOS_PROVISIONING_PROFILE"],
            os.environ["RUNNER_TEMP"],
            Path.home() / "Library",
        )
        root = Path(__file__).resolve().parents[1]
        configure_release_signing(
            root / "ios/Runner.xcodeproj/project.pbxproj",
            profile, root / "exportOptions.plist",
        )
    except (KeyError, IndexError, StopIteration, ValueError, OSError, subprocess.SubprocessError, plistlib.InvalidFileException):
        raise SystemExit("App Store profile or Runner signing configuration is invalid.") from None


if __name__ == "__main__":
    main()
