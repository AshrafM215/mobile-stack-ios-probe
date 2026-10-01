#!/usr/bin/env bash
# G1 iOS CI - NON-PRODUCTION / SYNTHETIC DATA ONLY.
# Copies the embedded synthetic bundle and the lab trust store into the G1NativeCommon resource folder after checking
# their SHA-256 against synthetic-data/out/GENERATION_RECORD.json (same rule as the Android G1AssetsTask).
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
out="$here/synthetic-data/out"
dest="$here/native-common/ios/Sources/G1NativeCommon/Resources/g1"
mkdir -p "$dest"
python3 - "$out" "$dest" <<'PY'
import hashlib, json, pathlib, shutil, sys
out, dest = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
record = {o["path"]: o["sha256"] for o in json.loads((out / "GENERATION_RECORD.json").read_text(encoding="utf-8"))["outputs"]}
for rel, name in (("bundle/G1SYN-1.0.0.zip", "G1SYN-1.0.0.zip"), ("app/trust_store.json", "trust_store.json")):
    data = (out / rel).read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    if digest != record.get(rel):
        sys.exit("G1 asset %s does not match GENERATION_RECORD.json" % rel)
    (dest / name).write_bytes(data)
    print("asset", name, digest)
PY
