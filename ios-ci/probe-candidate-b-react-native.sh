#!/usr/bin/env bash
# Candidate B (React Native 0.87.1) iOS feasibility - NON-PRODUCTION / SYNTHETIC DATA ONLY.
set -euo pipefail
source "$(dirname "$0")/probe-common.sh"
C=candidate-b-react-native

select_xcode
capture_env "$C"
cd "$C"
npm ci --no-audit --no-fund 2>&1 | tee "$EVIDENCE_DIR/$C-npm-ci.txt"
npx jest --ci 2>&1 | tee "$EVIDENCE_DIR/$C-unit-tests.txt"
(cd ios && pod install 2>&1 | tee "$EVIDENCE_DIR/$C-pod-install.txt")
UDID=$(create_simulator G1Probe-B)
xcodebuild -workspace ios/G1CandidateB.xcworkspace -scheme G1CandidateB -configuration Release -sdk iphonesimulator \
  -destination "id=$UDID" -derivedDataPath ios/build/dd CODE_SIGNING_ALLOWED=NO build 2>&1 \
  | tee "$EVIDENCE_DIR/$C-build-simulator.txt"
APP=ios/build/dd/Build/Products/Release-iphonesimulator/G1CandidateB.app
hash_tree "$APP" "$C-simulator-app"
launch_and_capture "$UDID" "$APP" com.example.g1bench.candidateb "$C"
cp ios/Podfile.lock "$EVIDENCE_DIR/$C-Podfile.lock"
find ios -name Package.resolved -not -path '*/build/*' -exec cp {} "$EVIDENCE_DIR/$C-Package.resolved" \; || true
