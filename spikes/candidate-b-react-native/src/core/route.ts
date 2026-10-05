// Candidate B (React Native) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// G1-ROUTE-1.0 in TypeScript: Dijkstra on integer millimetres; ties take the smallest predecessor id.
import type { GraphData, GraphEdge } from './bundleData';

export interface RouteResult {
  /** PATH | REJECT_STEP_FREE_UNAVAILABLE | REJECT_BLOCKED | REJECT_UNREACHABLE | REJECT_UNKNOWN | REJECT_UNTRUSTED */
  outcome: string;
  nodes: string[];
  lengthMm: number;
}

export class RouteGraph {
  private readonly index = new Map<string, number>();
  private readonly ids: string[];
  private readonly edges: GraphEdge[];
  private readonly adj: number[][];
  private readonly byPair = new Map<string, GraphEdge>();

  constructor(g: GraphData) {
    this.ids = g.nodes.map((n) => n.id).sort();
    this.ids.forEach((id, i) => this.index.set(id, i));
    this.edges = g.edges;
    this.adj = this.ids.map(() => []);
    g.edges.forEach((e, k) => this.adj[this.index.get(e.from)!].push(k));
    for (const e of g.edges) this.byPair.set(`${e.from}>${e.to}`, e);
  }

  edge(from: string, to: string): GraphEdge | undefined {
    return this.byPair.get(`${from}>${to}`);
  }

  private dijkstra(origin: number, stepFree: boolean, blocked: Set<string>): { dist: Float64Array; prev: Int32Array } {
    const n = this.ids.length;
    const dist = new Float64Array(n).fill(-1);
    const prev = new Int32Array(n).fill(-1);
    const done = new Uint8Array(n);
    const heap = new Heap();
    dist[origin] = 0;
    heap.push(0, origin);
    while (heap.size > 0) {
      const d = heap.topDist();
      const u = heap.pop();
      if (done[u]) continue;
      done[u] = 1;
      for (const k of this.adj[u]) {
        const e = this.edges[k];
        if (blocked.has(e.edge) || (stepFree && !e.stepFree)) continue;
        const v = this.index.get(e.to)!;
        const nd = d + e.lengthMm;
        const old = dist[v];
        if (old < 0 || nd < old) {
          dist[v] = nd;
          prev[v] = u;
          heap.push(nd, v);
        } else if (nd === old && u < prev[v]) {
          prev[v] = u;
        }
      }
    }
    return { dist, prev };
  }

  route(origin: string, targetNode: string, stepFree = false, blocked: string[] = []): RouteResult {
    const o = this.index.get(origin);
    const t = this.index.get(targetNode);
    if (o === undefined || t === undefined) return { outcome: 'REJECT_UNKNOWN', nodes: [], lengthMm: 0 };
    const blockedSet = new Set(blocked);
    const { dist, prev } = this.dijkstra(o, stepFree, blockedSet);
    if (dist[t] >= 0) {
      const path: string[] = [];
      for (let v = t; v !== -1; v = v === o ? -1 : prev[v]) path.push(this.ids[v]);
      return { outcome: 'PATH', nodes: path.reverse(), lengthMm: dist[t] };
    }
    if (stepFree && this.dijkstra(o, false, blockedSet).dist[t] >= 0) return { outcome: 'REJECT_STEP_FREE_UNAVAILABLE', nodes: [], lengthMm: 0 };
    if (blockedSet.size > 0 && this.dijkstra(o, stepFree, new Set()).dist[t] >= 0) return { outcome: 'REJECT_BLOCKED', nodes: [], lengthMm: 0 };
    return { outcome: 'REJECT_UNREACHABLE', nodes: [], lengthMm: 0 };
  }
}

/** Binary min-heap of (distance, node index); ties by node index. */
class Heap {
  private d: number[] = [];
  private v: number[] = [];

  get size(): number {
    return this.d.length;
  }

  topDist(): number {
    return this.d[0];
  }

  private less(i: number, j: number): boolean {
    return this.d[i] < this.d[j] || (this.d[i] === this.d[j] && this.v[i] < this.v[j]);
  }

  private swap(i: number, j: number): void {
    const td = this.d[i];
    const tv = this.v[i];
    this.d[i] = this.d[j];
    this.v[i] = this.v[j];
    this.d[j] = td;
    this.v[j] = tv;
  }

  push(d: number, v: number): void {
    this.d.push(d);
    this.v.push(v);
    let i = this.d.length - 1;
    while (i > 0) {
      const p = (i - 1) >> 1;
      if (!this.less(i, p)) break;
      this.swap(i, p);
      i = p;
    }
  }

  pop(): number {
    const top = this.v[0];
    const lastD = this.d.pop()!;
    const lastV = this.v.pop()!;
    if (this.d.length > 0) {
      this.d[0] = lastD;
      this.v[0] = lastV;
      let i = 0;
      for (;;) {
        const l = 2 * i + 1;
        const r = l + 1;
        let m = i;
        if (l < this.d.length && this.less(l, m)) m = l;
        if (r < this.d.length && this.less(r, m)) m = r;
        if (m === i) break;
        this.swap(i, m);
        i = m;
      }
    }
    return top;
  }
}
