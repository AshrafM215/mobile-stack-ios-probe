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

# Full candidate apps: install, start a live unified-log stream (subsystem com.example.g1bench), launch with the app's
# standard output/error captured (lab builds write every G1MARK line to standard error as well), wait for the READY
# marker (name=app.ready) in either capture, then record a screenshot, the markers from every source and, when READY is
# missing, the process log for diagnosis.
launch_and_wait_ready() {
  local udid="$1" app="$2" bundle="$3" candidate="$4" i found="" exe stream_pid f
  exe=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Info.plist")
  xcrun simctl install "$udid" "$app"
  xcrun simctl spawn "$udid" log stream --style compact --level info --predicate 'subsystem == "com.example.g1bench"' \
    > "$EVIDENCE_DIR/$candidate-markers-stream.txt" 2>&1 &
  stream_pid=$!
  sleep 3
  xcrun simctl launch --stdout="$EVIDENCE_DIR/$candidate-app-stdout.txt" --stderr="$EVIDENCE_DIR/$candidate-app-stderr.txt" \
    "$udid" "$bundle" | tee "$EVIDENCE_DIR/$candidate-launch.txt"
  for i in $(seq 1 60); do
    sleep 3
    if grep -q "name=app.ready" "$EVIDENCE_DIR/$candidate-app-stderr.txt" 2>/dev/null; then found=stderr; break; fi
    if grep -q "name=app.ready" "$EVIDENCE_DIR/$candidate-markers-stream.txt" 2>/dev/null; then found=log-stream; break; fi
  done
  sleep 5
  xcrun simctl io "$udid" screenshot "$EVIDENCE_DIR/$candidate-ready.png"
  kill "$stream_pid" 2>/dev/null || true
  wait "$stream_pid" 2>/dev/null || true
  xcrun simctl spawn "$udid" log show --last 10m --style compact --predicate 'subsystem == "com.example.g1bench"' \
    > "$EVIDENCE_DIR/$candidate-markers-logshow.txt" 2>&1 || true
  {
    echo "ready_source=${found:-none}"
    for f in app-stderr markers-stream markers-logshow; do
      echo "$f G1MARK_lines=$(grep -c 'G1MARK v=1' "$EVIDENCE_DIR/$candidate-$f.txt" 2>/dev/null || true)"
    done
  } | tee "$EVIDENCE_DIR/$candidate-marker-sources.txt"
  if [ -z "$found" ]; then
    xcrun simctl spawn "$udid" log show --last 15m --style compact --info --debug --predicate "process == \"$exe\"" \
      > "$EVIDENCE_DIR/$candidate-diag-process-log.txt" 2>&1 || true
    xcrun simctl spawn "$udid" launchctl list > "$EVIDENCE_DIR/$candidate-diag-launchctl.txt" 2>&1 || true
    echo "READY marker missing" >&2
    return 6
  fi
  # run-independent view of the marker sequence (native and runtime clock values removed)
  grep -ho "G1MARK v=1 .*" "$EVIDENCE_DIR/$candidate-app-stderr.txt" | sed -E 's/ t=[0-9]+ rt=[^ ]+//' \
    > "$EVIDENCE_DIR/$candidate-markers-normalized.txt" || true
}

XCODEGEN_URL=https://github.com/yonaskolb/XcodeGen/releases/download/2.46.0/xcodegen.zip
XCODEGEN_SHA256=4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806
PROBE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Pinned XcodeGen (checksum verified); sets XG.
fetch_xcodegen() {
  if [ -n "${XG:-}" ] && [ -x "$XG" ]; then return; fi
  curl -fsSL --retry 3 -o "$RUNNER_TEMP/xcodegen.zip" "$XCODEGEN_URL"
  echo "$XCODEGEN_SHA256  $RUNNER_TEMP/xcodegen.zip" | shasum -a 256 -c -
  rm -rf "$RUNNER_TEMP/xcodegen"
  unzip -q "$RUNNER_TEMP/xcodegen.zip" -d "$RUNNER_TEMP/xcodegen"
  XG="$RUNNER_TEMP/xcodegen/xcodegen/bin/xcodegen"
  "$XG" --version > "$EVIDENCE_DIR/xcodegen-version.txt"
}

# Shared end-to-end UI flow (ios-ci/e2e) against the installed candidate app; the injected QR image is placed in the app's
# lab import folder first (lab hook qr.inject through the candidate's URL scheme). The G1MARK markers of the test session
# are streamed to the evidence folder and the test attachments (screenshots) are exported from the result bundle.
run_e2e() {
  local udid="$1" bundle="$2" scheme="$3" candidate="$4" data stream_pid rc=0
  fetch_xcodegen
  # The READY instance (launched with captured output) is ended first: every test then launches a fresh process instead
  # of terminating a running one (the first test's launch, which had to terminate it, timed out once in a probe round).
  xcrun simctl terminate "$udid" "$bundle" > /dev/null 2>&1 || true
  sleep 2
  data=$(xcrun simctl get_app_container "$udid" "$bundle" data)
  mkdir -p "$data/Documents/g1/import"
  cp "$PROBE_ROOT/synthetic-data/out/qr/A01.png" "$data/Documents/g1/import/A01.png"
  (cd "$PROBE_ROOT/ios-ci/e2e" && "$XG" generate --spec project.yml) > "$EVIDENCE_DIR/$candidate-e2e-xcodegen.txt" 2>&1
  xcrun simctl spawn "$udid" log stream --style compact --level info --predicate 'subsystem == "com.example.g1bench"' \
    > "$EVIDENCE_DIR/$candidate-e2e-markers.txt" 2>&1 &
  stream_pid=$!
  sleep 3
  TEST_RUNNER_G1_BUNDLE_ID="$bundle" TEST_RUNNER_G1_URL_SCHEME="$scheme" \
    xcodebuild -project "$PROBE_ROOT/ios-ci/e2e/G1E2E.xcodeproj" -scheme G1E2E -destination "id=$udid" \
    -derivedDataPath "$RUNNER_TEMP/e2e-dd-$candidate" -resultBundlePath "$EVIDENCE_DIR/$candidate-e2e.xcresult" \
    CODE_SIGNING_ALLOWED=NO test 2>&1 | tee "$EVIDENCE_DIR/$candidate-e2e.txt" || rc=$?
  kill "$stream_pid" 2>/dev/null || true
  wait "$stream_pid" 2>/dev/null || true
  xcrun xcresulttool export attachments --path "$EVIDENCE_DIR/$candidate-e2e.xcresult" \
    --output-path "$EVIDENCE_DIR/$candidate-e2e-attachments" > "$EVIDENCE_DIR/$candidate-e2e-attachments.txt" 2>&1 || true
  return "$rc"
}

# Linkage record of a built app: the dynamic libraries of its executable and of every embedded framework, and whether
# the two native dependencies the probe is about are linked: the map engine (MapLibre) and ARKit. A build that does not
# link both fails here.
capture_linkage() {
  local app="$1" name="$2" exe f b
  exe=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Info.plist")
  {
    echo "== executable $exe"
    xcrun otool -L "$app/$exe"
    for f in "$app"/Frameworks/*.framework; do
      [ -d "$f" ] || continue
      b=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$f/Info.plist" 2>/dev/null || basename "$f" .framework)
      echo "== framework $(basename "$f")"
      xcrun otool -L "$f/$b"
    done
  } > "$EVIDENCE_DIR/$name-linkage.txt" 2>&1
  {
    echo "maplibre_lines=$(grep -ci 'maplibre' "$EVIDENCE_DIR/$name-linkage.txt" || true)"
    echo "arkit_lines=$(grep -c 'ARKit.framework' "$EVIDENCE_DIR/$name-linkage.txt" || true)"
  } | tee "$EVIDENCE_DIR/$name-linkage-summary.txt"
  grep -qi 'maplibre' "$EVIDENCE_DIR/$name-linkage.txt" && grep -q 'ARKit.framework' "$EVIDENCE_DIR/$name-linkage.txt"
}

hash_tree() {
  local path="$1" name="$2"
  (cd "$(dirname "$path")" && find "$(basename "$path")" -type f -print0 | sort -z | xargs -0 shasum -a 256) \
    > "$EVIDENCE_DIR/$name-sha256.txt"
}
