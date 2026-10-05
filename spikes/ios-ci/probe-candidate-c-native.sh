#!/usr/bin/env bash
# Candidate C (native Swift/SwiftUI) iOS feasibility job - NON-PRODUCTION / SYNTHETIC DATA ONLY.
# Stages: environment (pinned Xcode, runner record, simulator, dataset regeneration check - also the common module's
# resources - and pinned XcodeGen), configure (XcodeGen writes the project from project.yml and Xcode lists the scheme),
# resolve (Swift packages at the versions of the resolved file), unit (the candidate's own unit corpus on the simulator),
# build-simulator (Release), linkage-simulator, launch (to the READY marker), e2e (the shared UI flow), build-device
# (Release, unsigned), linkage-device, inventory (Swift packages with their licence files), lock-check. In update mode
# the package resolution may write the resolved file.
set -euo pipefail
source "$(dirname "$0")/probe-common.sh"
C=candidate-c-native
BUNDLE_ID=com.example.g1bench.candidatec
URL_SCHEME=g1bench-c
PROJECT=G1CandidateC.xcodeproj
PACKAGES=(-clonedSourcePackagesDirPath "$SPM_DIR")
if [ "$G1_RESOLUTION" = locked ]; then PACKAGES+=(-disableAutomaticPackageResolution); fi
XB=(xcodebuild -project "$PROJECT" -scheme G1CandidateC "${PACKAGES[@]}")
SIM_APP="$PROBE_ROOT/$C/ios/build/dd/Build/Products/Release-iphonesimulator/G1CandidateC.app"
DEVICE_APP="$PROBE_ROOT/$C/ios/build/dd-device/Build/Products/Release-iphoneos/G1CandidateC.app"

s_environment() {
  select_xcode
  capture_env "$C"
  prepare_simulator G1Probe-C
  prepare_data
  fetch_xcodegen
}

s_configure() {
  cd "$PROBE_ROOT/$C/ios"
  "$XCODEGEN_BIN" generate --spec project.yml 2>&1 | tee "$EVIDENCE_DIR/$C-xcodegen.txt"
  list_schemes "$C" G1CandidateC -project "$PROJECT" "${PACKAGES[@]}"
}

s_resolve() {
  cd "$PROBE_ROOT/$C/ios"
  "${XB[@]}" -resolvePackageDependencies 2>&1 | tee "$EVIDENCE_DIR/$C-resolve-packages.txt"
}

s_unit() {
  local rc=0
  cd "$PROBE_ROOT/$C/ios"
  "${XB[@]}" -destination "id=$(sim_udid)" -derivedDataPath build/dd -resultBundlePath "$EVIDENCE_DIR/$C-tests.xcresult" \
    CODE_SIGNING_ALLOWED=NO test 2>&1 | tee "$EVIDENCE_DIR/$C-tests.txt" || rc=$?
  export_test_results "$EVIDENCE_DIR/$C-tests.xcresult" "$C-tests"
  return "$rc"
}

s_build_simulator() {
  cd "$PROBE_ROOT/$C/ios"
  "${XB[@]}" -configuration Release -sdk iphonesimulator -destination "id=$(sim_udid)" ONLY_ACTIVE_ARCH=YES \
    -derivedDataPath build/dd CODE_SIGNING_ALLOWED=NO build 2>&1 | tee "$EVIDENCE_DIR/$C-build-simulator.txt"
  hash_tree "$SIM_APP" "$C-simulator-app"
}

s_linkage_simulator() { capture_linkage "$SIM_APP" "$C-simulator-app"; }

s_launch() { launch_and_wait_ready "$(sim_udid)" "$SIM_APP" "$BUNDLE_ID" "$C"; }

s_e2e() { run_e2e "$(sim_udid)" "$BUNDLE_ID" "$URL_SCHEME" "$C"; }

s_build_device() {
  cd "$PROBE_ROOT/$C/ios"
  "${XB[@]}" -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
    -derivedDataPath build/dd-device CODE_SIGNING_ALLOWED=NO build 2>&1 | tee "$EVIDENCE_DIR/$C-build-iphoneos-unsigned.txt"
  hash_tree "$DEVICE_APP" "$C-iphoneos-unsigned-app"
  capture_app_metadata "$DEVICE_APP" "$C-iphoneos-unsigned-app"
}

s_linkage_device() { capture_linkage "$DEVICE_APP" "$C-iphoneos-unsigned-app"; }

s_inventory() { capture_dependencies "$C"; }

s_lock_check() {
  lock_check "$C" synthetic-data/package-lock.json "$C/ios/$PROJECT/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
}

job_begin "$C" environment configure resolve unit build-simulator linkage-simulator launch e2e build-device linkage-device inventory lock-check
stage environment s_environment
stage configure needs:environment s_configure
stage resolve needs:configure s_resolve
stage unit needs:resolve s_unit
stage build-simulator needs:resolve s_build_simulator
stage linkage-simulator needs:build-simulator s_linkage_simulator
stage launch needs:build-simulator s_launch
stage e2e needs:launch s_e2e
stage build-device needs:resolve s_build_device
stage linkage-device needs:build-device s_linkage_device
stage inventory needs:resolve s_inventory
stage lock-check needs:resolve s_lock_check
job_finish
