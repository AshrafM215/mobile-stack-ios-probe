// G1 synthetic data generator - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// Geometry and topology of G1-SYNTH-SPEC: 3 buildings x 3 floors, 3000 nodes, 3000 undirected / 6000 directed edges.
import { Stream } from './drbg.mjs';
import { ceilDistance } from './canonical.mjs';

export const BUILDINGS = [1, 2, 3];
export const FLOORS = [1, 2, 3];
export const FLOOR_HEIGHT_MM = 3500;
export const STAIRS_MM = 3 * FLOOR_HEIGHT_MM; // 10500
export const ELEVATOR_MM = 30000; // fixed wait-equivalent
const X0 = { 1: 0, 2: 200000, 3: 400000 };
const GRID = 6000;
const FULL_293 = new Set(['SB1F1', 'SB1F2', 'SB1F3', 'SB2F1']);
const WING_FLOORS = new Set(['SB1F1', 'SB1F2', 'SB1F3', 'SB2F2', 'SB2F3', 'SB3F1', 'SB3F2', 'SB3F3']);
const DEST_PER_FLOOR = (key) => (key === 'SB3F2' || key === 'SB3F3' ? 29 : 30);

export const floorKey = (b, f) => `SB${b}F${f}`;

function corridorPoints(b, f) {
  const key = floorKey(b, f);
  const lastRowOfColumn24 = FULL_293.has(key) ? 4 : 3; // 293 omits (24, 5..11); 292 omits (24, 4..11)
  const pts = [];
  for (let c = 0; c <= 24; c += 1) {
    for (let r = 0; r <= 11; r += 1) {
      if (c === 24 && r > lastRowOfColumn24) continue;
      pts.push({ c, r });
    }
  }
  return pts; // (c, r) order
}

/**
 * Build the complete graph. Returns { nodes, edges } with canonical ids.
 * nodes: { id, kind, building, floor, x_mm, y_mm, c?, r?, k?, dest_index? }
 * edges (undirected, canonical order by (min node id, max node id)): { id, a, b, kind, length_mm, step_free }
 */
export function buildGraph() {
  const nodes = [];
  const pending = []; // undirected edges by node object reference
  const byKey = new Map(); // `${b}|${f}|c|r` -> node
  const destSlots = new Map(); // floorKey -> chosen slots in (c, r) order
  const nodeOf = (b, f, c, r) => byKey.get(`${b}|${f}|${c}|${r}`);

  for (const b of BUILDINGS) {
    for (const f of FLOORS) {
      const key = floorKey(b, f);
      const x0 = X0[b];
      // main corridor nodes in (c, r) order
      for (const { c, r } of corridorPoints(b, f)) {
        const n = { kind: 'corridor', building: b, floor: f, x_mm: x0 + GRID * c, y_mm: GRID * r, c, r };
        nodes.push(n);
        byKey.set(`${b}|${f}|${c}|${r}`, n);
      }
      // destination slots: eligible (c, r) with c = 0..23, r = 1..11 in (c, r) order, shuffled, first 30 (29)
      const eligible = [];
      for (let c = 0; c <= 23; c += 1) for (let r = 1; r <= 11; r += 1) eligible.push({ c, r });
      const stream = new Stream(`dest-slots|${key}`);
      const chosen = stream.shuffle(eligible.slice()).slice(0, DEST_PER_FLOOR(key));
      chosen.sort((p, q) => (p.c - q.c) || (p.r - q.r));
      destSlots.set(key, chosen);
      for (const { c, r } of chosen) {
        const slot = nodeOf(b, f, c, r);
        const d = { kind: 'destination', building: b, floor: f, x_mm: slot.x_mm + 3000, y_mm: slot.y_mm, slot_c: c, slot_r: r, wing: false };
        nodes.push(d);
        pending.push({ a: slot, b: d, kind: 'spur' });
      }
      // wing (isolated tree) on the listed floors
      if (WING_FLOORS.has(key)) {
        const wing = [];
        for (let k = 0; k <= 5; k += 1) {
          const w = { kind: 'corridor', building: b, floor: f, x_mm: x0 + 60000 + GRID * k, y_mm: 84000, wing_k: k, wing: true };
          nodes.push(w);
          wing.push(w);
        }
        for (let k = 0; k < 5; k += 1) pending.push({ a: wing[k], b: wing[k + 1], kind: 'corridor' });
        for (let k = 1; k <= 4; k += 1) {
          const d = { kind: 'destination', building: b, floor: f, x_mm: x0 + 60000 + GRID * k, y_mm: 87000, wing_k: k, wing: true };
          nodes.push(d);
          pending.push({ a: wing[k], b: d, kind: 'spur' });
        }
      }
      // main corridor spanning tree: spine and teeth
      for (let c = 0; c < 24; c += 1) pending.push({ a: nodeOf(b, f, c, 0), b: nodeOf(b, f, c + 1, 0), kind: 'corridor' });
      for (let c = 0; c <= 24; c += 1) {
        for (let r = 0; r < 11; r += 1) {
          const p = nodeOf(b, f, c, r);
          const q = nodeOf(b, f, c, r + 1);
          if (p && q) pending.push({ a: p, b: q, kind: 'corridor' });
        }
      }
    }
    // vertical edges: stairs (6, 0) and elevator (18, 0) between F1-F2 and F2-F3
    for (const f of [1, 2]) {
      pending.push({ a: nodeOf(b, f, 6, 0), b: nodeOf(b, f + 1, 6, 0), kind: 'stairs' });
      pending.push({ a: nodeOf(b, f, 18, 0), b: nodeOf(b, f + 1, 18, 0), kind: 'elevator' });
    }
  }
  // outdoor path
  const outdoor = [];
  for (let k = 0; k <= 19; k += 1) {
    const o = { kind: 'outdoor', building: null, floor: null, x_mm: 28000 * k, y_mm: -30000, outdoor_k: k };
    nodes.push(o);
    outdoor.push(o);
  }
  for (let k = 0; k < 19; k += 1) pending.push({ a: outdoor[k], b: outdoor[k + 1], kind: 'outdoor' });
  // entrances: F1 spine ends join the nearest outdoor node (ties: lower k)
  for (const b of BUILDINGS) {
    for (const c of [0, 24]) {
      const e = nodeOf(b, 1, c, 0);
      e.entrance = true;
      let best = null;
      for (const o of outdoor) {
        const dx = e.x_mm - o.x_mm;
        const dy = e.y_mm - o.y_mm;
        const d2 = dx * dx + dy * dy;
        if (best === null || d2 < best.d2) best = { o, d2 };
      }
      pending.push({ a: e, b: best.o, kind: 'entrance' });
    }
  }
  // ids in canonical node order; destination ids follow the same order
  let dn = 0;
  nodes.forEach((n, i) => {
    n.id = `N${String(i + 1).padStart(4, '0')}`;
    if (n.kind === 'destination') {
      dn += 1;
      n.dest_id = `D${String(dn).padStart(3, '0')}`;
    }
  });
  const edges = pending.map((e) => {
    const [p, q] = e.a.id < e.b.id ? [e.a, e.b] : [e.b, e.a];
    let length;
    if (e.kind === 'stairs') length = STAIRS_MM;
    else if (e.kind === 'elevator') length = ELEVATOR_MM;
    else length = ceilDistance(p.x_mm, p.y_mm, q.x_mm, q.y_mm);
    return { a: p.id, b: q.id, kind: e.kind, length_mm: length, step_free: e.kind !== 'stairs' };
  });
  edges.sort((x, y) => (x.a < y.a ? -1 : x.a > y.a ? 1 : x.b < y.b ? -1 : x.b > y.b ? 1 : 0));
  edges.forEach((e, i) => { e.id = `E${String(i + 1).padStart(4, '0')}`; });
  return { nodes, edges, destSlots };
}

/** Directed adjacency: node id -> [{ to, edge, length, step_free }], both directions per undirected edge. */
export function adjacency(edges) {
  const adj = new Map();
  const add = (from, to, e) => {
    if (!adj.has(from)) adj.set(from, []);
    adj.get(from).push({ to, edge: e.id, length: e.length_mm, step_free: e.step_free, kind: e.kind });
  };
  for (const e of edges) {
    add(e.a, e.b, e);
    add(e.b, e.a, e);
  }
  for (const list of adj.values()) list.sort((p, q) => (p.to < q.to ? -1 : p.to > q.to ? 1 : 0));
  return adj;
}
