#!/usr/bin/env bash
# Candidate C (native Swift/SwiftUI) iOS feasibility - NON-PRODUCTION / SYNTHETIC DATA ONLY.
set -euo pipefail
source "$(dirname "$0")/probe-common.sh"
C=candidate-c-native
XCODEGEN_URL=https://github.com/yonaskolb/XcodeGen/releases/download/2.46.0/xcodegen.zip
XCODEGEN_SHA256=4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806

select_xcode
capture_env "$C"
curl -fsSL --retry 3 -o "$RUNNER_TEMP/xcodegen.zip" "$XCODEGEN_URL"
echo "$XCODEGEN_SHA256  $RUNNER_TEMP/xcodegen.zip" | shasum -a 256 -c -
unzip -q "$RUNNER_TEMP/xcodegen.zip" -d "$RUNNER_TEMP/xcodegen"
XG="$RUNNER_TEMP/xcodegen/xcodegen/bin/xcodegen"
"$XG" --version | tee "$EVIDENCE_DIR/$C-xcodegen-version.txt"

cd "$C/ios"
"$XG" generate --spec project.yml 2>&1 | tee "$EVIDENCE_DIR/$C-xcodegen.txt"
UDID=$(create_simulator G1Probe-C)
xcodebuild -project G1CandidateC.xcodeproj -scheme G1CandidateC -destination "id=$UDID" -derivedDataPath build/dd \
  -resultBundlePath "$EVIDENCE_DIR/$C-tests.xcresult" CODE_SIGNING_ALLOWED=NO test 2>&1 \
  | tee "$EVIDENCE_DIR/$C-tests.txt"
xcodebuild -project G1CandidateC.xcodeproj -scheme G1CandidateC -configuration Release -sdk iphonesimulator \
  -destination "id=$UDID" -derivedDataPath build/dd CODE_SIGNING_ALLOWED=NO build 2>&1 \
  | tee "$EVIDENCE_DIR/$C-build-simulator.txt"
APP=build/dd/Build/Products/Release-iphonesimulator/G1CandidateC.app
hash_tree "$APP" "$C-simulator-app"
launch_and_capture "$UDID" "$APP" com.example.g1bench.candidatec "$C"
xcodebuild -project G1CandidateC.xcodeproj -scheme G1CandidateC -configuration Release -sdk iphoneos \
  -derivedDataPath build/dd-device CODE_SIGNING_ALLOWED=NO build 2>&1 | tee "$EVIDENCE_DIR/$C-build-iphoneos-unsigned.txt"
hash_tree build/dd-device/Build/Products/Release-iphoneos/G1CandidateC.app "$C-iphoneos-unsigned-app"
find . -name Package.resolved -not -path './build/*' -exec cp {} "$EVIDENCE_DIR/$C-Package.resolved" \; || true
