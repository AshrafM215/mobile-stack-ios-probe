#!/usr/bin/env bash
# Candidate A (Flutter 3.47.5) iOS feasibility - NON-PRODUCTION / SYNTHETIC DATA ONLY.
set -euo pipefail
source "$(dirname "$0")/probe-common.sh"
C=candidate-a-flutter
FLUTTER_ZIP_URL=https://storage.googleapis.com/flutter_infra_release/releases/stable/macos/flutter_macos_arm64_3.47.5-stable.zip
FLUTTER_ZIP_SHA256=d4dd908b5f8f65515831b6d68ae33307a813f2b68947dded7a1994ee5ea7cead

select_xcode
capture_env "$C"
bash "$(dirname "$0")/prepare-data.sh"
curl -fsSL --retry 3 -o "$RUNNER_TEMP/flutter.zip" "$FLUTTER_ZIP_URL"
echo "$FLUTTER_ZIP_SHA256  $RUNNER_TEMP/flutter.zip" | shasum -a 256 -c -
unzip -q "$RUNNER_TEMP/flutter.zip" -d "$RUNNER_TEMP/sdk"
export PATH="$RUNNER_TEMP/sdk/flutter/bin:$PATH"
export FLUTTER_SUPPRESS_ANALYTICS=true DASH__SUPPRESS_ANALYTICS=true
F=(flutter --suppress-analytics --no-version-check)
"${F[@]}" --version | tee "$EVIDENCE_DIR/$C-flutter-version.txt"

cd "$C"
"${F[@]}" pub get --enforce-lockfile 2>&1 | tee "$EVIDENCE_DIR/$C-pub-get.txt"
"${F[@]}" test 2>&1 | tee "$EVIDENCE_DIR/$C-unit-tests.txt"
"${F[@]}" build ios --simulator --debug 2>&1 | tee "$EVIDENCE_DIR/$C-build-simulator.txt"
APP=build/ios/iphonesimulator/Runner.app
hash_tree "$APP" "$C-simulator-app"
UDID=$(create_simulator G1Probe-A)
launch_and_wait_ready "$UDID" "$APP" com.example.g1bench.candidatea "$C"
run_e2e "$UDID" com.example.g1bench.candidatea g1bench-a "$C"
"${F[@]}" build ios --release --no-codesign 2>&1 | tee "$EVIDENCE_DIR/$C-build-iphoneos-unsigned.txt"
hash_tree build/ios/iphoneos/Runner.app "$C-iphoneos-unsigned-app"
cp ios/Podfile.lock "$EVIDENCE_DIR/$C-Podfile.lock" 2>/dev/null || true
find ios -name Package.resolved -exec cp {} "$EVIDENCE_DIR/$C-Package.resolved" \; || true
