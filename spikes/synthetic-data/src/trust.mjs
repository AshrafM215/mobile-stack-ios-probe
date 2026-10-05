// G1 synthetic data generator - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// Synthetic lab keys (public by design, never secrets, never used outside the lab), Ed25519 signing, trust store.
import { createPrivateKey, createPublicKey, sign as edSign, verify as edVerify, createHash } from 'node:crypto';
import { rawBytes } from './drbg.mjs';

const PKCS8_ED25519_PREFIX = Buffer.from('302e020100300506032b657004220420', 'hex');
export const b64url = (buf) => Buffer.from(buf).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
export const fromB64url = (s) => Buffer.from(s.replace(/-/g, '+').replace(/_/g, '/'), 'base64');

/** Lab key n (1..4): seed = first four 8-byte DRBG outputs of domain "lab-key-<n>". */
export function labKey(n) {
  const seed = rawBytes(`lab-key-${n}`, 4);
  const privateKey = createPrivateKey({ key: Buffer.concat([PKCS8_ED25519_PREFIX, seed]), format: 'der', type: 'pkcs8' });
  const spki = createPublicKey(privateKey).export({ format: 'der', type: 'spki' });
  const publicRaw = spki.subarray(spki.length - 32);
  const keyId = createHash('sha256').update(publicRaw).digest('hex').slice(0, 16);
  return { n, privateKey, publicRaw, keyId, publicKey: createPublicKey(privateKey) };
}

export const signBytes = (key, bytes) => edSign(null, bytes, key.privateKey);
export const verifyBytes = (key, bytes, sig) => edVerify(null, bytes, key.publicKey, sig);

/** Trust store compiled into every candidate build (identical bytes for A, B and C). */
export function trustStore(keys, wStartIso) {
  const expiredKeyUntil = new Date(Date.parse(wStartIso) - 1000).toISOString().replace('.000Z', 'Z');
  return {
    label: 'NON-PRODUCTION / SYNTHETIC LAB TRUST STORE / NOT FOR PRODUCTION USE',
    trust_contract: 'G1-TRUST-1.0',
    algorithm: 'Ed25519',
    keys: [
      { key_id: keys[1].keyId, public_key: b64url(keys[1].publicRaw), status: 'trusted', valid_until: null, lab_key: 1 },
      { key_id: keys[2].keyId, public_key: b64url(keys[2].publicRaw), status: 'revoked', valid_until: null, lab_key: 2 },
      { key_id: keys[3].keyId, public_key: b64url(keys[3].publicRaw), status: 'trusted', valid_until: expiredKeyUntil, lab_key: 3 },
    ],
    absent_lab_keys: [{ lab_key: 4, key_id: keys[4].keyId }],
  };
}
