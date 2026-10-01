// Candidate B (React Native) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// The verified bundle as the runtime sees it. Parsers are strict: any structural problem is a FormatError (fuzz target
// FUZ02 and bridge attack BRG02 rely on that), never a crash or a partially loaded state.

export class FormatError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'FormatError';
  }
}

export interface Destination {
  id: string;
  code: string;
  building: string;
  floor: number;
  node: string;
  roomNumber: string;
  nameEn: string;
  nameAr: string;
  reachable: boolean;
}

export interface GraphNode {
  id: string;
  kind: string;
  building: string | null;
  floor: number | null;
  xMm: number;
  yMm: number;
  entrance: boolean;
}

export interface GraphEdge {
  id: string;
  from: string;
  to: string;
  edge: string;
  kind: string;
  lengthMm: number;
  stepFree: boolean;
}

export interface GraphData {
  nodes: GraphNode[];
  edges: GraphEdge[];
}

export interface ScheduleEntry {
  code: string;
  labelEn: string;
  labelAr: string;
  destination: string;
  start: string;
  end: string;
}

export interface RouteCase {
  id: string;
  origin: string;
  destination: string;
  stepFree: boolean;
  blocked: string[];
}

export interface Query {
  id: string;
  text: string;
}

export const MAX_JSON_CHARS = 16 * 1024 * 1024;

type Obj = Record<string, unknown>;

function decode(json: string): unknown {
  if (json.length > MAX_JSON_CHARS) throw new FormatError('too large');
  try {
    return JSON.parse(json);
  } catch {
    throw new FormatError('json');
  }
}

function obj(v: unknown, what: string): Obj {
  if (v !== null && typeof v === 'object' && !Array.isArray(v)) return v as Obj;
  throw new FormatError(`${what}: object expected`);
}

function list(m: Obj, k: string): unknown[] {
  const v = m[k];
  if (Array.isArray(v)) return v;
  throw new FormatError(`${k}: array expected`);
}

function str(m: Obj, k: string): string {
  const v = m[k];
  if (typeof v === 'string') return v;
  throw new FormatError(`${k}: string expected`);
}

function optStr(m: Obj, k: string): string | null {
  const v = m[k];
  if (v === undefined || v === null) return null;
  if (typeof v === 'string') return v;
  throw new FormatError(`${k}: string or null expected`);
}

function int(m: Obj, k: string): number {
  const v = m[k];
  if (typeof v === 'number' && Number.isSafeInteger(v)) return v;
  throw new FormatError(`${k}: integer expected`);
}

function optInt(m: Obj, k: string): number | null {
  const v = m[k];
  if (v === undefined || v === null) return null;
  if (typeof v === 'number' && Number.isSafeInteger(v)) return v;
  throw new FormatError(`${k}: integer or null expected`);
}

function bool(m: Obj, k: string, fallback?: boolean): boolean {
  const v = m[k];
  if (typeof v === 'boolean') return v;
  if (v === undefined && fallback !== undefined) return fallback;
  throw new FormatError(`${k}: boolean expected`);
}

/** graph.json (G1-ROUTE-1.0 input). */
export function parseGraph(json: string): GraphData {
  const root = obj(decode(json), 'graph');
  const nodes: GraphNode[] = [];
  const ids = new Set<string>();
  for (const n of list(root, 'nodes')) {
    const m = obj(n, 'node');
    const node: GraphNode = {
      id: str(m, 'id'),
      kind: str(m, 'kind'),
      building: optStr(m, 'building'),
      floor: optInt(m, 'floor'),
      xMm: int(m, 'x_mm'),
      yMm: int(m, 'y_mm'),
      entrance: bool(m, 'entrance', false),
    };
    if (ids.has(node.id)) throw new FormatError(`duplicate node ${node.id}`);
    ids.add(node.id);
    nodes.push(node);
  }
  const edges: GraphEdge[] = [];
  for (const e of list(root, 'edges')) {
    const m = obj(e, 'edge');
    const edge: GraphEdge = {
      id: str(m, 'id'),
      from: str(m, 'from'),
      to: str(m, 'to'),
      edge: str(m, 'edge'),
      kind: str(m, 'kind'),
      lengthMm: int(m, 'length_mm'),
      stepFree: bool(m, 'step_free'),
    };
    if (!ids.has(edge.from) || !ids.has(edge.to)) throw new FormatError(`edge ${edge.id}: unknown node`);
    if (edge.lengthMm < 0) throw new FormatError(`edge ${edge.id}: negative length`);
    edges.push(edge);
  }
  return { nodes, edges };
}

/** destinations.json */
export function parseDestinations(json: string): Destination[] {
  const root = obj(decode(json), 'destinations');
  const out: Destination[] = [];
  const ids = new Set<string>();
  for (const d of list(root, 'destinations')) {
    const m = obj(d, 'destination');
    const dest: Destination = {
      id: str(m, 'id'),
      code: str(m, 'code'),
      building: str(m, 'building'),
      floor: int(m, 'floor'),
      node: str(m, 'node'),
      roomNumber: str(m, 'room_number'),
      nameEn: str(m, 'name_en'),
      nameAr: str(m, 'name_ar'),
      reachable: bool(m, 'reachable_from_entrances'),
    };
    if (ids.has(dest.id)) throw new FormatError(`duplicate destination ${dest.id}`);
    ids.add(dest.id);
    out.push(dest);
  }
  return out;
}

export function parseSchedule(json: string): ScheduleEntry[] {
  const root = obj(decode(json), 'schedule');
  return list(root, 'entries').map((e) => {
    const m = obj(e, 'entry');
    return {
      code: str(m, 'code'),
      labelEn: str(m, 'label_en'),
      labelAr: str(m, 'label_ar'),
      destination: str(m, 'destination'),
      start: str(m, 'start'),
      end: str(m, 'end'),
    };
  });
}

export function parseRouteCases(json: string): RouteCase[] {
  const root = obj(decode(json), 'route cases');
  return list(root, 'cases').map((c) => {
    const m = obj(c, 'case');
    return {
      id: str(m, 'id'),
      origin: str(m, 'origin'),
      destination: str(m, 'destination'),
      stepFree: bool(m, 'step_free'),
      blocked: list(m, 'blocked').map((b) => {
        if (typeof b !== 'string') throw new FormatError('blocked: string expected');
        return b;
      }),
    };
  });
}

export function parseQueries(json: string): Query[] {
  const root = obj(decode(json), 'query corpus');
  return list(root, 'queries').map((q) => {
    const m = obj(q, 'query');
    return { id: str(m, 'id'), text: str(m, 'text') };
  });
}

/** geometry.geojson LineString features of the non-vertical edges, by undirected edge id (route display). */
export function parseEdgeFeatures(json: string): Map<string, Obj> {
  const root = obj(decode(json), 'geometry');
  const out = new Map<string, Obj>();
  for (const f of list(root, 'features')) {
    const m = obj(f, 'feature');
    const props = obj(m.properties, 'properties');
    const geom = obj(m.geometry, 'geometry');
    const id = props.id;
    if (typeof id === 'string' && id.startsWith('E') && geom.type === 'LineString') out.set(id, m);
  }
  return out;
}

export class BundleData {
  readonly byId: Map<string, Destination>;
  readonly entrances: string[];

  constructor(
    readonly version: string,
    readonly dirUrl: string,
    readonly destinations: Destination[],
    readonly graph: GraphData,
    readonly schedule: ScheduleEntry[],
    readonly routeCases: RouteCase[],
    readonly queries: Query[],
    readonly styleJson: string,
    readonly edgeFeatures: Map<string, Obj>,
  ) {
    this.byId = new Map(destinations.map((d) => [d.id, d]));
    this.entrances = graph.nodes.filter((n) => n.entrance && n.building !== null).map((n) => n.id).sort();
  }

  scheduleFor(destinationId: string): ScheduleEntry[] {
    return this.schedule.filter((e) => e.destination === destinationId).sort((a, b) => (a.start < b.start ? -1 : a.start > b.start ? 1 : 0));
  }

  /** read: UTF-8 text of a bundle file (through the native module on device, from disk in tests). */
  static async load(version: string, dirUrl: string, read: (path: string) => Promise<string>): Promise<BundleData> {
    const [d, g, s, r, q, style, geo] = await Promise.all([
      read('destinations.json'),
      read('graph.json'),
      read('schedule.json'),
      read('route_cases.json'),
      read('query_corpus.json'),
      read('style.json'),
      read('geometry.geojson'),
    ]);
    return new BundleData(version, dirUrl, parseDestinations(d), parseGraph(g), parseSchedule(s), parseRouteCases(r), parseQueries(q), style,
      parseEdgeFeatures(geo));
  }
}
