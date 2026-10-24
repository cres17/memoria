#!/usr/bin/env bash
# AAB(또는 APK)가 디버그 인증서로 서명되지 않았는지 확인한다.
# Play Console은 디버그 서명 번들을 거부한다.
set -euo pipefail

file="${1:?usage: verify_aab_signature.sh <app.aab|app.apk>}"
test -s "$file" || { echo "::error::$file not found"; exit 1; }

out="$(keytool -printcert -jarfile "$file" 2>&1 || true)"
echo "$out" | sed -n '1,12p'

if ! echo "$out" | grep -q "Owner:"; then
  echo "::error::$file has no signing certificate"
  exit 1
fi
if echo "$out" | grep -qiE "Owner:.*CN=Android Debug"; then
  echo "::error::$file is signed with the Android debug certificate"
  exit 1
fi
echo "OK: $file is signed with a non-debug certificate"
