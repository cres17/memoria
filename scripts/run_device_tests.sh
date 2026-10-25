#!/bin/bash
# Existing cross-platform integration suite. The new GPU test has its own
# mandatory iOS job, fixture preparation and measured performance gate.
set -euo pipefail
tests=()
for target in integration_test/*_test.dart; do
  [ -f "$target" ] || continue
  [ "$target" != "integration_test/ios_gpu_ops_test.dart" ] || continue
  tests+=("$target")
done
if [ "${#tests[@]}" -eq 0 ]; then
  echo 'No cross-platform integration tests selected' >&2
  exit 1
fi
if [ "${1:-}" = '--list' ]; then
  printf '%s\n' "${tests[@]}"
  exit 0
fi
flutter test "${tests[@]}" -d "${1:?device ID required}" --reporter expanded 2>&1 |
  tee "${2:?log path required}"
