#!/usr/bin/env bash
# Entry point of one iOS job on a hosted runner - NON-PRODUCTION / SYNTHETIC DATA ONLY.
# Checks what the workflow passes on before anything is built: the job name, the resolution mode, the derived tree and
# the overlay. A derived tree (the tree an upgrade or a maintenance attempt left, checked out beside the registered
# revision) is built by the registered scripts of this directory, never by its own copy of them. An overlay is a
# registered set of files that replaces files of a derived tree before the job (the hidden oracle of a maintenance
# task); it is applied here and recorded with the digests of what it wrote and replaced.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
job="${1:-}"
case "$job" in
  native-common|candidate-a-flutter|candidate-b-react-native|candidate-c-native) ;;
  *) echo "unknown job: $job" >&2; exit 64 ;;
esac
: "${G1_RESOLUTION:=locked}"
case "$G1_RESOLUTION" in locked|update) ;; *) echo "resolution must be locked or update" >&2; exit 64 ;; esac
: "${EVIDENCE_DIR:=$PWD/evidence}"
export EVIDENCE_DIR G1_RESOLUTION
mkdir -p "$EVIDENCE_DIR"
if [ -n "${G1_TREE_REF:-}" ]; then
  tree="${GITHUB_WORKSPACE:?}/_tree/spikes"
  [ -d "$tree" ] || { echo "the derived tree is not checked out at _tree/spikes" >&2; exit 64; }
  export G1_TREE_ROOT="$tree"
fi
if [ -n "${G1_OVERLAY:-}" ]; then
  case "$G1_OVERLAY" in *[!a-z0-9-]*|'') echo "overlay name: lower-case letters, digits and hyphens" >&2; exit 64 ;; esac
  [ -n "${G1_TREE_ROOT:-}" ] || { echo "an overlay is applied to a derived tree only" >&2; exit 64; }
  overlay=""
  for candidate_dir in "$here/overlays/$G1_OVERLAY" "$here/../harness/oracle/$G1_OVERLAY/overlay"; do
    if [ -f "$candidate_dir/OVERLAY.json" ]; then overlay="$candidate_dir"; break; fi
  done
  [ -n "$overlay" ] || { echo "no registered overlay named $G1_OVERLAY" >&2; exit 64; }
  python3 "$here/apply-overlay.py" "$overlay" "$G1_TREE_ROOT" "$EVIDENCE_DIR/$job-overlay.json"
fi
exec bash "$here/probe-$job.sh"
