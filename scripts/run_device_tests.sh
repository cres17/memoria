#!/bin/bash
# Deterministic cross-platform simulator/emulator gate. Physical-device/profile
# benchmarks and manual share/permission matrices have dedicated drivers;
# adding a test file must never opt those procedures into unattended CI.
# Metal parity has a separate mandatory iOS job and performance gate.
set -euo pipefail
tests=(
  integration_test/editor_features_device_test.dart
  integration_test/editor_performance_test.dart
  integration_test/editor_whitebox_device_test.dart
  integration_test/ios_native_webp_test.dart
  integration_test/settings_recovery_ui_test.dart
)
for target in "${tests[@]}"; do
  if [ ! -f "$target" ]; then
    echo "Missing required CI integration test: $target" >&2
    exit 1
  fi
done
if [ "${1:-}" = '--list' ]; then
  printf '%s\n' "${tests[@]}"
  exit 0
fi
flutter test "${tests[@]}" -d "${1:?device ID required}" --reporter expanded 2>&1 |
  tee "${2:?log path required}"
