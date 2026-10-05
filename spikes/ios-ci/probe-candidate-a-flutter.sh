#!/usr/bin/env bash
# Candidate A (Flutter 3.47.5) iOS feasibility job - NON-PRODUCTION / SYNTHETIC DATA ONLY.
# Stages: environment (pinned Xcode, runner record, simulator, dataset regeneration check, pinned Flutter SDK and
# XcodeGen), resolve (Dart packages from the lock file), configure (Flutter writes the iOS project configuration and Xcode
# lists the scheme), unit (the candidate's own unit corpus), build-simulator (debug: the only mode Flutter builds for a
# simulator), linkage-simulator, launch (to the READY marker), e2e (the shared UI flow), build-device (release, unsigned),
# linkage-device, lock-check. The Swift packages of the native side are fetched by Xcode when it first loads the project.
set -euo pipefail
source "$(dirname "$0")/probe-common.sh"
C=candidate-a-flutter
BUNDLE_ID=com.example.g1bench.candidatea
URL_SCHEME=g1bench-a
FLUTTER_ZIP_URL=https://storage.googleapis.com/flutter_infra_release/releases/stable/macos/flutter_macos_arm64_3.47.5-stable.zip
FLUTTER_ZIP_SHA256=d4dd908b5f8f65515831b6d68ae33307a813f2b68947dded7a1994ee5ea7cead
export PATH="$RUNNER_TEMP/sdk/flutter/bin:$PATH"
export FLUTTER_SUPPRESS_ANALYTICS=true DASH__SUPPRESS_ANALYTICS=true
F=(flutter --suppress-analytics --no-version-check)
SIM_APP="$PROBE_ROOT/$C/build/ios/iphonesimulator/Runner.app"
DEVICE_APP="$PROBE_ROOT/$C/build/ios/iphoneos/Runner.app"

s_environment() {
  select_xcode
  capture_env "$C"
  prepare_simulator G1Probe-A
  bash "$PROBE_ROOT/ios-ci/prepare-data.sh"
  fetch_xcodegen
  curl -fsSL --retry 3 -o "$RUNNER_TEMP/flutter.zip" "$FLUTTER_ZIP_URL"
  echo "$FLUTTER_ZIP_SHA256  $RUNNER_TEMP/flutter.zip" | shasum -a 256 -c -
  unzip -q "$RUNNER_TEMP/flutter.zip" -d "$RUNNER_TEMP/sdk"
  "${F[@]}" --version | tee "$EVIDENCE_DIR/$C-flutter-version.txt"
}

s_resolve() {
  cd "$PROBE_ROOT/$C"
  "${F[@]}" pub get --enforce-lockfile 2>&1 | tee "$EVIDENCE_DIR/$C-pub-get.txt"
}

s_configure() {
  cd "$PROBE_ROOT/$C"
  "${F[@]}" build ios --config-only --simulator --debug --no-pub 2>&1 | tee "$EVIDENCE_DIR/$C-configure.txt"
  list_schemes "$C" Runner -workspace ios/Runner.xcworkspace
}

s_unit() {
  cd "$PROBE_ROOT/$C"
  "${F[@]}" test --no-pub --file-reporter "json:$EVIDENCE_DIR/$C-unit-tests.json" 2>&1 | tee "$EVIDENCE_DIR/$C-unit-tests.txt"
}

s_build_simulator() {
  cd "$PROBE_ROOT/$C"
  "${F[@]}" build ios --simulator --debug --no-pub 2>&1 | tee "$EVIDENCE_DIR/$C-build-simulator.txt"
  hash_tree "$SIM_APP" "$C-simulator-app"
}

s_linkage_simulator() { capture_linkage "$SIM_APP" "$C-simulator-app"; }

s_launch() { launch_and_wait_ready "$(sim_udid)" "$SIM_APP" "$BUNDLE_ID" "$C"; }

s_e2e() { run_e2e "$(sim_udid)" "$BUNDLE_ID" "$URL_SCHEME" "$C"; }

s_build_device() {
  cd "$PROBE_ROOT/$C"
  "${F[@]}" build ios --release --no-codesign --no-pub 2>&1 | tee "$EVIDENCE_DIR/$C-build-iphoneos-unsigned.txt"
  hash_tree "$DEVICE_APP" "$C-iphoneos-unsigned-app"
}

s_linkage_device() { capture_linkage "$DEVICE_APP" "$C-iphoneos-unsigned-app"; }

s_lock_check() {
  lock_check "$C" synthetic-data/package-lock.json "$C/pubspec.lock" "$C/ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved" \
    "$C/ios/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
}

job_begin "$C" environment resolve configure unit build-simulator linkage-simulator launch e2e build-device linkage-device lock-check
stage environment s_environment
stage resolve needs:environment s_resolve
stage configure needs:resolve s_configure
stage unit needs:resolve s_unit
stage build-simulator needs:configure s_build_simulator
stage linkage-simulator needs:build-simulator s_linkage_simulator
stage launch needs:build-simulator s_launch
stage e2e needs:launch s_e2e
stage build-device needs:configure s_build_device
stage linkage-device needs:build-device s_linkage_device
stage lock-check needs:resolve s_lock_check
job_finish
