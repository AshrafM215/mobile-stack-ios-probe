"""Independent checker for the G1 synthetic dataset - NON-PRODUCTION / SYNTHETIC DATA ONLY.

Re-derives every oracle with independent algorithms in another language (Python): search contract G1-SEARCH-1.0,
routes by exhaustive simple-path enumeration on the pruned relevant component (G1-ROUTE-1.0), QR identities
(G1-QR-1.0), trust fixtures (G1-TRUST-1.0), graph invariants, schedule rules and glyph coverage.
Usage: python verify.py <generated-out-dir>   (requires the 'cryptography' package; optional 'zxingcpp' + Pillow)
"""
import hashlib
import io
import json
import re
import sys
import unicodedata
import zipfile
from base64 import urlsafe_b64decode
from datetime import datetime, timedelta, timezone

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
from cryptography.exceptions import InvalidSignature

FAILS = []


def check(cond, msg):
    if not cond:
        FAILS.append(msg)
    return cond


def b64u(s):
    return urlsafe_b64decode(s + '=' * (-len(s) % 4))


def sha(b):
    return hashlib.sha256(b).hexdigest()


def doc_json(doc):
    """Same line-oriented JSON layout as the generator (documentJson)."""
    parts = []
    keys = list(doc.keys())
    for i, k in enumerate(keys):
        v = doc[k]
        sep = '' if i == len(keys) - 1 else ','
        if isinstance(v, list) and v:
            lines = [json.dumps(x, ensure_ascii=False, separators=(',', ':')) + ('' if j == len(v) - 1 else ',') for j, x in enumerate(v)]
            parts.append(json.dumps(k) + ':[\n' + '\n'.join(lines) + '\n]' + sep)
        else:
            parts.append(json.dumps(k) + ':' + json.dumps(v, ensure_ascii=False, separators=(',', ':')) + sep)
    return ('{\n' + '\n'.join(parts) + '\n}\n').encode('utf-8')


# ---------------- search contract (independent implementation) ----------------
REMOVE = set([0x0640, 0x0670, 0x061C, 0xFEFF] + list(range(0x064B, 0x0660)) + list(range(0x200B, 0x2010)) +
             list(range(0x202A, 0x202F)) + list(range(0x2060, 0x206A)))
SEPS = set(list(range(0x09, 0x0E)) + [0x20, 0x85, 0xA0, 0x1680] + list(range(0x2000, 0x200B)) +
           [0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0x2D] + list(range(0x2010, 0x2016)) + [0x2212])


def normalize(s):
    s = unicodedata.normalize('NFKC', s)
    out = []
    for ch in s:
        o = ord(ch)
        if 0x0660 <= o <= 0x0669:
            out.append(chr(48 + o - 0x0660))
        elif 0x06F0 <= o <= 0x06F9:
            out.append(chr(48 + o - 0x06F0))
        elif o in REMOVE:
            continue
        elif 65 <= o <= 90:
            out.append(chr(o + 32))
        else:
            out.append(ch)
    return ''.join(out)


def tokens(s):
    toks, cur = [], []
    for ch in normalize(s):
        if ord(ch) in SEPS:
            if cur:
                toks.append(''.join(cur))
                cur = []
        else:
            cur.append(ch)
    if cur:
        toks.append(''.join(cur))
    return toks


def code_key(s):
    return ''.join(tokens(s)).translate({c: c - 32 for c in range(97, 123)})


def search(q, index):
    t = tokens(q)
    if not t:
        return {'outcome': 'NO_MATCH', 'ids': []}
    k = code_key(q)
    if re.fullmatch(r'SB[0-9]+F[0-9]+R[0-9]+', k):
        ids = sorted(e['id'] for e in index if e['key'] == k)
    else:
        ids = sorted(e['id'] for e in index if all(x in e['tokens'] for x in t))
    if not ids:
        return {'outcome': 'NO_MATCH', 'ids': []}
    return {'outcome': 'UNIQUE_MATCH' if len(ids) == 1 else 'AMBIGUOUS', 'ids': ids}


# ---------------- routes by exhaustive enumeration ----------------
def route_enum(adj, origin, target, step_free, blocked):
    def usable(e):
        return e['edge'] not in blocked and (not step_free or e['step_free'])
    # component of origin under the constraints
    seen, stack = {origin}, [origin]
    while stack:
        u = stack.pop()
        for e in adj[u]:
            if usable(e) and e['to'] not in seen:
                seen.add(e['to'])
                stack.append(e['to'])
    if target not in seen:
        return None
    # prune degree-1 nodes (other than origin/target) repeatedly
    nbr = {u: {e['to']: e for e in adj[u] if usable(e) and e['to'] in seen} for u in seen}
    changed = True
    while changed:
        changed = False
        for u in list(nbr):
            if u in (origin, target) or len(nbr[u]) > 1:
                continue
            for v in list(nbr[u]):
                del nbr[v][u]
            del nbr[u]
            changed = True
    best = []
    path = [origin]
    on = {origin}

    def dfs(u, dist):
        if u == target:
            best.append((dist, list(path)))
            return
        for v in sorted(nbr[u]):
            if v in on:
                continue
            on.add(v)
            path.append(v)
            dfs(v, dist + nbr[u][v]['length_mm'])
            path.pop()
            on.discard(v)
    dfs(origin, 0)
    best.sort(key=lambda x: x[0])
    shortest = best[0][0]
    ties = [p for d, p in best if d == shortest]
    return {'length_mm': shortest, 'nodes': ties[0], 'unique': len(ties) == 1, 'simple_paths': len(best)}


def route_oracle(adj, origin, target, step_free, blocked):
    r = route_enum(adj, origin, target, step_free, blocked)
    if r:
        return {'outcome': 'PATH', 'nodes': r['nodes'], 'length_mm': r['length_mm']}, r
    if step_free and route_enum(adj, origin, target, False, blocked):
        return {'outcome': 'REJECT_STEP_FREE_UNAVAILABLE'}, None
    if blocked and route_enum(adj, origin, target, step_free, set()):
        return {'outcome': 'REJECT_BLOCKED'}, None
    return {'outcome': 'REJECT_UNREACHABLE'}, None


# ---------------- route steps (G1-ROUTE-STEPS-1.0), written independently of src/steps.mjs ----------------
def route_steps(nodes, edge_by_pair, path, code):
    out, acc, total = [], 0, 0

    def whole(mm):
        return (mm + 500) // 1000

    def flush():
        nonlocal acc
        if acc > 0:
            out.append({'kind': 'walk', 'm': whole(acc)})
        acc = 0

    for a, b in zip(path, path[1:]):
        e = edge_by_pair[(a, b)]
        total += e['length_mm']
        if e['kind'] in ('corridor', 'spur', 'outdoor'):
            acc += e['length_mm']
        elif e['kind'] == 'entrance':
            acc += e['length_mm']
            flush()
            inside_a = nodes[a].get('building') is not None
            inside_b = nodes[b].get('building') is not None
            check(inside_a != inside_b, 'entrance joins indoor and outdoor ' + e['id'])
            out.append({'kind': 'exit', 'building': nodes[a]['building']} if inside_a else {'kind': 'enter', 'building': nodes[b]['building']})
        elif e['kind'] in ('stairs', 'elevator'):
            flush()
            out.append({'kind': e['kind'], 'floor': nodes[b]['floor']})
        else:
            check(False, 'unknown edge kind ' + e['kind'])
    flush()
    out.append({'kind': 'arrive', 'code': code})
    seen_floors = []
    for n in path:
        f = nodes[n].get('floor')
        if f is not None and f not in seen_floors:
            seen_floors.append(f)
    return {'steps': out, 'summary': {'length_m': whole(total), 'steps': len(out), 'floors': '-'.join(str(f) for f in seen_floors)}}


# ---------------- trust contract ----------------
def verify_bundle(zbytes, store, now, active_version, high_water=None):
    try:
        z = zipfile.ZipFile(io.BytesIO(zbytes))
        names = z.namelist()
        if len(set(names)) != len(names) or any(n.startswith('/') or '..' in n.split('/') or '\\' in n for n in names):
            return 'REJECT_MALFORMED_CONTAINER'
        if any(i.compress_type != 0 for i in z.infolist()):
            return 'REJECT_MALFORMED_CONTAINER'
        files = {n: z.read(n) for n in names}
    except zipfile.BadZipFile:
        return 'REJECT_MALFORMED_CONTAINER'
    if 'MANIFEST.json' not in files or 'bundle_signature.json' not in files:
        return 'REJECT_MALFORMED_MANIFEST'
    manifest_bytes = files['MANIFEST.json']
    sig = json.loads(files['bundle_signature.json'])
    if high_water is not None and now < high_water - timedelta(seconds=300):
        return 'REJECT_UNTRUSTED_TIME'
    key = next((k for k in store['keys'] if k['key_id'] == sig['key_id']), None)
    if key is None:
        return 'REJECT_UNKNOWN_KEY'
    if key['status'] == 'revoked':
        return 'REJECT_REVOKED_KEY'
    if key['valid_until'] and now > datetime.fromisoformat(key['valid_until'].replace('Z', '+00:00')):
        return 'REJECT_EXPIRED_KEY'
    try:
        Ed25519PublicKey.from_public_bytes(b64u(key['public_key'])).verify(b64u(sig['signature']), manifest_bytes)
    except InvalidSignature:
        return 'REJECT_BAD_SIGNATURE'
    m = json.loads(manifest_bytes)
    if m.get('schema_version') != 1:
        return 'REJECT_SCHEMA'
    mv = re.fullmatch(r'G1SYN-(\d+)\.(\d+)\.(\d+)', m.get('bundle_version', ''))
    if not mv or int(mv.group(1)) > 1:
        return 'REJECT_UNSUPPORTED_VERSION'
    listed = {f['path']: f for f in m['files']}
    payload = {n: b for n, b in files.items() if n not in ('MANIFEST.json', 'bundle_signature.json')}
    if set(listed) != set(payload) or any(len(payload[p]) != f['bytes'] or sha(payload[p]) != f['sha256'] for p, f in listed.items()):
        return 'REJECT_HASH_MISMATCH'
    vf = datetime.fromisoformat(m['valid_from'].replace('Z', '+00:00'))
    vu = datetime.fromisoformat(m['valid_until'].replace('Z', '+00:00'))
    if now < vf:
        return 'REJECT_NOT_YET_VALID'
    if now > vu:
        return 'REJECT_EXPIRED'
    if active_version:
        cand = tuple(int(x) for x in mv.groups())
        act = tuple(int(x) for x in re.fullmatch(r'G1SYN-(\d+)\.(\d+)\.(\d+)', active_version).groups())
        if cand < act:
            return 'REJECT_DOWNGRADE'
        if cand == act:
            return 'REJECT_ALREADY_ACTIVE'
    return 'ACTIVATED'


def qr_validate(payload, store, anchors, active_version, now):
    if not payload.startswith('G1SYN:'):
        return {'outcome': 'REJECT_FOREIGN_PAYLOAD'}
    if len(payload.encode('utf-8')) > 2953:
        return {'outcome': 'REJECT_MALFORMED'}
    parts = payload.split(':')
    if len(parts) != 6 or parts[1] != '1' or not re.fullmatch(r'A[0-9]{2}', parts[2]) or \
            not re.fullmatch(r'G1SYN-\d+\.\d+\.\d+', parts[3]) or not re.fullmatch(r'\d{8}T\d{6}Z', parts[4]) or \
            not re.fullmatch(r'[A-Za-z0-9_-]{86}', parts[5]):
        return {'outcome': 'REJECT_MALFORMED'}
    prefix = payload[:payload.rindex(':')].encode('utf-8')
    ok = False
    for k in store['keys']:
        if k['status'] != 'trusted' or (k['valid_until'] and now > datetime.fromisoformat(k['valid_until'].replace('Z', '+00:00'))):
            continue
        try:
            Ed25519PublicKey.from_public_bytes(b64u(k['public_key'])).verify(b64u(parts[5]), prefix)
            ok = True
        except InvalidSignature:
            pass
    if not ok:
        return {'outcome': 'REJECT_BAD_SIGNATURE'}
    exp = datetime.strptime(parts[4], '%Y%m%dT%H%M%SZ').replace(tzinfo=timezone.utc)
    if now > exp:
        return {'outcome': 'REJECT_EXPIRED'}
    if parts[2] not in anchors:
        return {'outcome': 'REJECT_UNKNOWN_ANCHOR'}
    if parts[3] != active_version:
        return {'outcome': 'REJECT_BUNDLE_MISMATCH'}
    return {'outcome': 'IDENTITY_VALID', 'anchor': parts[2], 'pose_established': False}


def main(out):
    rec = json.load(open(f'{out}/GENERATION_RECORD.json', encoding='utf-8'))
    for o in rec['outputs']:
        check(sha(open(f"{out}/{o['path']}", 'rb').read()) == o['sha256'], 'output hash ' + o['path'])
    store = json.load(open(f'{out}/app/trust_store.json', encoding='utf-8'))
    w_start = datetime.fromisoformat(rec['inputs']['w_start'].replace('Z', '+00:00'))
    now = w_start + timedelta(days=1)
    bundle = open(f'{out}/bundle/G1SYN-1.0.0.zip', 'rb').read()
    check(verify_bundle(bundle, store, now, None) == 'ACTIVATED', 'bundle must verify and activate')
    z = zipfile.ZipFile(io.BytesIO(bundle))
    files = {n: z.read(n) for n in z.namelist()}
    check(sha(files['MANIFEST.json']) == rec['bundle']['bundle_sha256'], 'bundle_sha256 = sha256(MANIFEST.json)')
    graph = json.loads(files['graph.json'])
    nodes = {n['id']: n for n in graph['nodes']}
    check(len(graph['nodes']) == 3000 and len(nodes) == 3000, 'node count/unique')
    check(len(graph['edges']) == 6000 and len({e['id'] for e in graph['edges']}) == 6000, 'directed edge count/unique')
    und = {}
    for e in graph['edges']:
        check(e['from'] in nodes and e['to'] in nodes and e['from'] != e['to'], 'edge endpoints ' + e['id'])
        und.setdefault(e['edge'], []).append(e)
    check(len(und) == 3000 and all(len(v) == 2 for v in und.values()), '3000 undirected edges, both directions')
    pairs = set()
    for eid, (a, b) in und.items():
        check(a['from'] == b['to'] and a['to'] == b['from'] and a['length_mm'] == b['length_mm'] and a['kind'] == b['kind'], 'pair ' + eid)
        key = tuple(sorted((a['from'], a['to'])))
        check(key not in pairs, 'duplicate undirected pair ' + eid)
        pairs.add(key)
        p, q = nodes[a['from']], nodes[a['to']]
        if a['kind'] == 'stairs':
            want = 10500
        elif a['kind'] == 'elevator':
            want = 30000
        else:
            d2 = (p['x_mm'] - q['x_mm']) ** 2 + (p['y_mm'] - q['y_mm']) ** 2
            r = int(d2 ** 0.5)
            while r * r > d2:
                r -= 1
            while (r + 1) * (r + 1) <= d2:
                r += 1
            want = r if r * r == d2 else r + 1
        check(a['length_mm'] == want, 'length reproducible ' + eid)
        check(a['step_free'] == (a['kind'] != 'stairs'), 'step_free attribute ' + eid)
    adj = {n: [] for n in nodes}
    for e in graph['edges']:
        adj[e['from']].append({'to': e['to'], 'edge': e['edge'], 'length_mm': e['length_mm'], 'step_free': e['step_free']})
    comps, seen = [], set()
    for n in sorted(nodes):
        if n in seen:
            continue
        stack, members = [n], {n}
        seen.add(n)
        while stack:
            u = stack.pop()
            for e in adj[u]:
                if e['to'] not in seen:
                    seen.add(e['to'])
                    members.add(e['to'])
                    stack.append(e['to'])
        ecount = sum(len(adj[u]) for u in members) // 2
        comps.append((len(members), ecount))
    comps.sort(reverse=True)
    check(comps[0] == (2920, 2928) and comps[0][1] - comps[0][0] + 1 == 9, 'main component 2920/2928 with 9 cycles')
    check(comps[1:] == [(10, 9)] * 8, 'eight wing trees of 10 nodes')
    dest = json.loads(files['destinations.json'])['destinations']
    check(len(dest) == 300 and len({d['code'] for d in dest}) == 300, '300 destinations with unique codes')
    for d in dest:
        spurs = [e for e in adj[d['node']]]
        check(len(spurs) == 1 and nodes[spurs[0]['to']]['kind'] == 'corridor', 'destination attached to one corridor node ' + d['id'])
    nums = {}
    for d in dest:
        nums.setdefault(d['room_number'], set()).add(d['building'])
    check(sum(1 for v in nums.values() if len(v) == 2) == 30 and max(len(v) for v in nums.values()) == 2, '30 cross-building lookalikes')
    check(sum(d['long_name'] for d in dest) == 12 and sum(d['diacritized'] for d in dest) == 12, '12 long and 12 diacritized names')
    # search oracle
    index = []
    for d in dest:
        toks = set(tokens(d['name_en'])) | set(tokens(d['name_ar']))
        toks |= {d['building'].lower(), 'f%d' % d['floor'], 'r' + d['room_number'], d['room_number'], code_key(d['code']).lower()}
        index.append({'id': d['id'], 'key': code_key(d['code']), 'tokens': toks})
    corpus = json.loads(files['query_corpus.json'])['queries']
    so_bytes = open(f'{out}/oracle/search_oracle.json', 'rb').read()
    so = json.loads(so_bytes)
    mine = [{'id': q['id'], **search(q['text'], index)} for q in corpus]
    check(mine == so['results'], 'search oracle re-derived independently')
    rebuilt = dict(so)
    rebuilt['results'] = mine
    check(doc_json(rebuilt) == so_bytes, 'search oracle byte-for-byte')
    # route oracle
    cases = json.loads(files['route_cases.json'])['cases']
    ro_bytes = open(f'{out}/oracle/route_oracle.json', 'rb').read()
    ro = json.loads(ro_bytes)
    dnode = {d['id']: d['node'] for d in dest}
    dcode = {d['id']: d['code'] for d in dest}
    edge_by_pair = {(e['from'], e['to']): e for e in graph['edges']}
    check(ro.get('steps_contract') == 'G1-ROUTE-STEPS-1.0', 'route oracle names the steps contract')
    results = []
    for c, expect in zip(cases, ro['results']):
        res, detail = route_oracle(adj, c['origin'], dnode[c['destination']], c['step_free'], set(c['blocked']))
        if detail:
            check(detail['unique'], 'unique shortest path ' + c['id'])
            check(detail['length_mm'] == sum(edge_by_pair[(a, b)]['length_mm'] for a, b in zip(detail['nodes'], detail['nodes'][1:])), 'path length ' + c['id'])
            res.update(route_steps(nodes, edge_by_pair, res['nodes'], dcode[c['destination']]))
        results.append({'id': c['id'], 'class': expect['class'], **res})
    check(results == ro['results'], 'route oracle re-derived by exhaustive enumeration')
    rebuilt = dict(ro)
    rebuilt['results'] = results
    check(doc_json(rebuilt) == ro_bytes, 'route oracle byte-for-byte')
    # QR fixtures
    qf = json.load(open(f'{out}/oracle/qr_fixtures.json', encoding='utf-8'))
    anchors = {a['id'] for a in json.loads(files['qr_identities.json'])['anchors']}
    for f in qf['fixtures']:
        got = qr_validate(f['payload'], store, anchors, 'G1SYN-1.0.0', now)
        check(got == f['expected'] or (f['kind'] == 'foreign_url' and got['outcome'] == f['expected']['outcome']), 'qr fixture ' + f['id'])
    try:
        import zxingcpp
        from PIL import Image
        for f in qf['fixtures']:
            res = zxingcpp.read_barcodes(Image.open(f"{out}/{f['png']}"))
            check(bool(res) and res[0].text == f['payload'], 'qr image decodes ' + f['id'])
    except ImportError:
        print('note: zxingcpp/Pillow not installed; QR image decode skipped')
    # trust fixtures
    fx = json.load(open(f'{out}/fixtures/FIXTURES.json', encoding='utf-8'))
    for f in fx['fixtures']:
        if f['file'] is None:
            continue
        got = verify_bundle(open(f"{out}/{f['file']}", 'rb').read(), store, now, 'G1SYN-1.0.0')
        check(got == f['expected'], 'trust fixture %s: %s' % (f['id'], got))
    expired = open(f'{out}/fixtures/F-EXPIRED.zip', 'rb').read()
    check(verify_bundle(expired, store, w_start - timedelta(days=30), 'G1SYN-1.0.0', high_water=now) == 'REJECT_UNTRUSTED_TIME', 'F-CLOCK (a)')
    check(verify_bundle(open(f'{out}/fixtures/F-NOT-YET-VALID.zip', 'rb').read(), store, now, 'G1SYN-1.0.0') == 'REJECT_NOT_YET_VALID', 'F-CLOCK (b)')
    # schedule
    sched = json.loads(files['schedule.json'])['entries']
    check(len(sched) == 60 and len({(s['destination'], s['start']) for s in sched}) == 60, 'schedule 60 unique entries')
    main_ids = {d['id'] for d in dest if not d['wing']}
    check(all(s['destination'] in main_ids and s['start'][:10] in {'2026-10-0%d' % i for i in range(4, 9)} and s['start'].endswith('+03:00') for s in sched), 'schedule rules')
    # glyph coverage: every code point used in room labels (and the Arabic presentation forms of their letters) has a glyph
    have = set()
    for n, b in files.items():
        if n.startswith('glyphs/'):
            have |= pbf_glyph_ids(b)
    need = set()
    pres = presentation_forms()
    for d in dest:
        for s in (d['name_en'], d['name_ar']):
            for ch in s:
                need.add(ord(ch))
                need |= pres.get(ord(ch), set())
    missing = sorted(c for c in need if c not in have and c != 0x20)
    check(not missing, 'glyph coverage, missing: ' + ','.join('U+%04X' % c for c in missing[:20]))
    print(json.dumps({'ok': not FAILS, 'failures': FAILS[:50], 'failure_count': len(FAILS),
                      'checked': {'outputs': len(rec['outputs']), 'queries': len(corpus), 'routes': len(cases),
                                  'qr_fixtures': len(qf['fixtures']), 'trust_fixtures': len(fx['fixtures']),
                                  'glyph_codepoints_required': len(need)}}, indent=1))
    return 0 if not FAILS else 1


def presentation_forms():
    """Arabic presentation forms whose compatibility decomposition is a single base letter (isolated/initial/medial/final)."""
    out = {}
    for cp in list(range(0xFB50, 0xFE00)) + list(range(0xFE70, 0xFF00)):
        dec = unicodedata.decomposition(chr(cp))
        m = re.fullmatch(r'<(isolated|initial|medial|final)> ([0-9A-F]{4})', dec)
        if m:
            out.setdefault(int(m.group(2), 16), set()).add(cp)
    return out


def pbf_glyph_ids(buf):
    """Minimal protobuf walk of a glyphs PBF: glyphs.stacks[1].glyphs[3].id[1]."""
    def fields(b):
        i = 0
        while i < len(b):
            key, i = varint(b, i)
            f, w = key >> 3, key & 7
            if w == 0:
                v, i = varint(b, i)
                yield f, v
            elif w == 2:
                ln, i = varint(b, i)
                yield f, b[i:i + ln]
                i += ln
            elif w == 5:
                i += 4
            elif w == 1:
                i += 8
            else:
                raise ValueError('wire type')

    def varint(b, i):
        shift = result = 0
        while True:
            c = b[i]
            i += 1
            result |= (c & 0x7f) << shift
            if not c & 0x80:
                return result, i
            shift += 7
    ids = set()
    for f, stack in fields(buf):
        if f != 1:
            continue
        for g, glyph in fields(stack):
            if g != 3:
                continue
            for h, v in fields(glyph):
                if h == 1:
                    ids.add(v)
    return ids


if __name__ == '__main__':
    sys.exit(main(sys.argv[1]))
