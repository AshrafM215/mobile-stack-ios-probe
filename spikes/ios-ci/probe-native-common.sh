#!/usr/bin/env bash
# Common native module (Swift package G1NativeCommon) iOS feasibility job - NON-PRODUCTION / SYNTHETIC DATA ONLY.
# Stages: environment (pinned Xcode, runner record, simulator, dataset regeneration check: the module's resources), unit
# (the module's trust contract suite on the simulator, which runs for this stage only), build-device (the package
# builds for a device), lock-check.
set -euo pipefail
source "$(dirname "$0")/probe-common.sh"
N=native-common

# the scheme Xcode offers for the package (the package scheme when the package has more than one product scheme)
package_scheme() {
  if grep -q "G1NativeCommon-Package" "$EVIDENCE_DIR/$N-schemes.txt"; then echo G1NativeCommon-Package; else echo G1NativeCommon; fi
}

s_environment() {
  select_xcode
  capture_env "$N"
  prepare_simulator G1Probe-N
  prepare_data
  cd "$PROBE_ROOT/native-common/ios"
  xcodebuild -list 2>&1 | tee "$EVIDENCE_DIR/$N-schemes.txt"
}

s_unit() {
  local rc=0
  cd "$PROBE_ROOT/native-common/ios"
  sim_up
  xcodebuild -scheme "$(package_scheme)" -destination "id=$(sim_udid)" -derivedDataPath build/dd \
    -resultBundlePath "$EVIDENCE_DIR/$N-tests.xcresult" CODE_SIGNING_ALLOWED=NO test 2>&1 | tee "$EVIDENCE_DIR/$N-tests.txt" || rc=$?
  sim_down
  export_test_results "$EVIDENCE_DIR/$N-tests.xcresult" "$N-tests"
  return "$rc"
}

s_build_device() {
  cd "$PROBE_ROOT/native-common/ios"
  xcodebuild -scheme "$(package_scheme)" -destination 'generic/platform=iOS' -derivedDataPath build/dd-device \
    CODE_SIGNING_ALLOWED=NO build 2>&1 | tee "$EVIDENCE_DIR/$N-build-iphoneos.txt"
}

s_lock_check() { lock_check "$N" synthetic-data/package-lock.json; }

job_begin "$N" environment unit build-device lock-check
stage environment s_environment
stage unit needs:environment s_unit
stage build-device needs:environment s_build_device
stage lock-check needs:environment s_lock_check
job_finish
