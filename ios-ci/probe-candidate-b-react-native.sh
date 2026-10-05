#!/usr/bin/env bash
# Candidate B (React Native 0.87.1) iOS feasibility - NON-PRODUCTION / SYNTHETIC DATA ONLY.
# Dataset regeneration check, npm ci from the lockfile, type check and unit tests, CocoaPods (RN + MapLibre + the G1
# common module), Release simulator build with the embedded JS bundle, launch to the READY marker, unsigned device build.
set -euo pipefail
source "$(dirname "$0")/probe-common.sh"
C=candidate-b-react-native

select_xcode
capture_env "$C"
bash "$(dirname "$0")/prepare-data.sh"
cd "$C"
npm ci --no-audit --no-fund 2>&1 | tee "$EVIDENCE_DIR/$C-npm-ci.txt"
npx tsc --noEmit 2>&1 | tee "$EVIDENCE_DIR/$C-typecheck.txt"
npx jest --ci 2>&1 | tee "$EVIDENCE_DIR/$C-unit-tests.txt"
(cd ios && pod install 2>&1 | tee "$EVIDENCE_DIR/$C-pod-install.txt")
UDID=$(create_simulator G1Probe-B)
xcodebuild -workspace ios/G1CandidateB.xcworkspace -scheme G1CandidateB -configuration Release -sdk iphonesimulator \
  -destination "id=$UDID" ONLY_ACTIVE_ARCH=YES -derivedDataPath ios/build/dd CODE_SIGNING_ALLOWED=NO build 2>&1 \
  | tee "$EVIDENCE_DIR/$C-build-simulator.txt"
APP=ios/build/dd/Build/Products/Release-iphonesimulator/G1CandidateB.app
hash_tree "$APP" "$C-simulator-app"
capture_linkage "$APP" "$C-simulator-app"
launch_and_wait_ready "$UDID" "$APP" com.example.g1bench.candidateb "$C"
run_e2e "$UDID" com.example.g1bench.candidateb g1bench-b "$C"
xcodebuild -workspace ios/G1CandidateB.xcworkspace -scheme G1CandidateB -configuration Release -sdk iphoneos \
  -destination 'generic/platform=iOS' -derivedDataPath ios/build/dd-device CODE_SIGNING_ALLOWED=NO build 2>&1 \
  | tee "$EVIDENCE_DIR/$C-build-iphoneos-unsigned.txt"
hash_tree ios/build/dd-device/Build/Products/Release-iphoneos/G1CandidateB.app "$C-iphoneos-unsigned-app"
capture_linkage ios/build/dd-device/Build/Products/Release-iphoneos/G1CandidateB.app "$C-iphoneos-unsigned-app"
cp ios/Podfile.lock "$EVIDENCE_DIR/$C-Podfile.lock"
find ios -name Package.resolved -not -path '*/build/*' -exec cp {} "$EVIDENCE_DIR/$C-Package.resolved" \; || true
