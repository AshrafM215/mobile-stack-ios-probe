// G1 synthetic data generator - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// Deterministic random bit generator of G1-SYNTH-SPEC: SHA-256 over UTF-8 "G1-SYNTH|<seed>|<domain>|<counter>",
// first 8 bytes as a big-endian unsigned 64-bit integer. One stream per domain; the counter starts at 0 and
// increments by one per 64-bit draw. No Math.random, no time, no floating-point randomness.
import { createHash } from 'node:crypto';

export const SEED = 2026091401;
const TWO64 = 1n << 64n;

export class Stream {
  constructor(domain, seed = SEED) {
    this.domain = domain;
    this.seed = seed;
    this.counter = 0;
  }

  /** Next 64-bit value as BigInt. */
  next() {
    const digest = createHash('sha256').update(`G1-SYNTH|${this.seed}|${this.domain}|${this.counter}`, 'utf8').digest();
    this.counter += 1;
    return digest.readBigUInt64BE(0);
  }

  /** Uniform integer in [0, n) by rejection sampling below the largest multiple of n. */
  randbelow(n) {
    if (!Number.isSafeInteger(n) || n <= 0) throw new Error('randbelow: n must be a positive safe integer');
    const bn = BigInt(n);
    const limit = (TWO64 / bn) * bn;
    for (;;) {
      const x = this.next();
      if (x < limit) return Number(x % bn);
    }
  }

  /** In-place Fisher-Yates shuffle from the last index down to 1; returns the array. */
  shuffle(items) {
    for (let i = items.length - 1; i >= 1; i -= 1) {
      const j = this.randbelow(i + 1);
      const t = items[i];
      items[i] = items[j];
      items[j] = t;
    }
    return items;
  }

  /** k distinct items: shuffle a copy of the canonical list and take the first k. */
  sample(items, k) {
    if (k > items.length) throw new Error('sample: k exceeds population');
    return this.shuffle(items.slice()).slice(0, k);
  }
}

/** The first n raw 8-byte outputs of a domain stream, concatenated (used for synthetic lab key seeds). */
export function rawBytes(domain, count) {
  const s = new Stream(domain);
  const out = Buffer.alloc(count * 8);
  for (let i = 0; i < count; i += 1) out.writeBigUInt64BE(s.next(), i * 8);
  return out;
}
