#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo 'Usage: tool/run_ios_device_validation.sh memory|share DEVICE_ID DEVICE_NAME' >&2
  exit 2
fi
case "$1" in
  memory) target='integration_test/ios_portrait_memory_device_test.dart' ;;
  share) target='integration_test/ios_share_completion_device_test.dart' ;;
  *) echo 'Choose memory or share.' >&2; exit 2 ;;
esac

cd "$(dirname "$0")/.."
flutter_bin="${MEMORIA_FLUTTER_BIN:-flutter}"
if ! command -v "$flutter_bin" >/dev/null 2>&1; then
  flutter_bin="$HOME/flutter/bin/flutter"
fi
if ! command -v "$flutter_bin" >/dev/null 2>&1; then
  echo 'Set MEMORIA_FLUTTER_BIN to your Flutter executable.' >&2
  exit 2
fi
mkdir -p build/device-validation
export MEMORIA_IOS_VALIDATION_OUTPUT="build/device-validation/$1.json"
export MEMORIA_IOS_VALIDATION_COMMIT="$(git rev-parse HEAD)"

"$flutter_bin" drive --profile --no-pub --publish-port \
  --driver test_driver/ios_device_validation_driver.dart \
  --target "$target" \
  --device-id "$2" \
  --dart-define=MEMORIA_PHYSICAL_DEVICE=true \
  --dart-define="MEMORIA_PERF_DEVICE_NAME=$3" \
  --dart-define=MEMORIA_RSS_DELTA_LIMIT_MIB=500 \
  2>&1 | tee "build/device-validation/$1.log"
