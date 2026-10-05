// Candidate B (React Native) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// UTF-8 decoding with U+FFFD for malformed sequences (fuzz inputs are arbitrary bytes); no dependency on TextDecoder.

export function decodeUtf8(b: Uint8Array): string {
  const out: number[] = [];
  let i = 0;
  while (i < b.length) {
    const c = b[i];
    if (c < 0x80) {
      out.push(c);
      i++;
      continue;
    }
    let need = 0;
    let cp = 0;
    let min = 0;
    if (c >= 0xc2 && c <= 0xdf) {
      need = 1;
      cp = c & 0x1f;
      min = 0x80;
    } else if (c >= 0xe0 && c <= 0xef) {
      need = 2;
      cp = c & 0x0f;
      min = 0x800;
    } else if (c >= 0xf0 && c <= 0xf4) {
      need = 3;
      cp = c & 0x07;
      min = 0x10000;
    } else {
      out.push(0xfffd);
      i++;
      continue;
    }
    let j = 1;
    for (; j <= need && i + j < b.length; j++) {
      const d = b[i + j];
      if ((d & 0xc0) !== 0x80) break;
      cp = (cp << 6) | (d & 0x3f);
    }
    if (j <= need) {
      // truncated sequence: the lead byte and the continuation bytes seen so far become one U+FFFD
      out.push(0xfffd);
      i += j;
      continue;
    }
    if (cp < min || cp > 0x10ffff || (cp >= 0xd800 && cp <= 0xdfff)) {
      // overlong, surrogate or out of range: the lead byte becomes U+FFFD, the continuation bytes follow as stray bytes
      out.push(0xfffd);
      i++;
      continue;
    }
    out.push(cp);
    i += need + 1;
  }
  let s = '';
  for (let k = 0; k < out.length; k += 4096) s += String.fromCodePoint(...out.slice(k, k + 4096));
  return s;
}
