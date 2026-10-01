#!/usr/bin/env bash
# Common native module (Swift package G1NativeCommon) iOS feasibility - NON-PRODUCTION / SYNTHETIC DATA ONLY.
set -euo pipefail
source "$(dirname "$0")/probe-common.sh"
N=native-common
select_xcode
capture_env "$N"
python3 -m pip install --quiet --disable-pip-version-check cryptography==46.0.7 > "$EVIDENCE_DIR/$N-pip.txt" 2>&1
bash "$(dirname "$0")/prepare-data.sh"
UDID=$(create_simulator G1Probe-N)
cd native-common/ios
xcodebuild -list 2>&1 | tee "$EVIDENCE_DIR/$N-schemes.txt"
SCHEME=G1NativeCommon
if grep -q "G1NativeCommon-Package" "$EVIDENCE_DIR/$N-schemes.txt"; then SCHEME=G1NativeCommon-Package; fi
xcodebuild -scheme "$SCHEME" -destination "id=$UDID" -derivedDataPath build/dd \
  -resultBundlePath "$EVIDENCE_DIR/$N-tests.xcresult" CODE_SIGNING_ALLOWED=NO test 2>&1 | tee "$EVIDENCE_DIR/$N-tests.txt"
xcodebuild -scheme "$SCHEME" -destination 'generic/platform=iOS' -derivedDataPath build/dd-device \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | tee "$EVIDENCE_DIR/$N-build-iphoneos.txt"
