// G1 synthetic data generator - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// Synthetic QR anchor identities G1-QR-1.0: payload "G1SYN:1:<anchor>:<bundle_version>:<expiry>:<signature>"; the expiry
// uses ISO 8601 basic format (YYYYMMDDTHHMMSSZ, no colons); the signature is base64url (no padding) of the Ed25519
// signature by lab key 1 over the UTF-8 prefix before the last colon. A QR identity never establishes pose, floor or arrival.
import QRCode from 'qrcode';
import { encodePng } from './binary.mjs';
import { b64url, signBytes } from './trust.mjs';
import { LABEL } from './canonical.mjs';

export const QR_CONTRACT = 'G1-QR-1.0';
export const basicUtc = (iso) => iso.replace(/[-:]/g, '').replace('.000', '');

export function payload(key1, anchorId, bundleVersion, expiryIso) {
  const prefix = `G1SYN:1:${anchorId}:${bundleVersion}:${basicUtc(expiryIso)}`;
  return `${prefix}:${b64url(signBytes(key1, Buffer.from(prefix, 'utf8')))}`;
}

/** Anchors A01..A18: two per floor at the stairs (6, 0) and elevator (18, 0) spine nodes in canonical floor order. */
export function anchors(nodes) {
  const out = [];
  for (const b of [1, 2, 3]) {
    for (const f of [1, 2, 3]) {
      for (const [c, kind] of [[6, 'stairs'], [18, 'elevator']]) {
        const n = nodes.find((x) => x.kind === 'corridor' && !x.wing && x.building === b && x.floor === f && x.c === c && x.r === 0);
        out.push({ id: `A${String(out.length + 1).padStart(2, '0')}`, node: n.id, building: `SB${b}`, floor: f, kind });
      }
    }
  }
  return out;
}

/** QR fixtures: 18 valid anchors, 6 negative anchor fixtures A19..A24 and one foreign-URL payload (never opened). */
export function qrFixtures(key1, anchorList, bundleVersion, wStartIso, wEndIso) {
  const fx = anchorList.map((a) => ({ id: a.id, kind: 'valid', source_anchor: a.id, payload: payload(key1, a.id, bundleVersion, wEndIso),
    expected: { outcome: 'IDENTITY_VALID', anchor: a.id, pose_established: false } }));
  const byId = new Map(fx.map((f) => [f.id, f]));
  const flipSig = (p) => {
    const i = p.lastIndexOf(':') + 1;
    const c = p[i];
    return p.slice(0, i) + (c === 'A' ? 'B' : 'A') + p.slice(i + 1);
  };
  const expiredMinus1 = new Date(Date.parse(wStartIso) - 1000).toISOString();
  fx.push(
    { id: 'A19', kind: 'invalid_signature', source_anchor: 'A03', payload: flipSig(byId.get('A03').payload), expected: { outcome: 'REJECT_BAD_SIGNATURE' } },
    { id: 'A20', kind: 'copied', source_anchor: 'A05', payload: byId.get('A05').payload,
      context: 'presented in a second context (copy of A05)', expected: { outcome: 'IDENTITY_VALID', anchor: 'A05', pose_established: false } },
    { id: 'A21', kind: 'relocated', source_anchor: 'A08', payload: byId.get('A08').payload,
      context: 'physically relocated A08 (indistinguishable by payload)', expected: { outcome: 'IDENTITY_VALID', anchor: 'A08', pose_established: false } },
    { id: 'A22', kind: 'wrong_floor', source_anchor: 'A12', payload: byId.get('A12').payload,
      context: 'scanned while the active route is on another floor', expected: { outcome: 'IDENTITY_VALID', anchor: 'A12', pose_established: false } },
    { id: 'A23', kind: 'expired', source_anchor: 'A14', payload: payload(key1, 'A14', bundleVersion, expiredMinus1), expected: { outcome: 'REJECT_EXPIRED' } },
    { id: 'A24', kind: 'malformed', source_anchor: 'A16', payload: byId.get('A16').payload.split(':').slice(0, 4).join(':'), expected: { outcome: 'REJECT_MALFORMED' } },
    { id: 'QF-FOREIGN-URL', kind: 'foreign_url', source_anchor: null, payload: 'https://example.invalid/g1/anchor?id=A01', expected: { outcome: 'REJECT_FOREIGN_PAYLOAD', opened: false } },
  );
  return fx;
}

/** Render a payload as an 8-bit grayscale PNG: error correction H, 8 px per module, 4-module quiet zone. */
export function renderQr(text) {
  const qr = QRCode.create(text, { errorCorrectionLevel: 'H' });
  const size = qr.modules.size;
  const scale = 8;
  const quiet = 4;
  const dim = (size + 2 * quiet) * scale;
  const px = Buffer.alloc(dim * dim, 255);
  for (let y = 0; y < size; y += 1) {
    for (let x = 0; x < size; x += 1) {
      if (!qr.modules.get(y, x)) continue;
      for (let dy = 0; dy < scale; dy += 1) {
        const row = ((y + quiet) * scale + dy) * dim + (x + quiet) * scale;
        px.fill(0, row, row + scale);
      }
    }
  }
  return { png: encodePng(dim, dim, px, { colorType: 0, bitDepth: 1, text: { Comment: LABEL } }), version: qr.version, size };
}
