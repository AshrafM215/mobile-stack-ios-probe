// Candidate B (React Native) unit tests - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// The TypeScript implementations of G1-SEARCH-1.0, G1-ROUTE-1.0, G1-ROUTE-STEPS-1.0 and G1-STYLE-1.0 against the
// generated oracle (spikes/synthetic-data/out), plus strings, lab-hook, envelope and boundary-encoding checks.
import { decodeBase64, decodeBase64Portable, encodeBase64, encodeBase64Portable } from '../src/core/base64';
import { FormatError, parseDestinations, parseGraph, parseQueries, parseRouteCases, parseSchedule } from '../src/core/bundleData';
import { crc32 } from '../src/core/crc32';
import { qrText, scheduleItem, stepText, trustText } from '../src/core/format';
import { RouteGraph } from '../src/core/route';
import { SearchIndex } from '../src/core/search';
import { routeSteps } from '../src/core/steps';
import { Strings } from '../src/core/strings';
import { layerFor, splitStyle } from '../src/core/style';
import { decodeUtf8 } from '../src/core/utf8';
import { decodeEnvelope, LAB_COMMANDS, UI_SCRIPT } from '../src/lab';

jest.mock('g1-native', () => ({ nowNanos: () => 0, mark: () => undefined, NativeG1: {} }));

// Node built-ins of the Jest environment, typed locally (the app tsconfig has React Native globals, not Node's).
declare const require: (id: string) => any;
declare const __dirname: string;
type Bytes = Uint8Array & { readUInt16LE(o: number): number; readUInt32LE(o: number): number; toString(enc: string): string };
const fs = require('fs');
const path = require('path');
const Buffer: { from(v: Uint8Array | string, enc?: string): Bytes & { toString(enc?: string): string } } = require('buffer').Buffer;

const ROOT = path.resolve(__dirname, '..');
const OUT = path.resolve(ROOT, '../synthetic-data/out');
const CONTRACT = path.resolve(ROOT, '../contract');

/** Entries of a stored (method 0) ZIP, enough for the synthetic bundle. */
function storedZip(z: Bytes): Map<string, Bytes> {
  const eocd = z.length - 22;
  const count = z.readUInt16LE(eocd + 10);
  let p = z.readUInt32LE(eocd + 16);
  const out = new Map<string, Bytes>();
  for (let i = 0; i < count; i++) {
    const size = z.readUInt32LE(p + 24);
    const nameLen = z.readUInt16LE(p + 28);
    const local = z.readUInt32LE(p + 42);
    const name = (z.subarray(p + 46, p + 46 + nameLen) as Bytes).toString('utf8');
    const lName = z.readUInt16LE(local + 26);
    const start = local + 30 + lName;
    out.set(name, z.subarray(start, start + size) as Bytes);
    p += 46 + nameLen;
  }
  return out;
}

const bundle = storedZip(fs.readFileSync(path.join(OUT, 'bundle/G1SYN-1.0.0.zip')));
const text = (name: string): string => bundle.get(name)!.toString('utf8');
const destinations = parseDestinations(text('destinations.json'));
const graphData = parseGraph(text('graph.json'));
const graph = new RouteGraph(graphData);
const nodes = new Map(graphData.nodes.map((n) => [n.id, n]));
const byId = new Map(destinations.map((d) => [d.id, d]));
const readJson = (file: string): any => JSON.parse(fs.readFileSync(file, 'utf8'));

test('G1-SEARCH-1.0 agrees with the oracle on all 500 queries', () => {
  const index = new SearchIndex(destinations);
  const queries = parseQueries(text('query_corpus.json'));
  const oracle = readJson(path.join(OUT, 'oracle/search_oracle.json')).results;
  expect(queries.length).toBe(500);
  queries.forEach((q, i) => {
    const r = index.search(q.text);
    expect({ id: q.id, outcome: r.outcome, ids: r.ids }).toEqual({ id: q.id, outcome: oracle[i].outcome, ids: oracle[i].ids });
  });
});

test('G1-ROUTE-1.0 and G1-ROUTE-STEPS-1.0 agree with the oracle on all 30 cases', () => {
  const cases = parseRouteCases(text('route_cases.json'));
  const oracle = readJson(path.join(OUT, 'oracle/route_oracle.json')).results;
  expect(cases.length).toBe(30);
  cases.forEach((c, i) => {
    const d = byId.get(c.destination)!;
    const r = graph.route(c.origin, d.node, c.stepFree, c.blocked);
    expect({ id: c.id, outcome: r.outcome }).toEqual({ id: c.id, outcome: oracle[i].outcome });
    if (r.outcome === 'PATH') {
      expect(r.nodes).toEqual(oracle[i].nodes);
      expect(r.lengthMm).toBe(oracle[i].length_mm);
      const { steps, summary } = routeSteps(graph, nodes, r.nodes, d);
      expect(steps).toEqual(oracle[i].steps);
      expect(summary).toEqual(oracle[i].summary);
    }
  });
});

test('parsers reject malformed input with FormatError only', () => {
  const inputs = ['', '{', '[]', '{"nodes":{}}', '{"nodes":[],"edges":[{"id":1}]}', '{"nodes":[{"id":"N1"}],"edges":[]}',
    '{"nodes":[{"id":"N1","kind":"corridor","x_mm":0,"y_mm":0},{"id":"N1","kind":"corridor","x_mm":0,"y_mm":0}],"edges":[]}',
    '{"nodes":[{"id":"N1","kind":"corridor","x_mm":0.5,"y_mm":0}],"edges":[]}'];
  for (const input of inputs) expect(() => parseGraph(input)).toThrow(FormatError);
  expect(() => parseDestinations('{"destinations":[{"id":"D1"}]}')).toThrow(FormatError);
  expect(() => parseSchedule('{"entries":[{"code":1}]}')).toThrow(FormatError);
});

test('G1-STYLE-1.0 transforms for the declarative binding', () => {
  const st = splitStyle(text('style.json'), 'file:///data/g1/v-1');
  const full = JSON.parse(text('style.json'));
  expect(st.mapStyle.glyphs).toBe('file:///data/g1/v-1/glyphs/{fontstack}/{range}.pbf');
  expect(st.mapStyle.sprite).toBe('file:///data/g1/v-1/sprites/sprite');
  expect((st.mapStyle.sources as any).synthetic.data).toBe('file:///data/g1/v-1/geometry.geojson');
  expect((st.mapStyle.sources as any).route).toBeUndefined();
  // static + runtime layers = the style's layers, in the same order (each runtime layer is inserted above its predecessor)
  const staticIds = (st.mapStyle.layers as any[]).map((l) => l.id);
  const order = [...staticIds];
  for (const r of st.runtimeLayers) order.splice(order.indexOf(r.afterId) + 1, 0, r.def.id as string);
  expect(order).toEqual(full.layers.map((l: any) => l.id));
  expect(st.runtimeLayers.map((r) => r.def.id)).toEqual(full.metadata.runtime_floor_layers);
  expect([...st.languageLayers]).toEqual(['room-labels']);
  const byLayer = new Map(st.runtimeLayers.map((r) => [r.def.id as string, r.def]));
  expect(layerFor(byLayer.get('rooms')!, 2, 'en', st.languageLayers).filter).toEqual(['all', ['==', ['get', 'kind'], 'room'], ['==', ['get', 'floor'], 2]]);
  expect(layerFor(byLayer.get('route')!, 2, 'en', st.languageLayers).filter).toEqual(['any', ['!', ['has', 'floor']], ['==', ['get', 'floor'], 2]]);
  const labels = layerFor(byLayer.get('room-labels')!, 3, 'en', st.languageLayers);
  expect((labels.layout as any)['text-field']).toEqual(['get', 'name_en']);
  expect((labels.layout as any)['text-font']).toEqual(['G1Sans']);
  expect((layerFor(byLayer.get('room-labels')!, 1, 'ar', st.languageLayers).layout as any)['text-field']).toEqual(['get', 'name_ar']);
  expect(st.center).toEqual(full.center);
  expect(st.zoom).toBe(full.zoom);
});

test('strings: same keys in both languages, copies of the contract strings, every referenced key exists', () => {
  const enText = fs.readFileSync(path.join(ROOT, 'src/strings/en.json'), 'utf8');
  const arText = fs.readFileSync(path.join(ROOT, 'src/strings/ar.json'), 'utf8');
  expect(enText).toBe(fs.readFileSync(path.join(CONTRACT, 'strings/en.json'), 'utf8'));
  expect(arText).toBe(fs.readFileSync(path.join(CONTRACT, 'strings/ar.json'), 'utf8'));
  const en = new Strings('en', JSON.parse(enText));
  const ar = new Strings('ar', JSON.parse(arText));
  expect(new Set(en.keys())).toEqual(new Set(ar.keys()));
  expect(ar.rtl).toBe(true);
  expect(en.rtl).toBe(false);
  const sources = ['App.tsx', 'src/state.ts', 'src/ui/screens.tsx', 'src/ui/MapPanel.tsx', 'src/core/format.ts']
    .map((f) => fs.readFileSync(path.join(ROOT, f), 'utf8'))
    .join('\n');
  const referenced = new Set([...sources.matchAll(/\bs\.t\('([a-z0-9_.]+)'/g)].map((m) => m[1]));
  expect(referenced.size).toBeGreaterThan(40);
  for (const k of referenced) {
    expect({ k, en: en.has(k), ar: ar.has(k) }).toEqual({ k, en: true, ar: true });
  }
  for (const s of [en, ar]) {
    expect(stepText(s, { kind: 'walk', m: 12 })).not.toMatch(/^\[/);
    expect(trustText(s, null)).not.toMatch(/^\[/);
    for (const code of ['IDENTITY_VALID', 'REJECT_EXPIRED', 'REJECT_NO_BUNDLE', 'CAMERA_UNAVAILABLE', 'PERMISSION_DENIED', 'CANCELLED']) {
      expect(qrText(s, { outcome: code, anchor: 'A01', building: 'SB1', floor: 1, kind: 'stairs' })).not.toContain('[');
    }
    for (let d = 1; d <= 7; d++) expect(s.has(`day.${d}`)).toBe(true);
  }
  const schedule = parseSchedule(text('schedule.json'));
  expect(scheduleItem(en, schedule[0])).toContain('Tuesday');
});

test('lab hooks: registered commands, UI script and envelope decoder match the contract', () => {
  const contract = readJson(path.join(CONTRACT, 'contract.json'));
  expect(new Set(LAB_COMMANDS)).toEqual(new Set(Object.keys(contract.lab_hooks.commands)));
  expect(UI_SCRIPT).toEqual(contract.ui_session_script.keyframes);
  expect(decodeEnvelope('{"method":"nav.home","args":{}}')).toBe('ACCEPT');
  expect(decodeEnvelope('{"method":"shell","args":{}}')).toBe('REJECT_METHOD');
  expect(decodeEnvelope('{"method":"nav.home","args":[]}')).toBe('REJECT_ARGS');
  expect(decodeEnvelope('{"method":"nav.home","args":{},"x":1}')).toBe('REJECT_SHAPE');
  expect(decodeEnvelope('[]')).toBe('REJECT_SHAPE');
  expect(decodeEnvelope('{')).toBe('REJECT_JSON');
  expect(decodeEnvelope('x'.repeat(20000))).toBe('REJECT_SIZE');
});

test('boundary encodings: CRC-32 check value, base64 engine and portable paths, UTF-8 replacement', () => {
  expect(crc32(new Uint8Array(Buffer.from('123456789')))).toBe(0xcbf43926);
  const bytes = new Uint8Array(70000).map((_, i) => (i * 131 + 7) & 0xff);
  for (const n of [0, 1, 2, 3, 64, 4096, 65536, 65537]) {
    const b = bytes.subarray(0, n);
    const e = encodeBase64(b);
    expect(e).toBe(Buffer.from(b).toString('base64'));
    expect(encodeBase64Portable(b)).toBe(e);
    expect(Buffer.from(decodeBase64(e))).toEqual(Buffer.from(b));
    expect(Buffer.from(decodeBase64Portable(e))).toEqual(Buffer.from(b));
  }
  expect(() => decodeBase64Portable('ab$d')).toThrow();
  expect(() => decodeBase64('ab$d')).toThrow();
  expect(decodeUtf8(new Uint8Array([0x61, 0xd9, 0x85, 0xe2, 0x82, 0xac, 0xf0, 0x9f, 0x98, 0x80]))).toBe('a\u{645}\u{20ac}\u{1f600}');
  expect(decodeUtf8(new Uint8Array([0x61, 0xff, 0x62]))).toBe('a\u{fffd}b');
  expect(decodeUtf8(new Uint8Array([0xe2, 0x82]))).toBe('\u{fffd}');
  expect(decodeUtf8(new Uint8Array([0xc0, 0x80]))).toBe('\u{fffd}\u{fffd}');
  expect(decodeUtf8(new Uint8Array([0xed, 0xa0, 0x80]))).toBe('\u{fffd}\u{fffd}\u{fffd}');
});
