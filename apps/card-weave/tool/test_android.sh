#!/usr/bin/env bash
set -euo pipefail
app_dir=$(cd -- "$(dirname -- "$0")/.." && pwd)
if [[ $# -ne 2 || "$2" != integration_test/*_test.dart ]]; then
  echo "Usage: bash tool/test_android.sh DEVICE integration_test/NAME_test.dart" >&2
  exit 2
fi
device=$1
test_entry=$2
export CARDWEAVE_ACCEPTANCE=1 CARDWEAVE_BUILD_MODE=debug CARDWEAVE_ENTRYPOINT="$test_entry"
: "${ANDROID_HOME:?Set ANDROID_HOME to Android SDK}"
aapt="$ANDROID_HOME/build-tools/36.0.0/aapt"
[[ -x "$aapt" ]] || { echo "Android Build Tools 36.0.0 aapt is required" >&2; exit 2; }
cd "$app_dir"
[[ -f "$test_entry" ]] || { echo "Test entry does not exist" >&2; exit 2; }
# Flutter caches the existing APK identity before rebuilding and uses it at teardown.
bash tool/build_android.sh
package=$("$aapt" dump badging build/app/outputs/flutter-apk/app-debug.apk |
  sed -n "s/^package: name='\([^']*\)'.*/\1/p")
if [[ "$package" != io.cardweave.app.acceptance ]]; then
  echo "Refusing to test: APK is not the isolated acceptance package" >&2
  exit 2
fi
flutter test "$test_entry" --no-pub -d "$device"
