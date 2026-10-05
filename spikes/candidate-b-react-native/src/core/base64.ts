// Candidate B (React Native) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// Base64 for the TurboModule boundary (which has no binary type). The engine's btoa/atob (Hermes, Node) are used when
// present; the portable implementation below is the fallback and the reference in the unit tests.
const ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
const LOOKUP = (() => {
  const l = new Int16Array(128).fill(-1);
  for (let i = 0; i < ALPHABET.length; i++) l[ALPHABET.charCodeAt(i)] = i;
  return l;
})();

type G = { btoa?: (s: string) => string; atob?: (s: string) => string };
const engine = globalThis as unknown as G;

export function encodeBase64Portable(bytes: Uint8Array): string {
  const parts: string[] = [];
  let i = 0;
  for (; i + 2 < bytes.length; i += 3) {
    const n = (bytes[i] << 16) | (bytes[i + 1] << 8) | bytes[i + 2];
    parts.push(ALPHABET[(n >> 18) & 63] + ALPHABET[(n >> 12) & 63] + ALPHABET[(n >> 6) & 63] + ALPHABET[n & 63]);
  }
  if (i < bytes.length) {
    const n = (bytes[i] << 16) | ((i + 1 < bytes.length ? bytes[i + 1] : 0) << 8);
    parts.push(ALPHABET[(n >> 18) & 63] + ALPHABET[(n >> 12) & 63] + (i + 1 < bytes.length ? ALPHABET[(n >> 6) & 63] + '=' : '=='));
  }
  return parts.join('');
}

/** Strict decoding: only the standard alphabet, padding only at the end; anything else throws. */
export function decodeBase64Portable(s: string): Uint8Array {
  if (!/^[A-Za-z0-9+/]*={0,2}$/.test(s) || s.length % 4 === 1) throw new Error('base64');
  const clean = s.replace(/=+$/, '');
  const out = new Uint8Array(Math.floor((clean.length * 3) / 4));
  let acc = 0;
  let bits = 0;
  let o = 0;
  for (let i = 0; i < clean.length; i++) {
    const c = clean.charCodeAt(i);
    const v = c < 128 ? LOOKUP[c] : -1;
    if (v < 0) throw new Error('base64');
    acc = ((acc << 6) | v) & 0xffffff;
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      out[o++] = (acc >> bits) & 0xff;
    }
  }
  return o === out.length ? out : out.subarray(0, o);
}

export function encodeBase64(bytes: Uint8Array): string {
  const btoa = engine.btoa;
  if (typeof btoa !== 'function') return encodeBase64Portable(bytes);
  let bin = '';
  for (let i = 0; i < bytes.length; i += 8192) bin += String.fromCharCode(...bytes.subarray(i, i + 8192));
  return btoa(bin);
}

export function decodeBase64(s: string): Uint8Array {
  const atob = engine.atob;
  if (typeof atob !== 'function' || !/^[A-Za-z0-9+/]*={0,2}$/.test(s)) return decodeBase64Portable(s);
  const bin = atob(s);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}
