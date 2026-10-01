// G1 synthetic data generator - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// Assembles the signed bundle (stored ZIP) and the trust fixtures of G1-TRUST-1.0.
import { LABEL, documentJson, prettyJson, sha256 } from './canonical.mjs';
import { encodeZip } from './binary.mjs';
import { b64url, signBytes } from './trust.mjs';
import { Stream } from './drbg.mjs';
import { SEARCH_CONTRACT } from './search.mjs';
import { ROUTE_CONTRACT } from './routes.mjs';
import { QR_CONTRACT } from './qr.mjs';
import { STYLE_CONTRACT } from './mapres.mjs';
import { destinationRecord } from './destinations.mjs';

export const SPEC = 'G1-SYNTH-SPEC-0.3';
export const TRUST_CONTRACT = 'G1-TRUST-1.0';
export const BUNDLE_SCHEMA_VERSION = 1;

/** Data files of one bundle version (every JSON file carries the label and its bundle_version). */
export function bundleFiles(ctx, bundleVersion) {
  const { nodes, edges, dests, queries, cases, anchorList, schedule, geojson, style, glyphs, sprites } = ctx;
  const hdr = { label: LABEL, bundle_version: bundleVersion };
  const files = {};
  const directed = [];
  for (const e of edges) {
    directed.push({ id: `${e.id}+`, from: e.a, to: e.b, edge: e.id, kind: e.kind, length_mm: e.length_mm, step_free: e.step_free });
    directed.push({ id: `${e.id}-`, from: e.b, to: e.a, edge: e.id, kind: e.kind, length_mm: e.length_mm, step_free: e.step_free });
  }
  files['graph.json'] = documentJson({ ...hdr, frame: 'G1-SYNTH-LOCAL', units: 'mm', route_contract: ROUTE_CONTRACT,
    nodes: nodes.map((n) => ({ id: n.id, kind: n.kind, building: n.building ? `SB${n.building}` : null, floor: n.floor, x_mm: n.x_mm, y_mm: n.y_mm, ...(n.entrance ? { entrance: true } : {}), ...(n.dest_id ? { destination: n.dest_id } : {}) })),
    edges: directed });
  files['destinations.json'] = documentJson({ ...hdr, destinations: dests.map(destinationRecord) });
  files['search_index_input.json'] = documentJson({ ...hdr, search_contract: SEARCH_CONTRACT,
    fields: ['code', 'building', 'floor', 'room_number', 'name_en', 'name_ar'],
    entries: dests.map((d) => ({ id: d.id, code: d.code, building: `SB${d.building}`, floor: d.floor, room_number: d.number, name_en: d.name_en, name_ar: d.name_ar })) });
  files['query_corpus.json'] = documentJson({ ...hdr, search_contract: SEARCH_CONTRACT, order: 'fixed shuffled order (DRBG domain queries)',
    queries: queries.map((q) => ({ id: q.id, text: q.text })) });
  files['route_cases.json'] = documentJson({ ...hdr, route_contract: ROUTE_CONTRACT,
    cases: cases.map((c) => ({ id: c.id, origin: c.origin, destination: c.destination, step_free: c.step_free, blocked: c.blocked })) });
  files['qr_identities.json'] = documentJson({ ...hdr, qr_contract: QR_CONTRACT, rule: 'A QR identity never establishes pose, floor or arrival.', anchors: anchorList });
  files['schedule.json'] = documentJson({ ...hdr, time_zone: 'Etc/GMT-3', utc_offset: '+03:00', week: 'SYNTHETIC 2026-10-04..2026-10-08', entries: schedule });
  files['geometry.geojson'] = documentJson({ ...geojson, bundle_version: bundleVersion });
  files['style.json'] = prettyJson({ ...style, metadata: { ...style.metadata, bundle_version: bundleVersion } });
  Object.assign(files, glyphs, sprites);
  return files;
}

export function manifestFor(files, bundleVersion, validFrom, validUntil, schemaVersion = BUNDLE_SCHEMA_VERSION, overrides = {}) {
  const list = Object.keys(files).sort().map((p) => ({ path: p, bytes: files[p].length, sha256: overrides[p] ?? sha256(files[p]) }));
  return prettyJson({
    schema_version: schemaVersion, label: LABEL, bundle_version: bundleVersion, spec: SPEC, trust_contract: TRUST_CONTRACT,
    valid_from: validFrom, valid_until: validUntil,
    contracts: { search: SEARCH_CONTRACT, route: ROUTE_CONTRACT, qr: QR_CONTRACT, style: STYLE_CONTRACT },
    files: list,
  });
}

export function signatureFor(key, manifestBytes) {
  return prettyJson({ algorithm: 'Ed25519', key_id: key.keyId, signature: b64url(signBytes(key, manifestBytes)) });
}

export function zipBundle(files, manifestBytes, signatureBytes) {
  const entries = Object.entries(files).map(([name, data]) => ({ name, data }));
  entries.push({ name: 'MANIFEST.json', data: manifestBytes }, { name: 'bundle_signature.json', data: signatureBytes });
  return encodeZip(entries);
}

const iso = (ms) => new Date(ms).toISOString().replace('.000Z', 'Z');

/** The ten file fixtures of the trust contract plus their exact expected outcomes. */
export function trustFixtures(ctx, keys, valid, wStartIso, wEndIso) {
  const ws = Date.parse(wStartIso);
  const we = Date.parse(wEndIso);
  const day = 86400000;
  const out = {};
  const index = [];
  const add = (id, files, manifest, sigKey, expected, note) => {
    out[`fixtures/${id}.zip`] = zipBundle(files, manifest, signatureFor(sigKey, manifest));
    index.push({ id, file: `fixtures/${id}.zip`, expected, note });
  };
  const f100 = valid.files;
  add('F-EXPIRED', f100, manifestFor(f100, 'G1SYN-1.0.0', iso(ws - 90 * day), iso(ws - 1000)), keys[1], 'REJECT_EXPIRED', 'validity W_start-90d .. W_start-1s, validly signed');
  add('F-NOT-YET-VALID', f100, manifestFor(f100, 'G1SYN-1.0.0', iso(we + day), iso(we + 90 * day)), keys[1], 'REJECT_NOT_YET_VALID', 'validity W_end+1d .. W_end+90d, validly signed');
  const tampered = { ...f100 };
  const g = Buffer.from(f100['graph.json']);
  const off = new Stream('tamper').randbelow(g.length);
  g[off] ^= 0x01;
  tampered['graph.json'] = g;
  out['fixtures/F-TAMPERED.zip'] = zipBundle(tampered, valid.manifest, valid.signature);
  index.push({ id: 'F-TAMPERED', file: 'fixtures/F-TAMPERED.zip', expected: 'REJECT_HASH_MISMATCH', note: `graph.json byte ${off} XOR 0x01 after signing (valid manifest and signature)` });
  add('F-WRONG-SCHEMA', f100, manifestFor(f100, 'G1SYN-1.0.0', wStartIso, wEndIso, 99), keys[1], 'REJECT_SCHEMA', 'MANIFEST schema_version 99, validly signed');
  const withLic = ctx.bundleFilesWithLicenses || ((x) => x);
  const f090 = withLic(bundleFiles(ctx, 'G1SYN-0.9.0'));
  add('F-MIXED', f100, manifestFor(f100, 'G1SYN-1.0.0', wStartIso, wEndIso, 1, { 'graph.json': sha256(f090['graph.json']) }), keys[1], 'REJECT_HASH_MISMATCH', 'MANIFEST lists the graph.json hash of G1SYN-0.9.0 while the files are G1SYN-1.0.0, validly signed');
  add('F-REVOKED', f100, valid.manifest, keys[2], 'REJECT_REVOKED_KEY', 'valid content signed with lab key 2 (revoked)');
  add('F-EXPIRED-KEY', f100, valid.manifest, keys[3], 'REJECT_EXPIRED_KEY', 'valid content signed with lab key 3 (trusted only until W_start-1s)');
  add('F-UNKNOWN-KEY', f100, valid.manifest, keys[4], 'REJECT_UNKNOWN_KEY', 'valid content signed with lab key 4 (absent from the trust store)');
  const f200 = withLic(bundleFiles(ctx, 'G1SYN-2.0.0'));
  add('F-WRONG-VERSION', f200, manifestFor(f200, 'G1SYN-2.0.0', wStartIso, wEndIso), keys[1], 'REJECT_UNSUPPORTED_VERSION', 'validly signed bundle_version G1SYN-2.0.0 (unsupported major version)');
  add('F-DOWNGRADE', f090, manifestFor(f090, 'G1SYN-0.9.0', wStartIso, wEndIso), keys[1], 'REJECT_DOWNGRADE', 'validly signed G1SYN-0.9.0 offered while G1SYN-1.0.0 is active');
  index.push({ id: 'F-CLOCK', file: null, expected: { a: 'REJECT_UNTRUSTED_TIME', b: 'REJECT_NOT_YET_VALID' },
    note: '(a) after activating G1SYN-1.0.0 and rejecting F-EXPIRED at real time, the device clock is set to W_start-30d; F-EXPIRED must stay rejected and the backward jump is untrusted time (no validity-dependent authoritative guidance); (b) at real time F-NOT-YET-VALID is rejected' });
  return { files: out, index };
}
