#!/usr/bin/env bash
# Synthetic iOS feasibility probe - NON-PRODUCTION / SYNTHETIC DATA ONLY.
# Shared helpers: pinned Xcode selection, environment capture, simulator lifecycle and evidence capture.
set -euo pipefail

: "${XCODE_APP:=/Applications/Xcode_26.6.app}"
: "${SIM_DEVICE_TYPE:=com.apple.CoreSimulator.SimDeviceType.iPhone-17}"
: "${SIM_RUNTIME:=com.apple.CoreSimulator.SimRuntime.iOS-26-5}"
: "${EVIDENCE_DIR:=$PWD/evidence}"
mkdir -p "$EVIDENCE_DIR"

select_xcode() {
  if [ ! -d "$XCODE_APP" ]; then
    echo "Pinned Xcode not found: $XCODE_APP" >&2
    ls -d /Applications/Xcode*.app >&2 || true
    exit 2
  fi
  sudo xcode-select -s "$XCODE_APP/Contents/Developer"
}

capture_env() {
  local candidate="$1"
  {
    echo "candidate=$candidate"
    echo "image_os=${ImageOS:-unknown} image_version=${ImageVersion:-unknown} runner_os=${RUNNER_OS:-unknown} runner_arch=${RUNNER_ARCH:-unknown}"
    echo "xcode_app=$XCODE_APP sim_device_type=$SIM_DEVICE_TYPE sim_runtime=$SIM_RUNTIME"
    sw_vers
    uname -m
    xcodebuild -version
    echo "iphonesimulator_sdk=$(xcrun --sdk iphonesimulator --show-sdk-version)"
    echo "iphoneos_sdk=$(xcrun --sdk iphoneos --show-sdk-version)"
    echo "node=$(node --version 2>/dev/null || echo absent)"
    echo "npm=$(npm --version 2>/dev/null || echo absent)"
    echo "ruby=$(ruby --version 2>/dev/null || echo absent)"
    echo "cocoapods=$(pod --version 2>/dev/null || echo absent)"
    echo "git=$(git --version)"
  } > "$EVIDENCE_DIR/$candidate-environment.txt" 2>&1
  xcrun simctl list runtimes -j > "$EVIDENCE_DIR/$candidate-simulator-runtimes.json"
  xcrun simctl list devicetypes -j > "$EVIDENCE_DIR/$candidate-simulator-devicetypes.json"
}

create_simulator() {
  local name="$1" udid
  python3 - "$EVIDENCE_DIR" "$SIM_RUNTIME" "$SIM_DEVICE_TYPE" <<'PY'
import glob, json, sys
evidence, runtime, devicetype = sys.argv[1], sys.argv[2], sys.argv[3]
runtimes = json.load(open(sorted(glob.glob(evidence + '/*-simulator-runtimes.json'))[-1]))['runtimes']
types = json.load(open(sorted(glob.glob(evidence + '/*-simulator-devicetypes.json'))[-1]))['devicetypes']
ok_runtime = any(r.get('identifier') == runtime and r.get('isAvailable') for r in runtimes)
ok_type = any(t.get('identifier') == devicetype for t in types)
if not (ok_runtime and ok_type):
    sys.exit('pinned simulator runtime/device type unavailable: runtime=%s type=%s' % (ok_runtime, ok_type))
PY
  udid=$(xcrun simctl create "$name" "$SIM_DEVICE_TYPE" "$SIM_RUNTIME")
  xcrun simctl boot "$udid"
  xcrun simctl bootstatus "$udid" -b > /dev/null
  echo "$udid"
}

launch_and_capture() {
  local udid="$1" app="$2" bundle="$3" candidate="$4"
  xcrun simctl install "$udid" "$app"
  xcrun simctl launch "$udid" "$bundle" | tee "$EVIDENCE_DIR/$candidate-launch.txt"
  sleep 30
  xcrun simctl io "$udid" screenshot "$EVIDENCE_DIR/$candidate-launch.png"
  xcrun simctl spawn "$udid" log show --last 5m --style compact --predicate 'eventMessage CONTAINS "G1_PROBE"' \
    > "$EVIDENCE_DIR/$candidate-probe-log.txt" || true
  xcrun simctl spawn "$udid" launchctl list > "$EVIDENCE_DIR/$candidate-launchctl.txt" || true
  if grep -q "UIKitApplication:$bundle" "$EVIDENCE_DIR/$candidate-launchctl.txt"; then
    echo "process_running=true" | tee -a "$EVIDENCE_DIR/$candidate-launch.txt"
  else
    echo "process_running=false" | tee -a "$EVIDENCE_DIR/$candidate-launch.txt"
    return 4
  fi
  if ! grep -q "event=launch" "$EVIDENCE_DIR/$candidate-probe-log.txt"; then
    echo "launch marker missing" >&2
    return 5
  fi
}

hash_tree() {
  local path="$1" name="$2"
  (cd "$(dirname "$path")" && find "$(basename "$path")" -type f -print0 | sort -z | xargs -0 shasum -a 256) \
    > "$EVIDENCE_DIR/$name-sha256.txt"
}
