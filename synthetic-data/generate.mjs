// G1 synthetic data generator g1-synth-gen 1.0.0 - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// Implements G1-SYNTH-SPEC-0.3. Usage:
//   node generate.mjs --out <new-dir> --fonts <cache-dir> --w-start <YYYY-MM-DDT00:00:00Z>
// The output directory must not exist. Generation uses no network, no clock and no randomness outside the DRBG.
import { mkdirSync, writeFileSync, readFileSync, existsSync, readdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { SEED } from './src/drbg.mjs';
import { LABEL, documentJson, prettyJson, sha256 } from './src/canonical.mjs';
import { buildGraph } from './src/geometry.mjs';
import { buildDestinations, destinationRecord, NAME_WORDS_VERSION } from './src/destinations.mjs';
import { buildQueries, MIX as QUERY_MIX } from './src/queries.mjs';
import { buildIndex, search, SEARCH_CONTRACT } from './src/search.mjs';
import { buildRouteCases, MIX as ROUTE_MIX, ROUTE_CONTRACT } from './src/routes.mjs';
import { anchors, qrFixtures, renderQr, QR_CONTRACT } from './src/qr.mjs';
import { buildSchedule } from './src/schedule.mjs';
import { labKey, trustStore } from './src/trust.mjs';
import { buildGeoJson, buildStyle, buildSprites, buildGlyphs, GLYPH_RANGES, FONTSTACK, STYLE_CONTRACT } from './src/mapres.mjs';
import { bundleFiles, manifestFor, signatureFor, zipBundle, trustFixtures, SPEC, TRUST_CONTRACT } from './src/bundle.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const require = createRequire(import.meta.url);
const GENERATOR = { name: 'g1-synth-gen', version: '1.0.0' };

function args() {
  const a = process.argv.slice(2);
  const get = (k) => { const i = a.indexOf(k); if (i < 0 || !a[i + 1]) throw new Error(`missing ${k}`); return a[i + 1]; };
  const wStart = get('--w-start');
  if (!/^\d{4}-\d{2}-\d{2}T00:00:00Z$/.test(wStart)) throw new Error('--w-start must be a UTC midnight like 2026-10-01T00:00:00Z');
  return { out: get('--out'), fonts: get('--fonts'), wStart };
}

function sourceDigest() {
  const files = ['generate.mjs', 'fetch-inputs.mjs', 'package.json', 'package-lock.json', 'inputs/fonts.json',
    ...readdirSync(join(HERE, 'src')).filter((f) => f.endsWith('.mjs')).sort().map((f) => `src/${f}`)];
  const list = files.map((f) => ({ path: f, sha256: sha256(readFileSync(join(HERE, f))) }));
  return { files: list, sha256: sha256(Buffer.from(list.map((x) => `${x.path}\t${x.sha256}\n`).join(''), 'utf8')) };
}

export async function generate({ out, fonts, wStart }) {
  if (existsSync(out)) throw new Error(`output exists: ${out}`);
  const wEnd = new Date(Date.parse(wStart) + 365 * 86400000).toISOString().replace('.000Z', 'Z');
  const fontSpec = JSON.parse(readFileSync(join(HERE, 'inputs/fonts.json'), 'utf8'));
  const inputs = {};
  for (const f of fontSpec.fonts) {
    for (const [file, sha] of [[f.file, f.sha256], [f.license_file, f.license_sha256]]) {
      const bytes = readFileSync(join(fonts, file));
      if (sha256(bytes) !== sha) throw new Error(`input sha256 mismatch: ${file}`);
      inputs[file] = bytes;
    }
  }
  const fontnik = require('fontnik');
  const qrPkg = JSON.parse(readFileSync(require.resolve('qrcode/package.json'), 'utf8'));
  const fontnikPkg = JSON.parse(readFileSync(require.resolve('fontnik/package.json'), 'utf8'));
  const fontnikBinary = join(dirname(require.resolve('fontnik')), 'prebuilds', `${process.platform}-${process.arch}`, 'fontnik.node');

  // core dataset
  const { nodes, edges } = buildGraph();
  const dests = buildDestinations(nodes);
  const destRecords = dests.map(destinationRecord);
  const queries = buildQueries(dests);
  const index = buildIndex(destRecords);
  const searchOracle = queries.map((q) => ({ id: q.id, ...search(q.text, index) }));
  const expectedByCategory = { exact_code: 'UNIQUE_MATCH', code_variants_case_space_hyphen: 'UNIQUE_MATCH', eastern_arabic_digits: 'UNIQUE_MATCH', ambiguous: 'AMBIGUOUS', no_match: 'NO_MATCH' };
  queries.forEach((q, i) => {
    const want = expectedByCategory[q.category];
    if (want && searchOracle[i].outcome !== want) throw new Error(`query ${q.id} (${q.category}) gave ${searchOracle[i].outcome}`);
  });
  const cases = buildRouteCases(nodes, edges, dests);
  const routeOracle = cases.map((c) => {
    if (c.expected.outcome === 'PATH') {
      if (!c.expected.unique) throw new Error(`route ${c.id} not unique`);
      return { id: c.id, class: c.cls, outcome: 'PATH', nodes: c.expected.nodes, length_mm: c.expected.length_mm };
    }
    return { id: c.id, class: c.cls, outcome: c.expected.outcome };
  });
  const anchorList = anchors(nodes);
  const schedule = buildSchedule(dests);
  const keys = { 1: labKey(1), 2: labKey(2), 3: labKey(3), 4: labKey(4) };

  // map resources
  const glyphs = await buildGlyphs(fontnik, [inputs['NotoSans[wdth,wght].ttf'], inputs['NotoSansArabic[wdth,wght].ttf']]);
  const sprites = buildSprites();
  const style = buildStyle('G1SYN-1.0.0');
  const ctx = { nodes, edges, dests, queries, cases, anchorList, schedule, style, glyphs, sprites,
    geojson: buildGeoJson(nodes, edges, dests, anchorList, 'G1SYN-1.0.0') };
  const withLicenses = (files) => ({ ...files, 'licenses/NotoSans-OFL.txt': inputs['NotoSans-OFL.txt'], 'licenses/NotoSansArabic-OFL.txt': inputs['NotoSansArabic-OFL.txt'] });

  // bundle 1.0.0 and fixtures
  const files100 = withLicenses(bundleFiles(ctx, 'G1SYN-1.0.0'));
  const manifest = manifestFor(files100, 'G1SYN-1.0.0', wStart, wEnd);
  const signature = signatureFor(keys[1], manifest);
  const bundleZip = zipBundle(files100, manifest, signature);
  const ctxFor = { ...ctx, glyphs: { ...glyphs }, sprites };
  const fixtureCtx = { ...ctxFor, geojson: ctx.geojson };
  const fixtures = trustFixtures({ ...fixtureCtx, bundleFilesWithLicenses: withLicenses }, keys, { files: files100, manifest, signature }, wStart, wEnd);

  // QR fixtures and images
  const qrfx = qrFixtures(keys[1], anchorList, 'G1SYN-1.0.0', wStart, wEnd);
  const outputs = {};
  for (const f of qrfx) {
    const { png, version, size } = renderQr(f.payload);
    f.png = `qr/${f.id}.png`;
    f.qr_version = version;
    f.qr_modules = size;
    f.error_correction = 'H';
    outputs[f.png] = png;
  }

  outputs['bundle/G1SYN-1.0.0.zip'] = bundleZip;
  outputs['bundle/MANIFEST.json'] = manifest;
  outputs['bundle/bundle_signature.json'] = signature;
  Object.assign(outputs, fixtures.files);
  outputs['fixtures/FIXTURES.json'] = documentJson({ label: LABEL, trust_contract: TRUST_CONTRACT, active_bundle: 'G1SYN-1.0.0', w_start: wStart, w_end: wEnd, fixtures: fixtures.index });
  outputs['oracle/search_oracle.json'] = documentJson({ label: LABEL, search_contract: SEARCH_CONTRACT, bundle_version: 'G1SYN-1.0.0', mix: QUERY_MIX, results: searchOracle });
  outputs['oracle/query_categories.json'] = documentJson({ label: LABEL, queries: queries.map((q) => ({ id: q.id, category: q.category, form: q.form })) });
  outputs['oracle/route_oracle.json'] = documentJson({ label: LABEL, route_contract: ROUTE_CONTRACT, bundle_version: 'G1SYN-1.0.0', mix: ROUTE_MIX, results: routeOracle });
  outputs['oracle/qr_fixtures.json'] = documentJson({ label: LABEL, qr_contract: QR_CONTRACT, bundle_version: 'G1SYN-1.0.0', rule: 'A QR identity never establishes pose, floor or arrival.', fixtures: qrfx });
  outputs['app/trust_store.json'] = prettyJson(trustStore(keys, wStart));

  const oracleFiles = ['oracle/search_oracle.json', 'oracle/route_oracle.json', 'oracle/qr_fixtures.json', 'fixtures/FIXTURES.json'];
  const record = {
    label: LABEL, spec: SPEC, generator: { ...GENERATOR, source: sourceDigest() },
    runtime: { node: process.versions.node, platform: process.platform, arch: process.arch },
    tools: { qrcode: qrPkg.version, fontnik: fontnikPkg.version, fontnik_binary: `prebuilds/${process.platform}-${process.arch}/fontnik.node`, fontnik_binary_sha256: sha256(readFileSync(fontnikBinary)) },
    inputs: { seed: SEED, w_start: wStart, w_end: wEnd, names: NAME_WORDS_VERSION, fonts: fontSpec.fonts.map((f) => ({ file: f.file, sha256: f.sha256, version: f.version })), fontstack: FONTSTACK, glyph_ranges: GLYPH_RANGES },
    contracts: { search: SEARCH_CONTRACT, route: ROUTE_CONTRACT, qr: QR_CONTRACT, style: STYLE_CONTRACT, trust: TRUST_CONTRACT },
    counts: { nodes: nodes.length, undirected_edges: edges.length, directed_edges: edges.length * 2, destinations: dests.length, queries: queries.length, routes: cases.length, anchors: anchorList.length, qr_fixtures: qrfx.length, schedule: schedule.length, trust_fixtures: fixtures.index.length },
    bundle: { version: 'G1SYN-1.0.0', file: 'bundle/G1SYN-1.0.0.zip', bundle_sha256: sha256(manifest), zip_sha256: sha256(bundleZip), files: JSON.parse(manifest.toString('utf8')).files.length },
    oracle_sha256: sha256(Buffer.from(oracleFiles.map((p) => `${p}\t${sha256(outputs[p])}\n`).join(''), 'utf8')),
    outputs: Object.keys(outputs).sort().map((p) => ({ path: p, bytes: outputs[p].length, sha256: sha256(outputs[p]) })),
  };
  outputs['GENERATION_RECORD.json'] = prettyJson(record);
  for (const [p, data] of Object.entries(outputs)) {
    mkdirSync(join(out, dirname(p)), { recursive: true });
    writeFileSync(join(out, p), data, { flag: 'wx' });
  }
  return record;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const record = await generate(args());
  console.log(JSON.stringify({ ok: true, bundle_sha256: record.bundle.bundle_sha256, zip_sha256: record.bundle.zip_sha256, oracle_sha256: record.oracle_sha256, outputs: record.outputs.length, generator_source_sha256: record.generator.source.sha256 }, null, 2));
}
