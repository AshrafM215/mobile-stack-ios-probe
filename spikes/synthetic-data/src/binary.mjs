// G1 synthetic data generator - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// Platform-independent binary writers: PNG (stored deflate blocks, no compression) and ZIP (stored entries).
// Stored encoding keeps every byte reproducible on any platform; CRC-32 comes from node:zlib.
import { crc32 } from 'node:zlib';

const u32 = (n) => { const b = Buffer.alloc(4); b.writeUInt32BE(n >>> 0); return b; };

function adler32(buf) {
  let a = 1;
  let b = 0;
  for (let i = 0; i < buf.length; i += 1) {
    a = (a + buf[i]) % 65521;
    b = (b + a) % 65521;
  }
  return ((b << 16) | a) >>> 0;
}

/** zlib stream with stored (uncompressed) deflate blocks. */
export function zlibStored(raw) {
  const blocks = [Buffer.from([0x78, 0x01])];
  for (let off = 0; off < raw.length || off === 0; off += 65535) {
    const chunk = raw.subarray(off, Math.min(raw.length, off + 65535));
    const final = off + 65535 >= raw.length ? 1 : 0;
    const hdr = Buffer.alloc(5);
    hdr[0] = final;
    hdr.writeUInt16LE(chunk.length, 1);
    hdr.writeUInt16LE((~chunk.length) & 0xffff, 3);
    blocks.push(hdr, chunk);
    if (raw.length === 0) break;
  }
  blocks.push(u32(adler32(raw)));
  return Buffer.concat(blocks);
}

function chunk(type, data) {
  const t = Buffer.from(type, 'ascii');
  return Buffer.concat([u32(data.length), t, data, u32(crc32(Buffer.concat([t, data])))]);
}

/**
 * PNG writer. pixels: Buffer of width*height*channels bytes (one byte per sample, 0..255); colorType 0 (gray, 1 channel)
 * or 6 (RGBA, 4 channels). bitDepth 8, or 1 for gray (samples < 128 -> 0, else 1). Filter 0 on every row.
 * text: optional { key: value } tEXt chunks (Latin-1).
 */
export function encodePng(width, height, pixels, { colorType = 0, bitDepth = 8, text = {} } = {}) {
  const channels = colorType === 6 ? 4 : 1;
  if (pixels.length !== width * height * channels) throw new Error('pixel buffer size');
  if (bitDepth !== 8 && !(bitDepth === 1 && colorType === 0)) throw new Error('unsupported bit depth');
  const rowBytes = bitDepth === 1 ? Math.ceil(width / 8) : width * channels;
  const raw = Buffer.alloc((rowBytes + 1) * height);
  for (let y = 0; y < height; y += 1) {
    const base = y * (rowBytes + 1);
    raw[base] = 0;
    if (bitDepth === 8) {
      pixels.copy(raw, base + 1, y * width * channels, (y + 1) * width * channels);
    } else {
      for (let x = 0; x < width; x += 1) {
        if (pixels[y * width + x] >= 128) raw[base + 1 + (x >> 3)] |= 0x80 >> (x & 7);
      }
    }
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = bitDepth;
  ihdr[9] = colorType;
  const parts = [Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', ihdr)];
  for (const [k, v] of Object.entries(text)) parts.push(chunk('tEXt', Buffer.concat([Buffer.from(k, 'latin1'), Buffer.from([0]), Buffer.from(v, 'latin1')])));
  parts.push(chunk('IDAT', zlibStored(raw)), chunk('IEND', Buffer.alloc(0)));
  return Buffer.concat(parts);
}

/**
 * Deterministic ZIP (method 0 = stored only): entries sorted by name, UTF-8 names (flag bit 11), fixed DOS date
 * 1980-01-01 00:00, no extra fields, no comments, no data descriptors, no ZIP64.
 */
export function encodeZip(entries) {
  const sorted = [...entries].sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
  const local = [];
  const central = [];
  let offset = 0;
  const names = new Set();
  for (const { name, data } of sorted) {
    if (names.has(name) || name.startsWith('/') || name.split('/').includes('..') || name.includes('\\')) throw new Error('bad zip name ' + name);
    names.add(name);
    const nameBuf = Buffer.from(name, 'utf8');
    const crc = crc32(data) >>> 0;
    const lh = Buffer.alloc(30);
    lh.writeUInt32LE(0x04034b50, 0);
    lh.writeUInt16LE(10, 4); // version needed
    lh.writeUInt16LE(0x0800, 6); // UTF-8 names
    lh.writeUInt16LE(0, 8); // stored
    lh.writeUInt16LE(0, 10); // time
    lh.writeUInt16LE(0x0021, 12); // date 1980-01-01
    lh.writeUInt32LE(crc, 14);
    lh.writeUInt32LE(data.length, 18);
    lh.writeUInt32LE(data.length, 22);
    lh.writeUInt16LE(nameBuf.length, 26);
    lh.writeUInt16LE(0, 28);
    local.push(lh, nameBuf, data);
    const ch = Buffer.alloc(46);
    ch.writeUInt32LE(0x02014b50, 0);
    ch.writeUInt16LE(20, 4); // version made by
    ch.writeUInt16LE(10, 6);
    ch.writeUInt16LE(0x0800, 8);
    ch.writeUInt16LE(0, 10);
    ch.writeUInt16LE(0, 12);
    ch.writeUInt16LE(0x0021, 14);
    ch.writeUInt32LE(crc, 16);
    ch.writeUInt32LE(data.length, 20);
    ch.writeUInt32LE(data.length, 24);
    ch.writeUInt16LE(nameBuf.length, 28);
    ch.writeUInt32LE(offset, 42);
    central.push(ch, nameBuf);
    offset += 30 + nameBuf.length + data.length;
  }
  const cd = Buffer.concat(central);
  const eocd = Buffer.alloc(22);
  eocd.writeUInt32LE(0x06054b50, 0);
  eocd.writeUInt16LE(sorted.length, 8);
  eocd.writeUInt16LE(sorted.length, 10);
  eocd.writeUInt32LE(cd.length, 12);
  eocd.writeUInt32LE(offset, 16);
  return Buffer.concat([...local, cd, eocd]);
}

/** Minimal reader for the stored ZIPs written above (used by tests and the independent checker). */
export function decodeZip(buf) {
  const eocdAt = buf.length - 22;
  if (buf.readUInt32LE(eocdAt) !== 0x06054b50) throw new Error('no EOCD');
  const count = buf.readUInt16LE(eocdAt + 10);
  let p = buf.readUInt32LE(eocdAt + 16);
  const out = [];
  for (let i = 0; i < count; i += 1) {
    if (buf.readUInt32LE(p) !== 0x02014b50) throw new Error('bad central header');
    const method = buf.readUInt16LE(p + 10);
    const size = buf.readUInt32LE(p + 20);
    const nameLen = buf.readUInt16LE(p + 28);
    const extraLen = buf.readUInt16LE(p + 30);
    const commentLen = buf.readUInt16LE(p + 32);
    const lho = buf.readUInt32LE(p + 42);
    const name = buf.subarray(p + 46, p + 46 + nameLen).toString('utf8');
    if (method !== 0) throw new Error('compressed entry');
    const lNameLen = buf.readUInt16LE(lho + 26);
    const lExtra = buf.readUInt16LE(lho + 28);
    const data = buf.subarray(lho + 30 + lNameLen + lExtra, lho + 30 + lNameLen + lExtra + size);
    out.push({ name, data: Buffer.from(data) });
    p += 46 + nameLen + extraLen + commentLen;
  }
  return out;
}
