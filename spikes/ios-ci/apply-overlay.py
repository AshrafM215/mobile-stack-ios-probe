#!/usr/bin/env python3
# Applies a registered overlay to a derived tree - NON-PRODUCTION / SYNTHETIC DATA ONLY.
# usage: apply-overlay.py <overlay directory> <tree root> <record file>
# The overlay directory holds OVERLAY.json ({"schema": "G1-OVERLAY-1.0", "name", "files": [{"path", "sha256"}]}) and the
# files under files/<path>. Every file is checked against its digest before it is written; a path that leaves the tree
# or names the job scripts or the harness is refused; a file of the directory that the manifest does not list is
# refused. The record lists what was written and the digest of what each file replaced.
import hashlib, json, pathlib, sys

overlay_dir, tree_root, record_path = (pathlib.Path(a) for a in sys.argv[1:4])
sha256 = lambda data: hashlib.sha256(data).hexdigest()
manifest_bytes = (overlay_dir / 'OVERLAY.json').read_bytes()
manifest = json.loads(manifest_bytes.decode('utf-8'))
if manifest.get('schema') != 'G1-OVERLAY-1.0' or not isinstance(manifest.get('files'), list) or not manifest['files']:
    sys.exit('overlay manifest: schema G1-OVERLAY-1.0 with a file list is required')
listed = set()
for entry in manifest['files']:
    rel = entry['path']
    parts = pathlib.PurePosixPath(rel).parts
    if not parts or rel.startswith('/') or '\\' in rel or any(p in ('..', '.', '') for p in parts) or parts[0] in ('ios-ci', 'harness', '.git'):
        sys.exit('overlay path refused: %s' % rel)
    if rel in listed:
        sys.exit('overlay path listed twice: %s' % rel)
    listed.add(rel)
present = {p.relative_to(overlay_dir / 'files').as_posix() for p in (overlay_dir / 'files').rglob('*') if p.is_file()}
if present != listed:
    sys.exit('overlay files and manifest differ: %s' % sorted(present ^ listed)[:10])
applied = []
for entry in manifest['files']:
    data = (overlay_dir / 'files' / entry['path']).read_bytes()
    if sha256(data) != entry['sha256']:
        sys.exit('overlay file %s does not have its registered digest' % entry['path'])
    target = tree_root / entry['path']
    replaced = sha256(target.read_bytes()) if target.is_file() else None
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(data)
    applied.append({'path': entry['path'], 'sha256': entry['sha256'], 'replaced_sha256': replaced})
record_path.write_text(json.dumps({'schema': 'G1-OVERLAY-APPLIED-1.0', 'classification': 'NON-PRODUCTION / SYNTHETIC DATA ONLY',
                                   'overlay': manifest.get('name'), 'manifest_sha256': sha256(manifest_bytes), 'files': applied}, indent=1) + '\n', encoding='utf-8')
print('overlay', manifest.get('name'), 'applied:', len(applied), 'files')
