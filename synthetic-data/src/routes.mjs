// G1 synthetic data generator - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// Route contract G1-ROUTE-1.0 (reference implementation) and the 30 route cases with their oracle.
//
// route(origin node, destination node, step_free, blocked undirected edge ids): edges are traversable in both
// directions; blocked edges are removed; step_free removes stairs. Shortest total integer length (Dijkstra).
// Reachable -> PATH (node sequence, length_mm). Otherwise REJECT_STEP_FREE_UNAVAILABLE if step_free was requested and
// the destination is reachable without that constraint (same blocked set); else REJECT_BLOCKED if edges were blocked and
// the destination is reachable without the blocked set (same step_free flag); else REJECT_UNREACHABLE.
import { Stream } from './drbg.mjs';
import { adjacency } from './geometry.mjs';

export const ROUTE_CONTRACT = 'G1-ROUTE-1.0';

/** Dijkstra with shortest-path counting (capped at 2). Returns { dist, count, prev }. */
export function dijkstra(adj, origin, { stepFree = false, blocked = new Set() } = {}) {
  const dist = new Map([[origin, 0]]);
  const count = new Map([[origin, 1]]);
  const prev = new Map();
  const done = new Set();
  // binary heap of [dist, nodeId]
  const heap = [[0, origin]];
  const less = (a, b) => a[0] < b[0] || (a[0] === b[0] && a[1] < b[1]);
  const pop = () => {
    const top = heap[0];
    const last = heap.pop();
    if (heap.length) {
      heap[0] = last;
      let i = 0;
      for (;;) {
        const l = 2 * i + 1, r = l + 1;
        let m = i;
        if (l < heap.length && less(heap[l], heap[m])) m = l;
        if (r < heap.length && less(heap[r], heap[m])) m = r;
        if (m === i) break;
        [heap[i], heap[m]] = [heap[m], heap[i]];
        i = m;
      }
    }
    return top;
  };
  const push = (item) => {
    heap.push(item);
    let i = heap.length - 1;
    while (i > 0) {
      const p = (i - 1) >> 1;
      if (!less(heap[i], heap[p])) break;
      [heap[i], heap[p]] = [heap[p], heap[i]];
      i = p;
    }
  };
  while (heap.length) {
    const [d, u] = pop();
    if (done.has(u)) continue;
    done.add(u);
    for (const e of adj.get(u) || []) {
      if (blocked.has(e.edge) || (stepFree && !e.step_free)) continue;
      const nd = d + e.length;
      const old = dist.get(e.to);
      if (old === undefined || nd < old) {
        dist.set(e.to, nd);
        count.set(e.to, count.get(u));
        prev.set(e.to, u);
        push([nd, e.to]);
      } else if (nd === old) {
        count.set(e.to, Math.min(2, count.get(e.to) + count.get(u)));
        if (u < prev.get(e.to)) prev.set(e.to, u);
      }
    }
  }
  return { dist, count, prev };
}

function pathTo(res, origin, target) {
  const nodes = [target];
  while (nodes[nodes.length - 1] !== origin) nodes.push(res.prev.get(nodes[nodes.length - 1]));
  return nodes.reverse();
}

export function route(adj, origin, target, stepFree, blockedIds) {
  const blocked = new Set(blockedIds);
  const res = dijkstra(adj, origin, { stepFree, blocked });
  if (res.dist.has(target)) {
    return { outcome: 'PATH', nodes: pathTo(res, origin, target), length_mm: res.dist.get(target), unique: res.count.get(target) === 1 };
  }
  if (stepFree && dijkstra(adj, origin, { stepFree: false, blocked }).dist.has(target)) return { outcome: 'REJECT_STEP_FREE_UNAVAILABLE' };
  if (blocked.size && dijkstra(adj, origin, { stepFree, blocked: new Set() }).dist.has(target)) return { outcome: 'REJECT_BLOCKED' };
  return { outcome: 'REJECT_UNREACHABLE' };
}

export const MIX = { normal: 12, step_free: 6, blocked_detour: 4, unreachable_wing: 4, blocked_bridge_unreachable: 2, step_free_unavailable: 2 };

/** Deterministic rejection loop (DRBG domain "routes") until every class constraint and the unique-shortest-path invariant hold. */
export function buildRouteCases(nodes, edges, dests) {
  const adj = adjacency(edges);
  const s = new Stream('routes');
  const nodeById = new Map(nodes.map((n) => [n.id, n]));
  const mainDest = dests.filter((d) => !d.wing);
  const wingDest = dests.filter((d) => d.wing);
  const origins = [...mainDest.map((d) => d.node), ...nodes.filter((n) => n.entrance).map((n) => n.id)].sort();
  const seen = new Set();
  const cases = [];
  const pick = (list) => list[s.randbelow(list.length)];
  const keyOf = (c) => `${c.origin}|${c.destination}|${c.step_free}|${c.blocked.join(',')}`;
  const accept = (cls, c, expected) => {
    const k = keyOf(c);
    if (seen.has(k)) return false;
    seen.add(k);
    cases.push({ cls, ...c, expected });
    return true;
  };
  const elevatorEdgesOf = (b) => edges.filter((e) => e.kind === 'elevator' && nodeById.get(e.a).building === b).map((e) => e.id).sort();

  for (const [cls, n] of Object.entries(MIX)) {
    let made = 0;
    while (made < n) {
      const o = pick(origins);
      let d;
      let c;
      let r;
      if (cls === 'unreachable_wing') {
        d = pick(wingDest);
        c = { origin: o, destination: d.id, step_free: false, blocked: [] };
        r = route(adj, o, d.node, false, []);
        if (r.outcome === 'REJECT_UNREACHABLE' && accept(cls, c, r)) made += 1;
        continue;
      }
      d = pick(mainDest);
      if (d.node === o) continue;
      const base = route(adj, o, d.node, false, []);
      if (base.outcome !== 'PATH') continue;
      const on = nodeById.get(o);
      if (cls === 'normal') {
        c = { origin: o, destination: d.id, step_free: false, blocked: [] };
        if (base.unique && accept(cls, c, base)) made += 1;
      } else if (cls === 'step_free') {
        if (on.floor === d.floor && on.building === d.building) continue;
        r = route(adj, o, d.node, true, []);
        c = { origin: o, destination: d.id, step_free: true, blocked: [] };
        if (r.outcome === 'PATH' && r.unique && r.nodes.join() !== base.nodes.join() && accept(cls, c, r)) made += 1;
      } else if (cls === 'blocked_detour' || cls === 'blocked_bridge_unreachable') {
        const pathEdges = [];
        for (let i = 0; i + 1 < base.nodes.length; i += 1) {
          const e = adj.get(base.nodes[i]).find((x) => x.to === base.nodes[i + 1]);
          pathEdges.push(e.edge);
        }
        const detour = [];
        const bridge = [];
        for (const eid of [...new Set(pathEdges)].sort()) {
          const rr = route(adj, o, d.node, false, [eid]);
          if (rr.outcome === 'PATH') detour.push(eid);
          else bridge.push(eid);
        }
        const pool = cls === 'blocked_detour' ? detour : bridge;
        if (!pool.length) continue;
        const eid = pick(pool);
        r = route(adj, o, d.node, false, [eid]);
        c = { origin: o, destination: d.id, step_free: false, blocked: [eid] };
        const ok = cls === 'blocked_detour' ? r.outcome === 'PATH' && r.unique && r.length_mm > base.length_mm : r.outcome === 'REJECT_BLOCKED';
        if (ok && accept(cls, c, r)) made += 1;
      } else if (cls === 'step_free_unavailable') {
        if (d.floor === 1) continue;
        if (on.building === d.building && on.floor === d.floor) continue;
        const blocked = elevatorEdgesOf(d.building);
        r = route(adj, o, d.node, true, blocked);
        c = { origin: o, destination: d.id, step_free: true, blocked };
        if (r.outcome === 'REJECT_STEP_FREE_UNAVAILABLE' && accept(cls, c, r)) made += 1;
      }
    }
  }
  cases.forEach((c, i) => { c.id = `RT${String(i + 1).padStart(2, '0')}`; });
  return cases;
}
