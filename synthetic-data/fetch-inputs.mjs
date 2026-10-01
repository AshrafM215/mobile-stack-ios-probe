// G1 synthetic data generator - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// Separate network step: fetch the pinned font inputs and their licences into a cache directory and verify SHA-256.
// Usage: node fetch-inputs.mjs <cache-dir>
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { join } from 'node:path';

const dir = process.argv[2];
if (!dir) throw new Error('usage: node fetch-inputs.mjs <cache-dir>');
mkdirSync(dir, { recursive: true });
const spec = JSON.parse(readFileSync(new URL('./inputs/fonts.json', import.meta.url), 'utf8'));
for (const f of spec.fonts) {
  for (const [url, file, sha] of [[f.url, f.file, f.sha256], [f.license_url, f.license_file, f.license_sha256]]) {
    const target = join(dir, file);
    if (!existsSync(target)) {
      const res = await fetch(url);
      if (!res.ok) throw new Error(`fetch failed ${res.status} ${url}`);
      writeFileSync(target, Buffer.from(await res.arrayBuffer()));
    }
    const got = createHash('sha256').update(readFileSync(target)).digest('hex');
    if (got !== sha) throw new Error(`sha256 mismatch for ${file}: ${got}`);
    console.log(`ok ${file} ${got}`);
  }
}
