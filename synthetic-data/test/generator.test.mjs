// G1 synthetic data generator tests - NON-PRODUCTION / SYNTHETIC DATA ONLY.
import test from 'node:test';
import assert from 'node:assert/strict';
import { Stream, rawBytes } from '../src/drbg.mjs';
import { isqrt, ceilDistance, roundHalfEven7, documentJson } from '../src/canonical.mjs';
import { normalize, tokens, codeKey, search, buildIndex } from '../src/search.mjs';
import { encodeZip, decodeZip, encodePng } from '../src/binary.mjs';
import { labKey } from '../src/trust.mjs';
import { buildGraph, adjacency } from '../src/geometry.mjs';
import { route } from '../src/routes.mjs';

test('DRBG: SHA-256 counter stream, first values fixed', () => {
  const s = new Stream('test-domain');
  const a = s.next();
  const b = s.next();
  const t = new Stream('test-domain');
  assert.equal(t.next(), a);
  assert.equal(t.next(), b);
  assert.notEqual(a, b);
  assert.equal(rawBytes('test-domain', 2).toString('hex'), a.toString(16).padStart(16, '0') + b.toString(16).padStart(16, '0'));
});

test('randbelow stays in range and shuffle is a permutation', () => {
  const s = new Stream('range');
  for (let i = 0; i < 1000; i += 1) {
    const v = s.randbelow(7);
    assert.ok(v >= 0 && v < 7);
  }
  const arr = Array.from({ length: 50 }, (_, i) => i);
  const sh = new Stream('perm').shuffle(arr.slice());
  assert.deepEqual([...sh].sort((x, y) => x - y), arr);
  assert.throws(() => s.randbelow(0));
});

test('integer geometry helpers', () => {
  assert.equal(isqrt(916000000), 30265);
  assert.equal(ceilDistance(144000, 0, 140000, -30000), 30266);
  assert.equal(ceilDistance(0, 0, 0, 6000), 6000);
  assert.equal(roundHalfEven7(5, 100000000), '0.0000000'); // 0.00000005 -> half-even -> 0
  assert.equal(roundHalfEven7(15, 100000000), '0.0000002'); // 0.00000015 -> 0.0000002
  assert.equal(roundHalfEven7(-30000 * 10, 1105742727), '-0.0002713');
});

test('search normalization contract G1-SEARCH-1.0', () => {
  assert.equal(normalize('SB\u{0661}-F\u{0662}'), 'sb1-f2');
  assert.equal(normalize('\u{06F3}\u{06F0}'), '30');
  assert.equal(normalize('\u{0642}\u{064E}\u{0627}\u{0639}\u{064E}\u{0629}'), '\u{0642}\u{0627}\u{0639}\u{0629}');
  assert.equal(normalize('\u{0642}\u{0640}\u{0627}'), '\u{0642}\u{0627}');
  assert.equal(normalize('\u{FF33}\u{FF22}\u{FF11}'), 'sb1');
  assert.equal(normalize('RO14'), 'ro14'); // O is never folded to 0
  assert.deepEqual(tokens('  Lecture\u{00A0}Hall -  014 '), ['lecture', 'hall', '014']);
  assert.equal(codeKey('sb1 - f1 - r014'), 'SB1F1R014');
  assert.equal(codeKey('\u{200F}SB1\u{200E}-F1-R014'), 'SB1F1R014');
});

test('search outcomes', () => {
  const dests = [
    { id: 'D001', code: 'SB1-F1-R001', building: 'SB1', floor: 1, room_number: '001', name_en: 'Cafe 001', name_ar: '\u{0645}\u{0642}\u{0647}\u{0649} 001' },
    { id: 'D002', code: 'SB2-F1-R001', building: 'SB2', floor: 1, room_number: '001', name_en: 'Clinic 001', name_ar: '\u{0639}\u{064A}\u{0627}\u{062F}\u{0629} 001' },
  ];
  const idx = buildIndex(dests);
  assert.deepEqual(search('sb1 f1 r001', idx), { outcome: 'UNIQUE_MATCH', ids: ['D001'] });
  assert.deepEqual(search('R001', idx), { outcome: 'AMBIGUOUS', ids: ['D001', 'D002'] });
  assert.deepEqual(search('SB3-F1-R001', idx), { outcome: 'NO_MATCH', ids: [] });
  assert.deepEqual(search('Clinic \u{0660}\u{0660}\u{0661}', idx), { outcome: 'UNIQUE_MATCH', ids: ['D002'] });
  assert.deepEqual(search('   ', idx), { outcome: 'NO_MATCH', ids: [] });
});

test('stored ZIP and PNG writers', () => {
  const z = encodeZip([{ name: 'b.txt', data: Buffer.from('b') }, { name: 'a/x.json', data: Buffer.from('{}') }]);
  assert.deepEqual(decodeZip(z).map((e) => e.name), ['a/x.json', 'b.txt']);
  assert.throws(() => encodeZip([{ name: '../x', data: Buffer.alloc(0) }]));
  const png = encodePng(9, 2, Buffer.from([0, 255, 0, 255, 0, 255, 0, 255, 0, 255, 0, 255, 0, 255, 0, 255, 0, 255]), { bitDepth: 1 });
  assert.equal(png.subarray(1, 4).toString('ascii'), 'PNG');
});

test('lab keys are stable and distinct', () => {
  const ids = [1, 2, 3, 4].map((n) => labKey(n).keyId);
  assert.equal(new Set(ids).size, 4);
  assert.equal(labKey(1).keyId, ids[0]);
});

test('graph topology and route contract', () => {
  const { nodes, edges } = buildGraph();
  assert.equal(nodes.length, 3000);
  assert.equal(edges.length, 3000);
  const adj = adjacency(edges);
  const r = route(adj, 'N0001', 'N0002', false, []);
  assert.equal(r.outcome, 'PATH');
  assert.deepEqual(r.nodes, ['N0001', 'N0002']);
  assert.equal(r.length_mm, 6000);
  const wing = nodes.find((n) => n.wing && n.kind === 'destination');
  assert.equal(route(adj, 'N0001', wing.id, false, []).outcome, 'REJECT_UNREACHABLE');
});

test('document JSON is line-oriented with a final newline', () => {
  const b = documentJson({ a: 1, list: [{ x: 1 }, { x: 2 }] }).toString('utf8');
  assert.equal(b, '{\n"a":1,\n"list":[\n{"x":1},\n{"x":2}\n]\n}\n');
});
