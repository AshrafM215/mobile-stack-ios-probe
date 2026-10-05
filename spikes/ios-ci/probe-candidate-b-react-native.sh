#!/usr/bin/env bash
# Candidate B (React Native 0.87.1) iOS feasibility job - NON-PRODUCTION / SYNTHETIC DATA ONLY.
# Stages: environment (pinned Xcode, runner record, simulator, dataset regeneration check, pinned XcodeGen), resolve (npm
# packages from the lock file, CocoaPods in deployment mode: the lock file may not change, Swift packages at the versions
# of the resolved file), configure (Xcode lists the scheme of the generated workspace), unit (type check and the
# candidate's own unit corpus), build-simulator (Release with the embedded JS bundle), linkage-simulator, launch (to the
# READY marker), e2e (the shared UI flow), build-device (Release, unsigned), linkage-device, lock-check.
set -euo pipefail
source "$(dirname "$0")/probe-common.sh"
C=candidate-b-react-native
BUNDLE_ID=com.example.g1bench.candidateb
URL_SCHEME=g1bench-b
WORKSPACE=ios/G1CandidateB.xcworkspace
PACKAGES=(-clonedSourcePackagesDirPath "$SPM_DIR" -disableAutomaticPackageResolution)
XB=(xcodebuild -workspace "$WORKSPACE" -scheme G1CandidateB "${PACKAGES[@]}")
SIM_APP="$PROBE_ROOT/$C/ios/build/dd/Build/Products/Release-iphonesimulator/G1CandidateB.app"
DEVICE_APP="$PROBE_ROOT/$C/ios/build/dd-device/Build/Products/Release-iphoneos/G1CandidateB.app"

s_environment() {
  select_xcode
  capture_env "$C"
  prepare_simulator G1Probe-B
  bash "$PROBE_ROOT/ios-ci/prepare-data.sh"
  fetch_xcodegen
}

s_resolve() {
  cd "$PROBE_ROOT/$C"
  npm ci --no-audit --no-fund 2>&1 | tee "$EVIDENCE_DIR/$C-npm-ci.txt"
  (cd ios && pod install --deployment 2>&1 | tee "$EVIDENCE_DIR/$C-pod-install.txt")
  "${XB[@]}" -resolvePackageDependencies 2>&1 | tee "$EVIDENCE_DIR/$C-resolve-packages.txt"
}

s_configure() {
  cd "$PROBE_ROOT/$C"
  list_schemes "$C" G1CandidateB -workspace "$WORKSPACE" "${PACKAGES[@]}"
}

s_unit() {
  cd "$PROBE_ROOT/$C"
  npx tsc --noEmit 2>&1 | tee "$EVIDENCE_DIR/$C-typecheck.txt"
  npx jest --ci --json --outputFile="$EVIDENCE_DIR/$C-unit-tests.json" 2>&1 | tee "$EVIDENCE_DIR/$C-unit-tests.txt"
}

s_build_simulator() {
  cd "$PROBE_ROOT/$C"
  "${XB[@]}" -configuration Release -sdk iphonesimulator -destination "id=$(sim_udid)" ONLY_ACTIVE_ARCH=YES \
    -derivedDataPath ios/build/dd CODE_SIGNING_ALLOWED=NO build 2>&1 | tee "$EVIDENCE_DIR/$C-build-simulator.txt"
  hash_tree "$SIM_APP" "$C-simulator-app"
}

s_linkage_simulator() { capture_linkage "$SIM_APP" "$C-simulator-app"; }

s_launch() { launch_and_wait_ready "$(sim_udid)" "$SIM_APP" "$BUNDLE_ID" "$C"; }

s_e2e() { run_e2e "$(sim_udid)" "$BUNDLE_ID" "$URL_SCHEME" "$C"; }

s_build_device() {
  cd "$PROBE_ROOT/$C"
  "${XB[@]}" -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
    -derivedDataPath ios/build/dd-device CODE_SIGNING_ALLOWED=NO build 2>&1 | tee "$EVIDENCE_DIR/$C-build-iphoneos-unsigned.txt"
  hash_tree "$DEVICE_APP" "$C-iphoneos-unsigned-app"
}

s_linkage_device() { capture_linkage "$DEVICE_APP" "$C-iphoneos-unsigned-app"; }

s_lock_check() {
  lock_check "$C" synthetic-data/package-lock.json "$C/package-lock.json" "$C/ios/Podfile.lock" \
    "$C/$WORKSPACE/xcshareddata/swiftpm/Package.resolved"
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
