#!/usr/bin/env bash
# Candidate C (native Swift/SwiftUI) iOS feasibility - NON-PRODUCTION / SYNTHETIC DATA ONLY.
# Dataset regeneration check (also the common module's resources), XcodeGen project with MapLibre and the common module as
# Swift packages, unit tests on the simulator, Release simulator build, launch to the READY marker, the shared end-to-end UI
# flow, unsigned device build.
set -euo pipefail
source "$(dirname "$0")/probe-common.sh"
C=candidate-c-native

select_xcode
capture_env "$C"
bash "$(dirname "$0")/prepare-data.sh"
fetch_xcodegen
cd "$C/ios"
"$XG" generate --spec project.yml 2>&1 | tee "$EVIDENCE_DIR/$C-xcodegen.txt"
UDID=$(create_simulator G1Probe-C)
xcodebuild -project G1CandidateC.xcodeproj -scheme G1CandidateC -destination "id=$UDID" -derivedDataPath build/dd \
  -resultBundlePath "$EVIDENCE_DIR/$C-tests.xcresult" CODE_SIGNING_ALLOWED=NO test 2>&1 \
  | tee "$EVIDENCE_DIR/$C-tests.txt"
xcodebuild -project G1CandidateC.xcodeproj -scheme G1CandidateC -configuration Release -sdk iphonesimulator \
  -destination "id=$UDID" ONLY_ACTIVE_ARCH=YES -derivedDataPath build/dd CODE_SIGNING_ALLOWED=NO build 2>&1 \
  | tee "$EVIDENCE_DIR/$C-build-simulator.txt"
APP=build/dd/Build/Products/Release-iphonesimulator/G1CandidateC.app
hash_tree "$APP" "$C-simulator-app"
launch_and_wait_ready "$UDID" "$APP" com.example.g1bench.candidatec "$C"
run_e2e "$UDID" com.example.g1bench.candidatec g1bench-c "$C"
xcodebuild -project G1CandidateC.xcodeproj -scheme G1CandidateC -configuration Release -sdk iphoneos \
  -destination 'generic/platform=iOS' -derivedDataPath build/dd-device CODE_SIGNING_ALLOWED=NO build 2>&1 \
  | tee "$EVIDENCE_DIR/$C-build-iphoneos-unsigned.txt"
hash_tree build/dd-device/Build/Products/Release-iphoneos/G1CandidateC.app "$C-iphoneos-unsigned-app"
find . -name Package.resolved -not -path './build/*' -exec cp {} "$EVIDENCE_DIR/$C-Package.resolved" \; || true
