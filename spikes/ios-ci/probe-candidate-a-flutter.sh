#!/usr/bin/env bash
# Candidate A (Flutter) iOS feasibility job - NON-PRODUCTION / SYNTHETIC DATA ONLY.
# Stages: environment (pinned Xcode, runner record, simulator, dataset regeneration check, the Flutter SDK the candidate
# pins in g1-toolchain.json and XcodeGen), resolve (Dart packages from the lock file), configure (Flutter writes the iOS
# project configuration and Xcode lists the scheme), unit (the candidate's own unit corpus), build-simulator (debug: the
# only mode Flutter builds for a simulator), linkage-simulator, launch (to the READY marker), e2e (the shared UI flow),
# build-device (release, unsigned), linkage-device, inventory (Swift packages with their licence files), lock-check. The
# Swift packages of the native side are fetched by Xcode when it first loads the project.
set -euo pipefail
source "$(dirname "$0")/probe-common.sh"
C=candidate-a-flutter
BUNDLE_ID=com.example.g1bench.candidatea
URL_SCHEME=g1bench-a
export PATH="$RUNNER_TEMP/sdk/flutter/bin:$PATH"
export FLUTTER_SUPPRESS_ANALYTICS=true DASH__SUPPRESS_ANALYTICS=true
F=(flutter --suppress-analytics --no-version-check)
SIM_APP="$PROBE_ROOT/$C/build/ios/iphonesimulator/Runner.app"
DEVICE_APP="$PROBE_ROOT/$C/build/ios/iphoneos/Runner.app"

s_environment() {
  select_xcode
  capture_env "$C"
  prepare_simulator G1Probe-A
  prepare_data
  fetch_xcodegen
  # the SDK archive of the tuple the tree pins (an upgraded tree pins its own), fetched by URL and checked by digest
  local url sha
  url=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["flutter_sdk"]["macos_arm64"]["url"])' "$PROBE_ROOT/$C/g1-toolchain.json")
  sha=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["flutter_sdk"]["macos_arm64"]["sha256"])' "$PROBE_ROOT/$C/g1-toolchain.json")
  case "$url" in https://storage.googleapis.com/flutter_infra_release/releases/*) ;; *) echo "Flutter SDK archive outside the release storage: $url" >&2; return 3 ;; esac
  curl -fsSL --retry 3 -o "$RUNNER_TEMP/flutter.zip" "$url"
  echo "$sha  $RUNNER_TEMP/flutter.zip" | shasum -a 256 -c -
  unzip -q "$RUNNER_TEMP/flutter.zip" -d "$RUNNER_TEMP/sdk"
  "${F[@]}" --version | tee "$EVIDENCE_DIR/$C-flutter-version.txt"
}

s_resolve() {
  cd "$PROBE_ROOT/$C"
  if [ "$G1_RESOLUTION" = locked ]; then
    "${F[@]}" pub get --enforce-lockfile 2>&1 | tee "$EVIDENCE_DIR/$C-pub-get.txt"
  else
    "${F[@]}" pub get 2>&1 | tee "$EVIDENCE_DIR/$C-pub-get.txt"
  fi
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
  capture_app_metadata "$DEVICE_APP" "$C-iphoneos-unsigned-app"
}

s_linkage_device() { capture_linkage "$DEVICE_APP" "$C-iphoneos-unsigned-app"; }

s_inventory() { capture_dependencies "$C" "$PROBE_ROOT/$C/build" "$PROBE_ROOT/$C/ios" "$HOME/Library/Developer/Xcode/DerivedData"; }

s_lock_check() {
  lock_check "$C" synthetic-data/package-lock.json "$C/pubspec.lock" "$C/ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved" \
    "$C/ios/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
}

job_begin "$C" environment resolve configure unit build-simulator linkage-simulator launch e2e build-device linkage-device inventory lock-check
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
stage inventory needs:build-device s_inventory
stage lock-check needs:resolve s_lock_check
job_finish
