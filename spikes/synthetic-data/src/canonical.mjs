// G1 synthetic data generator - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// Canonical, byte-stable serialization helpers shared by every generated text artifact.
import { createHash } from 'node:crypto';

export const LABEL = 'NON-PRODUCTION / SYNTHETIC DATA ONLY / NOT A REAL INSTITUTION / NOT FOR NAVIGATION';

export const sha256 = (bytes) => createHash('sha256').update(bytes).digest('hex');

/** Compact JSON for one value (object key order = insertion order, which every builder fixes explicitly). */
export const compact = (value) => JSON.stringify(value);

/**
 * Line-oriented JSON document: a top-level object whose array members are written one element per line.
 * Deterministic, UTF-8, LF line endings, final newline, no trailing whitespace.
 */
export function documentJson(doc) {
  const keys = Object.keys(doc);
  const parts = keys.map((key, index) => {
    const value = doc[key];
    const sep = index === keys.length - 1 ? '' : ',';
    if (Array.isArray(value) && value.length > 0) {
      const lines = value.map((item, i) => compact(item) + (i === value.length - 1 ? '' : ','));
      return `${compact(key)}:[\n${lines.join('\n')}\n]${sep}`;
    }
    return `${compact(key)}:${compact(value)}${sep}`;
  });
  return Buffer.from(`{\n${parts.join('\n')}\n}\n`, 'utf8');
}

/** Pretty JSON (2-space indent) for small records such as manifests. */
export const prettyJson = (value) => Buffer.from(JSON.stringify(value, null, 2) + '\n', 'utf8');

/** Integer square root (floor) for non-negative safe integers via BigInt Newton iteration. */
export function isqrt(n) {
  if (n < 0) throw new Error('isqrt of negative');
  if (n < 2) return n;
  let x = BigInt(n);
  let y = (x + 1n) / 2n;
  while (y < x) {
    x = y;
    y = (x + BigInt(n) / x) / 2n;
  }
  return Number(x);
}

/** Ceiling of the Euclidean distance between two integer points (millimetres). */
export function ceilDistance(ax, ay, bx, by) {
  const dx = ax - bx;
  const dy = ay - by;
  const d2 = dx * dx + dy * dy;
  if (!Number.isSafeInteger(d2)) throw new Error('distance overflow');
  const r = isqrt(d2);
  return r * r === d2 ? r : r + 1;
}

/** Round half-even to 7 decimals of a rational value num/den (integers), returned as a decimal string. */
export function roundHalfEven7(num, den) {
  // value = num / den; scaled = value * 1e7 = num * 1e7 / den
  const N = BigInt(num) * 10000000n;
  const D = BigInt(den);
  const neg = (N < 0n) !== (D < 0n);
  const a = N < 0n ? -N : N;
  const b = D < 0n ? -D : D;
  let q = a / b;
  const r = a % b;
  const twice = 2n * r;
  if (twice > b || (twice === b && q % 2n === 1n)) q += 1n;
  const s = q.toString().padStart(8, '0');
  const intPart = s.slice(0, -7);
  const frac = s.slice(-7);
  const body = `${intPart}.${frac}`;
  return (neg && q !== 0n ? '-' : '') + body;
}
