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
# DIAGNOSTIC round (probe branch only): each typing variant alone on a freshly created simulator (first keyboard use),
# with the app's diagnostic G1MARK trace streamed per variant. No READY capture, no shared flow, no device build.
xcrun simctl shutdown "$UDID" || true
fetch_xcodegen
(cd "$PROBE_ROOT/ios-ci/e2e" && "$XG" generate --spec project.yml) > "$EVIDENCE_DIR/$C-e2e-xcodegen.txt" 2>&1
RC=0
for VARIANT in testDiagBurstArabic testDiagBurstEnglish testDiagPacedArabic; do
  U=$(create_simulator "G1Probe-B-$VARIANT")
  xcrun simctl install "$U" "$APP"
  xcrun simctl spawn "$U" log stream --style compact --level info --predicate 'subsystem == "com.example.g1bench"' \
    > "$EVIDENCE_DIR/$C-$VARIANT-markers.txt" 2>&1 &
  STREAM_PID=$!
  sleep 3
  TEST_RUNNER_G1_BUNDLE_ID=com.example.g1bench.candidateb TEST_RUNNER_G1_URL_SCHEME=g1bench-b \
    xcodebuild -project "$PROBE_ROOT/ios-ci/e2e/G1E2E.xcodeproj" -scheme G1E2E -destination "id=$U" \
    -derivedDataPath "$RUNNER_TEMP/e2e-dd-$C" -resultBundlePath "$EVIDENCE_DIR/$C-$VARIANT.xcresult" \
    -only-testing:"G1E2ETests/FlowTests/$VARIANT" CODE_SIGNING_ALLOWED=NO test 2>&1 | tee "$EVIDENCE_DIR/$C-$VARIANT.txt" || RC=$?
  kill "$STREAM_PID" 2>/dev/null || true
  wait "$STREAM_PID" 2>/dev/null || true
  xcrun simctl shutdown "$U" || true
done
exit "$RC"
