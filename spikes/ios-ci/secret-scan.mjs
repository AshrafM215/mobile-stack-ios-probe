#!/usr/bin/env node
// Static secret scan of a release artifact - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// Searches every file of a directory (an unpacked app bundle) or every entry a caller hands over (the entries of an
// APK) for the patterns of secret-patterns.json and for the private halves of the synthetic lab keys. The iOS job runs
// it on the unsigned device app; the harness runs it on the entries of the release APK. It lives beside the job scripts
// so that the digest of the job scripts covers it. The scan states
// facts: which pattern or key matched in which file at which offset. It never prints what matched (a record of the
// scan must not become a copy of a secret): a hit carries the length and the SHA-256 of the matched bytes only.
// Whether a hit is a defect is decided by the registered rule of the inspection and by the security review.
//
//   node ios-ci/secret-scan.mjs <directory> [--out FILE]
//
// Text patterns are applied to the bytes of a file read as ISO 8859-1 (one character per byte, so an offset is a byte
// offset), and a second time to the bytes without NUL (ASCII text stored as UTF-16; such a hit carries no offset).
// Key material is searched as bytes: each private seed raw, in its PKCS#8 encoding, and as hexadecimal (both cases),
// base64 and base64url text of both, in ISO 8859-1 and in UTF-16LE.
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
export const SCAN_SCHEMA = 'G1-SECRET-SCAN-1.0';
const PKCS8_ED25519_PREFIX = Buffer.from('302e020100300506032b657004220420', 'hex');
const LAB_KEYS = 4;
const MAX_HITS_PER_FILE_AND_ID = 20;

const sha256 = bytes => crypto.createHash('sha256').update(bytes).digest('hex');

export function loadPatterns(file = path.join(HERE, 'secret-patterns.json')) {
  const bytes = fs.readFileSync(file);
  const table = JSON.parse(bytes.toString('utf8'));
  if (table.schema !== 'G1-SECRET-PATTERNS-1.0' || !Array.isArray(table.patterns) || !table.patterns.length) throw new Error('secret patterns: not a pattern table');
  return { sha256: sha256(bytes), patterns: table.patterns.map(p => ({ id: p.id, regex: new RegExp(p.regex, `g${p.flags ?? ''}`) })) };
}

/** The byte strings that would show a private half of a lab key in an artifact: [{id, bytes}]. */
export async function privateMaterial(spikesRoot = path.resolve(HERE, '..')) {
  const { rawBytes } = await import(pathToFileURL(path.join(spikesRoot, 'synthetic-data', 'src', 'drbg.mjs')).href);
  const needles = [];
  for (let n = 1; n <= LAB_KEYS; n++) {
    const seed = Buffer.from(rawBytes(`lab-key-${n}`, 4));
    if (seed.length !== 32) throw new Error('lab key seed: 32 bytes expected');
    const pkcs8 = Buffer.concat([PKCS8_ED25519_PREFIX, seed]);
    const forms = [['raw', seed], ['pkcs8', pkcs8]];
    for (const [name, value] of [['seed', seed], ['pkcs8', pkcs8]]) {
      const b64 = value.toString('base64');
      for (const [encoding, text] of [['hex', value.toString('hex')], ['HEX', value.toString('hex').toUpperCase()], ['base64', b64.replace(/=+$/, '')],
        ['base64url', b64.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')]]) {
        forms.push([`${name}-${encoding}`, Buffer.from(text, 'latin1')], [`${name}-${encoding}-utf16le`, Buffer.from(text, 'utf16le')]);
      }
    }
    const seen = new Set();
    for (const [form, bytes] of forms) {
      const key = bytes.toString('hex');
      if (seen.has(key)) continue; // base64 and base64url of a value without '+' or '/' are the same text
      seen.add(key);
      needles.push({ id: `lab-key-${n}.${form}`, bytes });
    }
  }
  return needles;
}

/** Hits of one file: [{kind, id, offset|null, length, match_sha256}]. */
export function scanBuffer(buf, { patterns, needles }) {
  const hits = [];
  const add = (kind, id, offset, matched) => {
    if (hits.filter(h => h.id === id).length < MAX_HITS_PER_FILE_AND_ID) hits.push({ kind, id, offset, length: matched.length, match_sha256: sha256(matched) });
  };
  for (const needle of needles) {
    for (let at = buf.indexOf(needle.bytes); at !== -1; at = buf.indexOf(needle.bytes, at + 1)) add('private-material', needle.id, at, needle.bytes);
  }
  const text = buf.toString('latin1');
  const stripped = text.includes('\0') ? text.replace(/\0/g, '') : null;
  for (const pattern of patterns) {
    for (const [body, withOffset] of [[text, true], [stripped, false]]) {
      if (body === null) continue;
      pattern.regex.lastIndex = 0;
      for (let m = pattern.regex.exec(body); m; m = pattern.regex.exec(body)) {
        if (m[0].length === 0) pattern.regex.lastIndex += 1;
        const matched = Buffer.from(m[0], 'latin1');
        // a match of the plain pass is found again in the stripped pass of the same file: recorded once
        if (!withOffset && hits.some(h => h.id === pattern.id && h.match_sha256 === sha256(matched))) continue;
        add('pattern', pattern.id, withOffset ? m.index : null, matched);
      }
    }
  }
  return hits;
}

/** Scans named byte strings. entries: iterable of {name, bytes}. Returns the scan record without its header. */
export function scanEntries(entries, { patterns, needles }) {
  let files = 0, bytes = 0;
  const hits = [];
  for (const entry of entries) {
    files += 1;
    bytes += entry.bytes.length;
    for (const hit of scanBuffer(entry.bytes, { patterns, needles })) hits.push({ file: entry.name, ...hit });
  }
  hits.sort((a, b) => (a.file < b.file ? -1 : a.file > b.file ? 1 : (a.offset ?? -1) - (b.offset ?? -1) || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0)));
  return { files, bytes, hits };
}

function* filesOf(root) {
  const walk = function* (rel) {
    const dir = path.join(root, ...rel.split('/').filter(Boolean));
    for (const entry of fs.readdirSync(dir, { withFileTypes: true }).sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0))) {
      const child = rel ? `${rel}/${entry.name}` : entry.name;
      if (entry.isDirectory()) yield* walk(child);
      else if (entry.isFile()) yield { name: child, bytes: fs.readFileSync(path.join(dir, entry.name)) };
      // a symbolic link names a file that the walk reads at its own place, or a file outside the artifact
    }
  };
  yield* walk('');
}

/** The complete record of a scan. what: {directory} or {entries, label}. */
export async function scan({ directory = null, entries = null, label = null, spikesRoot = undefined }) {
  const table = loadPatterns();
  const needles = await privateMaterial(spikesRoot);
  const result = scanEntries(directory ? filesOf(directory) : entries, { patterns: table.patterns, needles });
  return { schema: SCAN_SCHEMA, classification: 'NON-PRODUCTION / SYNTHETIC DATA ONLY', artifact: label ?? path.basename(directory),
    patterns_sha256: table.sha256, patterns: table.patterns.map(p => p.id), private_material_forms: needles.length, ...result,
    pattern_hits: result.hits.filter(h => h.kind === 'pattern').length, private_material_hits: result.hits.filter(h => h.kind === 'private-material').length };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [directory, flag, out] = process.argv.slice(2);
  if (!directory || (flag && flag !== '--out') || (flag && !out)) {
    process.stderr.write('usage: secret-scan.mjs <directory> [--out FILE]\n');
    process.exit(2);
  }
  const record = await scan({ directory });
  const text = JSON.stringify(record, null, 1) + '\n';
  if (out) fs.writeFileSync(out, text);
  else process.stdout.write(text);
}
