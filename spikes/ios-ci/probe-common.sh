#!/usr/bin/env bash
# Synthetic iOS feasibility job - NON-PRODUCTION / SYNTHETIC DATA ONLY.
# Shared helpers: stage records, pinned Xcode selection, the environment record of the runner, simulator lifecycle and
# evidence capture. A job declares its stages once (job_begin) and runs each of them through `stage`. Every stage is
# recorded with its outcome. A stage that fails does not end the job: the stages that do not need it still run, and a
# stage whose needed stages did not pass is recorded as skipped. The job exits non-zero when any stage failed or was
# skipped. The records are what a reader of the run evidence judges: a green job page alone is not evidence.
set -euo pipefail

: "${XCODE_APP:=/Applications/Xcode_26.6.app}"
: "${SIM_DEVICE_TYPE:=com.apple.CoreSimulator.SimDeviceType.iPhone-17}"
: "${SIM_RUNTIME:=com.apple.CoreSimulator.SimRuntime.iOS-26-5}"
: "${EVIDENCE_DIR:=$PWD/evidence}"
: "${RUNNER_TEMP:=${TMPDIR:-/tmp}}"
mkdir -p "$EVIDENCE_DIR"
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The tree whose candidates are built: the tree of these scripts or, for the verification of a derived tree, the tree the
# caller names (run-job.sh). The scripts, the shared UI flow and the overlays are always the ones beside this file.
PROBE_ROOT="${G1_TREE_ROOT:-$(cd "$SCRIPTS_DIR/.." && pwd)}"
# locked: every dependency resolves to the tracked lock files and a lock file that changes fails the job.
# update: resolution may write the lock files (the feedback run of an upgrade); the lock files are kept as evidence.
: "${G1_RESOLUTION:=locked}"
case "$G1_RESOLUTION" in locked|update) ;; *) echo "G1_RESOLUTION must be locked or update" >&2; exit 64 ;; esac
JOB_SCHEMA="G1-IOS-JOB-1.2"
# the Swift packages of every xcodebuild call of a job are cloned here once
SPM_DIR="$RUNNER_TEMP/g1-swift-packages"
UDID_FILE="$RUNNER_TEMP/g1-simulator-udid"

utc_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# ---------------------------------------------------------------- stage records

# job_begin <job name> <stage id>...   declares the stages of the job in their order
job_begin() {
  JOB_NAME="$1"
  shift
  JOB_PLANNED="$*"
  JOB_DONE=""
  JOB_PASSED=""
  JOB_FAILED=0
  JOB_STARTED="$(utc_now)"
  STAGES_FILE="$EVIDENCE_DIR/$JOB_NAME-stages.ndjson"
  : > "$STAGES_FILE"
  trap job_end EXIT
}

# stage <stage id> [needs:<id>,<id>...] <function or command> [args...]
# Runs the function in a subshell of its own (a failing command ends the stage, not the job) and records the outcome.
# With needs:, the stage runs only when every stage named there passed; otherwise it is recorded as skipped.
stage() {
  local id="$1" rc=0 t0 t1 needs="" n missing=""
  shift
  case "${1:-}" in needs:*) needs="${1#needs:}"; shift ;; esac
  case " $JOB_PLANNED " in *" $id "*) ;; *) echo "stage $id is not declared" >&2; exit 97 ;; esac
  case " $JOB_DONE " in *" $id "*) echo "stage $id runs twice" >&2; exit 97 ;; esac
  JOB_DONE="$JOB_DONE $id"
  for n in ${needs//,/ }; do
    case " $JOB_PASSED " in *" $n "*) ;; *) missing="$missing $n" ;; esac
  done
  if [ -n "$missing" ]; then
    printf '{"stage":"%s","status":"skipped","exit":null,"started_at_utc":null,"ended_at_utc":null,"needs":"%s","needs_not_passed":"%s"}\n' \
      "$id" "$needs" "${missing# }" >> "$STAGES_FILE"
    echo "stage $id skipped: needs${missing}" >&2
    JOB_FAILED=1
    return 0
  fi
  t0="$(utc_now)"
  echo "::group::stage $id"
  set +e
  ( set -euo pipefail; "$@" )
  rc=$?
  set -e
  echo "::endgroup::"
  t1="$(utc_now)"
  printf '{"stage":"%s","status":"%s","exit":%d,"started_at_utc":"%s","ended_at_utc":"%s","needs":"%s","needs_not_passed":""}\n' \
    "$id" "$([ "$rc" -eq 0 ] && echo passed || echo failed)" "$rc" "$t0" "$t1" "$needs" >> "$STAGES_FILE"
  if [ "$rc" -eq 0 ]; then
    JOB_PASSED="$JOB_PASSED $id"
  else
    echo "stage $id failed with exit $rc" >&2
    JOB_FAILED=1
  fi
  return 0
}

# job_finish   the last command of a job script: the exit status says whether every stage passed
job_finish() { exit "$JOB_FAILED"; }

# EXIT trap: records the stages that did not run and writes the job record (the exit status of the job is unchanged)
job_end() {
  local rc=$? id
  trap - EXIT
  for id in $JOB_PLANNED; do
    case " $JOB_DONE " in
      *" $id "*) ;;
      *) printf '{"stage":"%s","status":"not_run","exit":null,"started_at_utc":null,"ended_at_utc":null,"needs":"","needs_not_passed":""}\n' "$id" >> "$STAGES_FILE" ;;
    esac
  done
  python3 - "$EVIDENCE_DIR" "$JOB_NAME" "$JOB_SCHEMA" "$JOB_STARTED" "$(utc_now)" "$rc" "$JOB_PLANNED" <<'PY' || true
import hashlib, json, os, pathlib, sys
evidence, name, schema, started, ended, rc, planned = sys.argv[1:8]
evidence = pathlib.Path(evidence)
stages = [json.loads(line) for line in (evidence / (name + '-stages.ndjson')).read_text().splitlines() if line.strip()]
for s in stages:
    s['needs'] = [x for x in s.get('needs', '').split(',') if x]
    s['needs_not_passed'] = s.get('needs_not_passed', '').split()
files = {}
for p in sorted(evidence.rglob('*')):
    if p.is_file() and p.name != name + '-job.json' and '.xcresult' not in p.as_posix():
        files[p.relative_to(evidence).as_posix()] = hashlib.sha256(p.read_bytes()).hexdigest()
record = {
    'schema': schema, 'classification': 'NON-PRODUCTION / SYNTHETIC DATA ONLY', 'job': name,
    'started_at_utc': started, 'ended_at_utc': ended, 'exit': int(rc),
    'planned_stages': planned.split(), 'stages': stages,
    'all_stages_passed': len(stages) == len(planned.split()) and all(s['status'] == 'passed' for s in stages),
    'run': {k: os.environ.get(v) for k, v in (('repository', 'GITHUB_REPOSITORY'), ('run_id', 'GITHUB_RUN_ID'), ('run_attempt', 'GITHUB_RUN_ATTEMPT'),
                                              ('sha', 'GITHUB_SHA'), ('ref', 'GITHUB_REF'), ('workflow', 'GITHUB_WORKFLOW'), ('job', 'GITHUB_JOB'),
                                              ('event', 'GITHUB_EVENT_NAME'))},
    'evidence_files': files,
}
(evidence / (name + '-job.json')).write_text(json.dumps(record, indent=1) + '\n', encoding='utf-8')
print('job record:', name, 'exit', rc, ' '.join('%s=%s' % (s['stage'], s['status']) for s in stages))
PY
  exit "$rc"
}

# ---------------------------------------------------------------- environment

select_xcode() {
  if [ ! -d "$XCODE_APP" ]; then
    echo "Pinned Xcode not found: $XCODE_APP" >&2
    ls -d /Applications/Xcode*.app >&2 || true
    exit 2
  fi
  sudo xcode-select -s "$XCODE_APP/Contents/Developer"
}

# The environment record of the runner. Pseudonymous: image, OS, hardware class, pinned Xcode, SDK and simulator runtime
# with the digests of their identifying files, and the preinstalled tools. No host name, user name, address, serial
# number or device identifier is read or kept.
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
  python3 - "$EVIDENCE_DIR" "$candidate" "$XCODE_APP" "$SIM_DEVICE_TYPE" "$SIM_RUNTIME" "$SCRIPTS_DIR" "$PROBE_ROOT" <<'PY'
import hashlib, json, os, pathlib, subprocess, sys
evidence, candidate, xcode_app, device_type, runtime_id, scripts_dir, tree_root = sys.argv[1:8]
evidence = pathlib.Path(evidence)
root = pathlib.Path(scripts_dir).parent

def out(*argv):
    try:
        p = subprocess.run(list(argv), capture_output=True, text=True)
    except OSError:
        return None
    return p.stdout.strip() if p.returncode == 0 else None

def sha(path):
    try:
        return hashlib.sha256(pathlib.Path(path).read_bytes()).hexdigest()
    except OSError:
        return None

def sysctl(name):
    return out('sysctl', '-n', name)

def number(text):
    try:
        return int(text)
    except (TypeError, ValueError):
        return None

runtimes = json.loads((evidence / (candidate + '-simulator-runtimes.json')).read_text())['runtimes']
runtime = next((r for r in runtimes if r.get('identifier') == runtime_id), None)
# graphics model names only (the profiler's other fields are not kept)
try:
    displays = json.loads(out('system_profiler', 'SPDisplaysDataType', '-json') or '{}').get('SPDisplaysDataType', [])
except ValueError:
    displays = []
xcodebuild = (out('xcodebuild', '-version') or '').splitlines()
sdk_path = out('xcrun', '--sdk', 'iphoneos', '--show-sdk-path')
scripts = []
for p in sorted(pathlib.Path(root, 'ios-ci').rglob('*')):
    if p.is_file():
        scripts.append('%s %s' % (p.relative_to(root).as_posix(), hashlib.sha256(p.read_bytes()).hexdigest()))
first = lambda text: text.splitlines()[0].strip() if text else None
# the workflow file of the run (GITHUB_WORKFLOW_REF: <repository>/<path>@<ref>), read from the checkout of the run
repository = os.environ.get('GITHUB_REPOSITORY') or ''
workflow_ref = (os.environ.get('GITHUB_WORKFLOW_REF') or '').split('@')[0]
workflow_path = workflow_ref[len(repository) + 1:] if repository and workflow_ref.startswith(repository + '/') else None
workspace = os.environ.get('GITHUB_WORKSPACE')
derived = os.path.realpath(tree_root) != os.path.realpath(root)
record = {
    'schema': 'G1-IOS-ENVIRONMENT-1.1', 'classification': 'NON-PRODUCTION / SYNTHETIC DATA ONLY', 'job': candidate,
    'workflow': {'path': workflow_path, 'sha256': sha(pathlib.Path(workspace, workflow_path)) if workspace and workflow_path else None},
    'inputs': {'tree_ref': os.environ.get('G1_TREE_REF') or None, 'resolution': os.environ.get('G1_RESOLUTION') or 'locked',
               'overlay': os.environ.get('G1_OVERLAY') or None, 'purpose': os.environ.get('G1_PURPOSE') or None},
    'tree': {'derived': derived, 'commit': out('git', '-C', tree_root, 'rev-parse', 'HEAD')},
    'runner': {'image_os': os.environ.get('ImageOS'), 'image_version': os.environ.get('ImageVersion'), 'runner_os': os.environ.get('RUNNER_OS'),
               'runner_arch': os.environ.get('RUNNER_ARCH'), 'runner_environment': os.environ.get('RUNNER_ENVIRONMENT')},
    'os': {'product_name': out('sw_vers', '-productName'), 'product_version': out('sw_vers', '-productVersion'),
           'build_version': out('sw_vers', '-buildVersion'), 'architecture': out('uname', '-m')},
    'hardware': {'model': sysctl('hw.model'), 'cpu_brand': sysctl('machdep.cpu.brand_string'),
                 'physical_cpu': number(sysctl('hw.physicalcpu')), 'logical_cpu': number(sysctl('hw.logicalcpu')),
                 'memory_bytes': number(sysctl('hw.memsize')), 'virtual_machine': sysctl('kern.hv_vmm_present') == '1',
                 'gpu': sorted(str(d.get('sppci_model') or d.get('_name')) for d in displays)},
    'xcode': {'application': pathlib.Path(xcode_app).name, 'version': xcodebuild[0] if xcodebuild else None,
              'build': xcodebuild[1].replace('Build version', '').strip() if len(xcodebuild) > 1 else None,
              'version_plist_sha256': sha(pathlib.Path(xcode_app, 'Contents', 'version.plist')),
              'iphoneos_sdk': out('xcrun', '--sdk', 'iphoneos', '--show-sdk-version'),
              'iphonesimulator_sdk': out('xcrun', '--sdk', 'iphonesimulator', '--show-sdk-version'),
              'arkit_tbd_sha256': sha(pathlib.Path(sdk_path, 'System/Library/Frameworks/ARKit.framework/ARKit.tbd')) if sdk_path else None},
    'simulator': {'device_type': device_type, 'runtime': runtime_id, 'runtime_version': runtime.get('version') if runtime else None,
                  'runtime_build': runtime.get('buildversion') if runtime else None, 'runtime_available': bool(runtime and runtime.get('isAvailable')),
                  'system_version_plist_sha256': sha(pathlib.Path(runtime['runtimeRoot'], 'System/Library/CoreServices/SystemVersion.plist')) if runtime and runtime.get('runtimeRoot') else None},
    'tools': {'node': out('node', '--version'), 'npm': out('npm', '--version'), 'ruby': first(out('ruby', '--version')), 'cocoapods': out('pod', '--version'),
              'git': out('git', '--version'), 'python3': out('python3', '--version')},
    'job_scripts': {'files': len(scripts), 'sha256': hashlib.sha256(('\n'.join(scripts) + '\n').encode()).hexdigest()},
}
(evidence / (candidate + '-environment.json')).write_text(json.dumps(record, indent=1) + '\n', encoding='utf-8')
PY
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

# The simulator of the job: created and booted once (environment stage); later stages read its identifier.
prepare_simulator() { create_simulator "$1" > "$UDID_FILE"; }
sim_udid() { cat "$UDID_FILE"; }

# ---------------------------------------------------------------- launch

# Full candidate apps: install, start a live unified-log stream (subsystem com.example.g1bench), launch with the app's
# standard output/error captured (lab builds write every G1MARK line to standard error as well), wait for the READY
# marker (name=app.ready) in either capture, then record a screenshot, the markers from every source and, when READY is
# missing, the process log for diagnosis. The stage passes only when the markers of the common ready state appear in
# their order: app.start, bundle.loaded with state VALID, map.style.loaded, app.ready.
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
  local source="$EVIDENCE_DIR/$candidate-app-stderr.txt"
  [ "$found" = stderr ] || source="$EVIDENCE_DIR/$candidate-markers-stream.txt"
  grep -ho "G1MARK v=1 .*" "$source" | sed -E 's/ t=[0-9]+ rt=[^ ]+//' > "$EVIDENCE_DIR/$candidate-markers-normalized.txt" || true
  python3 - "$EVIDENCE_DIR/$candidate-markers-normalized.txt" "$EVIDENCE_DIR/$candidate-ready-sequence.json" <<'PY'
import json, re, sys
lines = [l.strip() for l in open(sys.argv[1], encoding='utf-8', errors='replace') if 'G1MARK v=1' in l]
want = [('app.start', None), ('bundle.loaded', 'state=VALID'), ('map.style.loaded', None), ('app.ready', None)]
found, at = [], 0
for name, field in want:
    hit = next((i for i in range(at, len(lines)) if re.search(r'(^| )name=%s( |$)' % re.escape(name), lines[i]) and (field is None or (' ' + field) in lines[i])), None)
    found.append({'marker': name, 'field': field, 'line': None if hit is None else hit + 1})
    if hit is None:
        break
    at = hit + 1
ok = len(found) == len(want) and all(f['line'] is not None for f in found)
json.dump({'schema': 'G1-IOS-READY-SEQUENCE-1.0', 'markers': len(lines), 'sequence': found, 'in_order': ok}, open(sys.argv[2], 'w'), indent=1)
print('ready sequence in order:', ok)
sys.exit(0 if ok else 7)
PY
}

XCODEGEN_URL=https://github.com/yonaskolb/XcodeGen/releases/download/2.46.0/xcodegen.zip
XCODEGEN_SHA256=4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806

# Pinned XcodeGen (checksum verified). The binary is at $XCODEGEN_BIN afterwards; calling it again is harmless.
XCODEGEN_BIN="$RUNNER_TEMP/xcodegen/xcodegen/bin/xcodegen"
fetch_xcodegen() {
  if [ -x "$XCODEGEN_BIN" ]; then return; fi
  curl -fsSL --retry 3 -o "$RUNNER_TEMP/xcodegen.zip" "$XCODEGEN_URL"
  echo "$XCODEGEN_SHA256  $RUNNER_TEMP/xcodegen.zip" | shasum -a 256 -c -
  rm -rf "$RUNNER_TEMP/xcodegen"
  unzip -q "$RUNNER_TEMP/xcodegen.zip" -d "$RUNNER_TEMP/xcodegen"
  "$XCODEGEN_BIN" --version > "$EVIDENCE_DIR/xcodegen-version.txt"
}

# The tests of a result bundle as JSON (names and results): the case-level record of an Xcode test run. A bundle whose
# tests cannot be exported fails the stage that asked for it.
export_test_results() {
  local bundle="$1" name="$2"
  xcrun xcresulttool get test-results tests --path "$bundle" > "$EVIDENCE_DIR/$name-test-results.json" 2> "$EVIDENCE_DIR/$name-test-results.err.txt"
  xcrun xcresulttool get test-results summary --path "$bundle" > "$EVIDENCE_DIR/$name-test-summary.json" 2>> "$EVIDENCE_DIR/$name-test-results.err.txt"
}

# Shared end-to-end UI flow (ios-ci/e2e) against the installed candidate app; the injected QR image is placed in the app's
# lab import folder first (lab hook qr.inject through the candidate's URL scheme). The G1MARK markers of the test session
# are streamed to the evidence folder and the test attachments (screenshots) are exported from the result bundle.
run_e2e() {
  local udid="$1" bundle="$2" scheme="$3" candidate="$4" data stream_pid rc=0
  fetch_xcodegen
  # The READY instance (launched with captured output) is ended first: every test then launches a fresh process instead
  # of terminating a running one (the first test's launch, which had to terminate it, timed out once in a development run).
  xcrun simctl terminate "$udid" "$bundle" > /dev/null 2>&1 || true
  sleep 2
  data=$(xcrun simctl get_app_container "$udid" "$bundle" data)
  mkdir -p "$data/Documents/g1/import"
  cp "$PROBE_ROOT/synthetic-data/out/qr/A01.png" "$data/Documents/g1/import/A01.png"
  (cd "$SCRIPTS_DIR/e2e" && "$XCODEGEN_BIN" generate --spec project.yml) > "$EVIDENCE_DIR/$candidate-e2e-xcodegen.txt" 2>&1
  xcrun simctl spawn "$udid" log stream --style compact --level info --predicate 'subsystem == "com.example.g1bench"' \
    > "$EVIDENCE_DIR/$candidate-e2e-markers.txt" 2>&1 &
  stream_pid=$!
  sleep 3
  TEST_RUNNER_G1_BUNDLE_ID="$bundle" TEST_RUNNER_G1_URL_SCHEME="$scheme" \
    xcodebuild -project "$SCRIPTS_DIR/e2e/G1E2E.xcodeproj" -scheme G1E2E -destination "id=$udid" \
    -derivedDataPath "$RUNNER_TEMP/e2e-dd-$candidate" -resultBundlePath "$EVIDENCE_DIR/$candidate-e2e.xcresult" \
    CODE_SIGNING_ALLOWED=NO test 2>&1 | tee "$EVIDENCE_DIR/$candidate-e2e.txt" || rc=$?
  kill "$stream_pid" 2>/dev/null || true
  wait "$stream_pid" 2>/dev/null || true
  xcrun xcresulttool export attachments --path "$EVIDENCE_DIR/$candidate-e2e.xcresult" \
    --output-path "$EVIDENCE_DIR/$candidate-e2e-attachments" > "$EVIDENCE_DIR/$candidate-e2e-attachments.txt" 2>&1 || true
  export_test_results "$EVIDENCE_DIR/$candidate-e2e.xcresult" "$candidate-e2e"
  return "$rc"
}

# ---------------------------------------------------------------- build records

# Xcode loads the configured project and lists the scheme of the app: the record that the project is configured.
list_schemes() {
  local name="$1" scheme="$2"
  shift 2
  xcodebuild -list "$@" 2>&1 | tee "$EVIDENCE_DIR/$name-xcode-list.txt"
  awk -v scheme="$scheme" '/Schemes:/ { inside = 1; next } inside && $1 == scheme { found = 1 } END { exit found ? 0 : 1 }' \
    "$EVIDENCE_DIR/$name-xcode-list.txt"
}

# Linkage record of a built app: the dynamic libraries of its executable, of every dynamic library beside it (a debug
# build keeps the app's own code in <name>.debug.dylib and leaves a small launcher as the executable) and of every
# embedded framework and library. Records whether the two native dependencies the job is about are linked: the map
# engine (MapLibre) and ARKit. A build that does not link both fails here.
capture_linkage() {
  local app="$1" name="$2" exe f b
  exe=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Info.plist")
  {
    echo "== executable $exe"
    xcrun otool -L "$app/$exe"
    for f in "$app"/*.dylib "$app"/Frameworks/*.dylib; do
      [ -f "$f" ] || continue
      echo "== library ${f#"$app"/}"
      xcrun otool -L "$f"
    done
    for f in "$app"/Frameworks/*.framework; do
      [ -d "$f" ] || continue
      b=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$f/Info.plist" 2>/dev/null || basename "$f" .framework)
      echo "== framework $(basename "$f")"
      xcrun otool -L "$f/$b"
    done
  } > "$EVIDENCE_DIR/$name-linkage.txt" 2>&1
  local maplibre arkit
  maplibre=$(grep -ci 'maplibre' "$EVIDENCE_DIR/$name-linkage.txt" || true)
  arkit=$(grep -c 'ARKit.framework' "$EVIDENCE_DIR/$name-linkage.txt" || true)
  {
    echo "maplibre_lines=$maplibre"
    echo "arkit_lines=$arkit"
  } | tee "$EVIDENCE_DIR/$name-linkage-summary.txt"
  printf '{"schema":"G1-IOS-LINKAGE-1.0","app":"%s","maplibre_lines":%d,"arkit_lines":%d,"maplibre_linked":%s,"arkit_linked":%s}\n' \
    "$name" "$maplibre" "$arkit" "$([ "$maplibre" -gt 0 ] && echo true || echo false)" "$([ "$arkit" -gt 0 ] && echo true || echo false)" \
    > "$EVIDENCE_DIR/$name-linkage.json"
  [ "$maplibre" -gt 0 ] && [ "$arkit" -gt 0 ]
}

hash_tree() {
  local path="$1" name="$2"
  [ -d "$path" ] || { echo "app bundle missing: $path" >&2; return 4; }
  (cd "$(dirname "$path")" && find "$(basename "$path")" -type f -print0 | sort -z | xargs -0 shasum -a 256) \
    > "$EVIDENCE_DIR/$name-sha256.txt"
}

# Lock check: every lock file named is tracked and unchanged after resolution and the builds, and no other lock file of
# the package managers of the job exists in the tree untracked or changed. Paths are relative to the tree root. The
# named files are copied into the evidence as they are after the job. In update mode (G1_RESOLUTION=update) the same
# facts are recorded and the copies are the lock files that the resolution wrote; a changed file does not fail the stage.
lock_check() {
  local name="$1" f rc=0 stray
  shift
  echo "resolution=$G1_RESOLUTION" > "$EVIDENCE_DIR/$name-lock-check.txt"
  for f in "$@"; do
    if ! git -C "$PROBE_ROOT" ls-files --error-unmatch -- "$f" > /dev/null 2>&1; then
      echo "untracked $f" | tee -a "$EVIDENCE_DIR/$name-lock-check.txt"
      rc=5
    elif [ -n "$(git -C "$PROBE_ROOT" status --porcelain -- "$f")" ]; then
      echo "changed $f" | tee -a "$EVIDENCE_DIR/$name-lock-check.txt"
      git -C "$PROBE_ROOT" diff -- "$f" > "$EVIDENCE_DIR/$name-lockfile-diff-$(echo "$f" | tr '/' '_').txt" 2>&1 || true
      rc=5
    else
      echo "unchanged $f $(shasum -a 256 "$PROBE_ROOT/$f" | cut -d' ' -f1)" | tee -a "$EVIDENCE_DIR/$name-lock-check.txt"
    fi
    cp "$PROBE_ROOT/$f" "$EVIDENCE_DIR/$name-lockfile-$(echo "$f" | tr '/' '_').copy" 2>/dev/null || true
  done
  stray=$(git -C "$PROBE_ROOT" status --porcelain --untracked-files=all -- . \
    | grep -E '(Package\.resolved|Podfile\.lock|pubspec\.lock|package-lock\.json)$' || true)
  if [ -n "$stray" ]; then
    echo "$stray" | sed 's/^/other-lock-file /' | tee -a "$EVIDENCE_DIR/$name-lock-check.txt"
    # the files are kept as they are, so that a lock file a tool writes can be compared and tracked
    local top line path
    top=$(git -C "$PROBE_ROOT" rev-parse --show-toplevel)
    while IFS= read -r line; do
      path="${line:3}"
      cp "$top/$path" "$EVIDENCE_DIR/$name-lockfile-other-$(echo "$path" | tr '/' '_').copy" 2>/dev/null || true
    done <<< "$stray"
    rc=5
  fi
  if [ "$G1_RESOLUTION" = update ]; then return 0; fi
  return "$rc"
}

# ---------------------------------------------------------------- tree preparation and inventories

# Dataset regeneration check and asset placement of the tree that is built (the scripts are the ones beside this file).
prepare_data() { G1_TREE_ROOT="$PROBE_ROOT" bash "$SCRIPTS_DIR/prepare-data.sh"; }

# Static record of a built app for the inspection of the release artifacts: Info.plist as JSON and the privacy manifests.
capture_app_metadata() {
  local app="$1" name="$2"
  plutil -p "$app/Info.plist" > "$EVIDENCE_DIR/$name-info-plist.txt"
  # the JSON form exists when every value of the file has a JSON form (no date or data value)
  plutil -convert json -r -o "$EVIDENCE_DIR/$name-info-plist.json" "$app/Info.plist" 2> /dev/null || rm -f "$EVIDENCE_DIR/$name-info-plist.json"
  (cd "$app" && find . -name 'PrivacyInfo.xcprivacy' -type f | sort) > "$EVIDENCE_DIR/$name-privacy-manifests.txt"
  # the privacy manifests as data: path inside the bundle -> manifest (a date or data value is kept as text)
  python3 - "$app" "$EVIDENCE_DIR/$name-privacy-manifests.json" <<'PY'
import json, pathlib, plistlib, sys
app, out = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
manifests = {}
for f in sorted(app.rglob('PrivacyInfo.xcprivacy')):
    if f.is_file():
        try:
            manifests[f.relative_to(app).as_posix()] = plistlib.loads(f.read_bytes())
        except Exception as error:
            manifests[f.relative_to(app).as_posix()] = {'unreadable': str(error)}
out.write_text(json.dumps({'schema': 'G1-IOS-PRIVACY-MANIFESTS-1.0', 'manifests': manifests}, indent=1, sort_keys=True, default=str) + '\n', encoding='utf-8')
PY
  # static secret scan of the bundle (patterns and the private halves of the lab keys); hits are recorded, never printed
  node "$SCRIPTS_DIR/secret-scan.mjs" "$app" --out "$EVIDENCE_DIR/$name-secret-scan.json"
}

# Dependency inventory of the iOS path: the Swift packages that were checked out (revision, the binary targets their
# manifest declares with the checksums the package manager verifies, licence files), the binary frameworks the package
# manager and CocoaPods installed (by the digest of their trees) and the acknowledgement list CocoaPods generated. Arguments:
# <name> <directory to search for SourcePackages/checkouts>... ; the job's own package directory is always searched.
# PODS_DIR names the Pods directory of a CocoaPods installation. A job that names the map engine as a Swift package or a
# pod and finds neither has not inventoried its dependencies: the stage fails.
capture_dependencies() {
  local name="$1"
  shift
  python3 - "$EVIDENCE_DIR" "$name" "${PODS_DIR:-}" "$SPM_DIR" "$@" <<'PY'
import hashlib, json, os, pathlib, plistlib, re, subprocess, sys
evidence, name, pods_dir = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
roots = [pathlib.Path(a) for a in sys.argv[4:]]
checkouts = {}
for root in roots:
    if not root.is_dir():
        continue
    # the package directory itself, or SourcePackages/checkouts at most four levels below (Xcode's derived data layout)
    found = [root / 'checkouts'] if (root / 'checkouts').is_dir() else [p for pattern in ('SourcePackages/checkouts', '*/SourcePackages/checkouts',
        '*/*/SourcePackages/checkouts', '*/*/*/SourcePackages/checkouts') for p in root.glob(pattern) if p.is_dir()]
    for directory in found:
        for package in sorted(p for p in directory.iterdir() if p.is_dir()):
            checkouts.setdefault(package.name, package)
packages = []
for pkg, directory in sorted(checkouts.items()):
    licences = []
    for f in sorted(directory.iterdir()):
        if f.is_file() and f.name.upper().split('.')[0] in ('LICENSE', 'LICENCE', 'COPYING', 'NOTICE'):
            data = f.read_bytes()
            target = evidence / 'licenses' / 'swift-packages' / pkg / f.name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
            licences.append({'file': f.name, 'sha256': hashlib.sha256(data).hexdigest(), 'bytes': len(data)})
    # the revision that was checked out and the binary targets the manifest of that revision declares (a binary target
    # is fetched by URL and checked by the package manager against this checksum, the SHA-256 of the archive)
    head = subprocess.run(['git', '-C', str(directory), 'rev-parse', 'HEAD'], capture_output=True, text=True)
    manifest = directory / 'Package.swift'
    binaries = []
    if manifest.is_file():
        for m in re.finditer(r'\.binaryTarget\(\s*name:\s*"([^"]+)"\s*,\s*url:\s*"([^"]+)"\s*,\s*checksum:\s*"([0-9a-fA-F]{64})"', manifest.read_text(encoding='utf-8', errors='replace')):
            binaries.append({'name': m.group(1), 'url': m.group(2), 'checksum_sha256': m.group(3).lower()})
    packages.append({'package': pkg, 'revision': head.stdout.strip() if head.returncode == 0 else None, 'binary_targets': binaries, 'licence_files': licences})

def tree_digest(directory):
    # SHA-256 over the sorted lines "<SHA-256 of the file>  <path>" of every file; a symbolic link is the line "link:<target>  <path>"
    lines, size = [], 0
    for f in sorted(directory.rglob('*')):
        rel = f.relative_to(directory).as_posix()
        if f.is_symlink():
            lines.append('link:%s  %s' % (os.readlink(f), rel))
        elif f.is_file():
            data = f.read_bytes()
            size += len(data)
            lines.append('%s  %s' % (hashlib.sha256(data).hexdigest(), rel))
    lines.sort()
    return {'entries': len(lines), 'bytes': size, 'tree_sha256': hashlib.sha256(('\n'.join(lines) + '\n').encode()).hexdigest()}

def frameworks(root):
    # every binary framework bundle below root, outermost only (an xcframework holds the frameworks of its slices)
    found = []
    for current, dirs, _ in os.walk(root):
        for d in sorted(dirs):
            if d.endswith('.xcframework'):
                found.append(pathlib.Path(current, d))
        dirs[:] = sorted(d for d in dirs if not d.endswith('.xcframework'))
    return [{'path': f.relative_to(root).as_posix(), **tree_digest(f)} for f in sorted(found)]

swift_binaries = []
for root in roots:
    for artifacts in ([root / 'artifacts'] if (root / 'artifacts').is_dir() else [p for pattern in ('SourcePackages/artifacts', '*/SourcePackages/artifacts',
            '*/*/SourcePackages/artifacts', '*/*/*/SourcePackages/artifacts') for p in root.glob(pattern) if p.is_dir()]):
        for entry in frameworks(artifacts):
            if not any(e['path'] == entry['path'] for e in swift_binaries):
                swift_binaries.append(entry)
swift_binaries.sort(key=lambda e: e['path'])
pods = None
if pods_dir:
    pods = []
    for plist in sorted(pathlib.Path(pods_dir).glob('Target Support Files/Pods-*/Pods-*-acknowledgements.plist')):
        data = plist.read_bytes()
        target = evidence / 'licenses' / 'cocoapods' / plist.name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        entries = [e for e in plistlib.loads(data).get('PreferenceSpecifiers', []) if e.get('License') or e.get('FooterText')]
        pods.append({'file': plist.name, 'sha256': hashlib.sha256(data).hexdigest(), 'bytes': len(data),
                     'pods': [{'pod': e.get('Title'), 'licence': e.get('License')} for e in entries if e.get('Title') and e.get('Title') != 'Acknowledgements']})
pod_binaries = frameworks(pathlib.Path(pods_dir)) if pods_dir else None
record = {'schema': 'G1-IOS-DEPENDENCIES-1.1', 'job': name, 'swift_packages': packages, 'swift_binary_artifacts': swift_binaries,
          'cocoapods_acknowledgements': pods, 'cocoapods_binary_frameworks': pod_binaries,
          'tree_digest_rule': 'SHA-256 over the sorted lines "<SHA-256 of the file>  <path>" of every file of the bundle; a symbolic link is the line "link:<target>  <path>"'}
(evidence / (name + '-dependencies.json')).write_text(json.dumps(record, indent=1) + '\n', encoding='utf-8')
names = [p['package'].lower() for p in packages] + [e['pod'].lower() for a in (pods or []) for e in a['pods']]
print('dependencies:', ' '.join(sorted(names)) or 'none')
if not any('maplibre' in n for n in names):
    sys.exit('the map engine is in neither the Swift packages nor the pods that were found: the inventory is incomplete')
PY
}
