// Candidate B (React Native) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// Lab hooks of G1-CIC-1.0 (present in every benchmark lab build). Commands arrive from the common module (Android intent
// extras / iOS launch arguments or URL) through the TurboModule and drive the same handlers as the UI.
import * as G1 from 'g1-native';

import type { AppState } from './state';
import { lonOf, latOf } from './state';
import { decodeBase64, encodeBase64 } from './core/base64';
import { FormatError, parseGraph, type RouteCase } from './core/bundleData';
import { crc32 } from './core/crc32';
import { decodeUtf8 } from './core/utf8';

export const LAB_COMMANDS: ReadonlySet<string> = new Set([
  'bench.search-route', 'bench.bridge', 'bench.ui-session', 'bench.idle', 'nav.home', 'nav.details', 'nav.route',
  'nav.open-route-ar', 'lang.set', 'bundle.import', 'bundle.rollback', 'bundle.update', 'qr.inject', 'ar.inject',
  'session.start', 'session.end', 'session.status', 'crash', 'fuzz', 'bridge.attack', 'search.set', 'a11y.seed',
  'bundle.remove', 'map.inspect', 'map.camera',
]);

type Keyframe =
  | { at_ms: number; action: 'camera'; center_mm: [number, number]; zoom: number; duration_ms: number }
  | { at_ms: number; action: 'floor'; floor: number };

/** G1-UI-SCRIPT-1.0 keyframes (contract ui_session_script; checked against contract.json by the unit tests). */
export const UI_SCRIPT: Keyframe[] = [
  { at_ms: 0, action: 'camera', center_mm: [72000, 33000], zoom: 17.0, duration_ms: 2000 },
  { at_ms: 3000, action: 'floor', floor: 2 },
  { at_ms: 4000, action: 'camera', center_mm: [272000, 33000], zoom: 17.0, duration_ms: 4000 },
  { at_ms: 9000, action: 'camera', center_mm: [272000, 33000], zoom: 18.5, duration_ms: 2000 },
  { at_ms: 12000, action: 'floor', floor: 3 },
  { at_ms: 13000, action: 'camera', center_mm: [472000, 33000], zoom: 18.5, duration_ms: 5000 },
  { at_ms: 19000, action: 'camera', center_mm: [472000, 33000], zoom: 16.5, duration_ms: 3000 },
  { at_ms: 23000, action: 'floor', floor: 1 },
  { at_ms: 24000, action: 'camera', center_mm: [72000, 33000], zoom: 17.0, duration_ms: 5000 },
];
export const UI_CYCLE_MS = 30000;

/** Settled reading of map.inspect (contract lab.map_inspect_settle; checked against contract.json by the unit tests). */
export const MAP_SETTLE_INTERVAL_MS = 100;
export const MAP_SETTLE_BOUND_MS = 4000;

const isObject = (v: unknown): v is Record<string, unknown> => v !== null && typeof v === 'object' && !Array.isArray(v);

/** Runtime-side decoder of the lab command envelope {"method": name, "args": {...}} (fuzz target FUZ03). */
export function decodeEnvelope(text: string): string {
  if (text.length > 16 * 1024) return 'REJECT_SIZE';
  let v: unknown;
  try {
    v = JSON.parse(text);
  } catch {
    return 'REJECT_JSON';
  }
  if (!isObject(v)) return 'REJECT_SHAPE';
  const m = v.method;
  if (typeof m !== 'string' || !LAB_COMMANDS.has(m)) return 'REJECT_METHOD';
  if (!isObject(v.args)) return 'REJECT_ARGS';
  if (Object.keys(v).length !== 2) return 'REJECT_SHAPE';
  return 'ACCEPT';
}

const SIZES: Record<string, number> = { '64B': 64, '4KiB': 4096, '64KiB': 65536 };
const TWO_32 = 4294967296;
const offsetOf = (seq: number, size: number): number => (seq * 64) % (65536 - size + 1);
const delay = (ms: number): Promise<void> => new Promise((r) => setTimeout(r, ms));
/** Idle point (G1-CIC-1.0): a timed handler never starts inside a frame callback (a zero-delay timer task). */
const idle = (): Promise<void> => delay(0);

type Series = {
  kind: 'control' | 'measured';
  t0_ns: number;
  send_offsets_ns: number[];
  latencies_ns: number[];
  completed: number;
  crc_failures: number;
};

/** Error code of a rejected boundary call: promise rejection code, or the JavaScript error thrown before native code. */
function errorCode(e: unknown, thrownSync: boolean): string {
  if (thrownSync) return e instanceof TypeError || (e instanceof Error && /argument|expected/i.test(e.message)) ? 'BAD_ARGUMENT' : 'THROWN';
  const code = (e as { code?: unknown })?.code;
  return typeof code === 'string' ? code : 'UNKNOWN';
}

export class LabController {
  private readonly queue: Array<{ name: string; args: string }> = [];
  private busy = false;
  canary: string | null = null;
  private readonly echoBuffer = new Uint8Array(64 * 1024);

  constructor(private readonly state: AppState) {}

  private now = (): number => G1.nowNanos();

  private mark(name: string, kv: string[] = []): void {
    G1.mark(name, kv);
  }

  async start(): Promise<void> {
    G1.NativeG1.onCommand((e) => this.enqueue(e));
    G1.NativeG1.onArEvent((e) => this.state.onArEvent(e.requestId, e.event));
    const deadline = this.now() + 60e9;
    while (!this.state.ready && this.now() < deadline && (this.state.bundleInfo === null || this.state.trusted)) await delay(50);
    const launch = await G1.launchCommand();
    if (launch !== null) this.enqueue(launch);
  }

  private enqueue(cmd: { name: string; args: string }): void {
    this.queue.push(cmd);
    if (!this.busy) void this.drain();
  }

  private async drain(): Promise<void> {
    this.busy = true;
    while (this.queue.length > 0) {
      const cmd = this.queue.shift()!;
      let args: Record<string, unknown> | null = null;
      try {
        const v: unknown = JSON.parse(cmd.args ?? '{}');
        if (isObject(v)) args = v;
      } catch {
        args = null;
      }
      if (typeof cmd.name !== 'string' || args === null || decodeEnvelope(JSON.stringify({ method: cmd.name, args })) !== 'ACCEPT') {
        this.mark('command.rejected', ['reason', 'runtime_envelope']);
        continue;
      }
      try {
        await this.exec(cmd.name, args);
      } catch (e) {
        this.mark('command.failed', ['cmd', cmd.name, 'error', e instanceof Error ? e.name : typeof e]);
      }
    }
    this.busy = false;
  }

  private async exec(name: string, a: Record<string, unknown>): Promise<void> {
    const str = (k: string): string => {
      const v = a[k];
      if (typeof v !== 'string') throw new FormatError(`arg ${k}`);
      return v;
    };
    const int = (k: string, fallback: number): number => {
      const v = a[k];
      return typeof v === 'number' && Number.isSafeInteger(v) ? v : fallback;
    };
    const s = this.state;
    switch (name) {
      case 'nav.home':
        s.goHome();
        break;
      case 'nav.details':
        s.goHome();
        s.openDetails(str('destination'));
        break;
      case 'nav.route':
        await this.openCaseRoute(a);
        break;
      case 'nav.open-route-ar':
        await this.openCaseRoute(a);
        await s.openAr();
        break;
      case 'ar.inject':
        await this.openCaseRoute(a);
        await s.openAr(JSON.stringify(a.script));
        break;
      case 'lang.set':
        s.setLang(str('lang'));
        break;
      case 'bundle.import':
        await s.importBundleFile(str('file'));
        break;
      case 'bundle.rollback':
        await s.rollback();
        break;
      case 'bundle.update':
        await s.update(str('url'));
        break;
      case 'qr.inject':
        await s.injectQr(str('file'));
        break;
      case 'session.start':
        await G1.NativeG1.sessionStart(str('marker'));
        break;
      case 'session.end':
        await G1.NativeG1.sessionEnd();
        break;
      case 'session.status':
        await G1.NativeG1.sessionActive();
        break;
      case 'crash':
        await this.crash(str('case'), typeof a.canary === 'string' ? a.canary : null);
        break;
      case 'bench.search-route':
        await this.benchSearchRoute(str('run_id'), str('kind'));
        break;
      case 'bench.bridge':
        await this.benchBridge(str('run_id'), str('workload'), typeof a.order === 'string' ? a.order : 'control-first',
          int('messages', 1000), int('rate_hz', 200));
        break;
      case 'bench.ui-session':
        await this.window(str('session_id'), int('warmup_s', 60), int('measure_s', 300), true);
        break;
      case 'bench.idle':
        await this.window(str('session_id'), int('warmup_s', 60), int('measure_s', 300), false);
        break;
      case 'fuzz':
        await this.fuzz(str('run_id'), str('target'), str('corpus'));
        break;
      case 'bridge.attack':
        await this.attack(str('run_id'), str('case'));
        break;
      case 'search.set':
        await s.setSearch(str('text'));
        break;
      case 'a11y.seed':
        if (!(await s.seedDefect(str('defect')))) this.mark('command.rejected', ['reason', 'unknown_defect']);
        break;
      case 'bundle.remove':
        await s.removeBundles();
        break;
      case 'map.inspect':
        await this.mapInspect(str('run_id'));
        break;
      case 'map.camera':
        await this.mapCamera(a);
        break;
    }
  }

  // ---------------------------------------------------------------- B02 map inspection (G1-MAP-INSPECT-1.1)

  /** Registered render view: home screen, the floor through the UI handler, the camera moved without animation. */
  private async mapCamera(a: Record<string, unknown>): Promise<void> {
    const s = this.state;
    const { x_mm: x, y_mm: y, zoom, floor } = a;
    if (!Number.isSafeInteger(x) || !Number.isSafeInteger(y) || typeof zoom !== 'number') throw new FormatError('arg camera');
    s.goHome();
    if (Number.isSafeInteger(floor)) s.setFloor(floor as number);
    s.camera?.easeTo(lonOf(x as number), latOf(y as number), zoom, 1); // same minimal duration as A and C
    await s.nextFrame();
    await s.nextFrame();
    this.mark('map.camera.done', ['floor', String(s.floor)]);
  }

  /**
   * The settled reading of G1-MAP-INSPECT-1.1: the reading is repeated every MAP_SETTLE_INTERVAL_MS until two consecutive
   * readings report the same rendered features (at least one feature while a style is loaded) or MAP_SETTLE_BOUND_MS
   * have passed since the first reading began; the last reading is written with the number of readings.
   */
  private async mapInspect(runId: string): Promise<void> {
    const s = this.state;
    this.mark('run.start', ['run', runId, 'map', 'inspect']);
    await s.nextFrame();
    const t0 = Date.now();
    let passes = 0;
    let settled = false;
    let previous: string | null = null;
    let m: Record<string, unknown> = { available: false };
    for (;;) {
      m = s.camera ? await s.camera.inspect() : { available: false };
      passes += 1;
      if (m.available !== true) break;
      const rendered = Array.isArray(m.rendered) ? m.rendered : [];
      const key = JSON.stringify(rendered);
      if (key === previous && (rendered.length > 0 || m.style_loaded !== true)) {
        settled = true;
        break;
      }
      if (Date.now() - t0 >= MAP_SETTLE_BOUND_MS) break;
      previous = key;
      await delay(MAP_SETTLE_INTERVAL_MS);
    }
    await G1.NativeG1.writeOut(`${runId}.json`, JSON.stringify({ contract: 'G1-MAP-INSPECT-1.1', run_id: runId, app: 'B', app_floor: s.floor,
      app_lang: s.lang, ...m, settle: { passes, elapsed_ms: Date.now() - t0, settled } }));
    this.mark('run.done', ['run', runId, 'map', 'inspect']);
  }

  private routeCase(id: unknown): RouteCase | undefined {
    return typeof id === 'string' ? this.state.data?.routeCases.find((c) => c.id === id) : undefined;
  }

  private async openCaseRoute(a: Record<string, unknown>): Promise<void> {
    const s = this.state;
    const c = this.routeCase(a.case);
    s.goHome();
    if (c) {
      s.openRoute(c.destination, c.origin, c.stepFree, c.blocked);
    } else {
      if (typeof a.destination !== 'string') throw new FormatError('arg destination');
      s.openRoute(a.destination, typeof a.origin === 'string' ? a.origin : null, a.step_free === true, []);
    }
    await s.nextFrame();
    s.computeRoute();
    await s.nextFrame();
  }

  // ---------------------------------------------------------------- B07-SEARCH / B03-ROUTING-GRAPH

  private async benchSearchRoute(runId: string, kind: string): Promise<void> {
    const s = this.state;
    const data = s.data;
    if (data === null) return;
    this.mark('run.start', ['run', runId, 'bench', 'search-route']);
    const start = this.now();
    s.goHome();
    await s.nextFrame();
    const search: Array<Record<string, unknown>> = [];
    for (const q of data.queries) {
      s.setQuery(q.text, false);
      await s.nextFrame(); // the typed query is on screen before the timed submit
      await idle();
      const t0 = this.now();
      const compute = s.submitSearch();
      const t1 = await s.nextFrame();
      const r = s.results!;
      search.push({ id: q.id, outcome: r.outcome, ids: r.ids, compute_ns: compute, e2e_ns: t1 - t0 });
    }
    s.clearSearch();
    const route: Array<Record<string, unknown>> = [];
    for (const c of data.routeCases) {
      s.openRoute(c.destination, c.origin, c.stepFree, c.blocked);
      await s.nextFrame();
      await idle();
      const t0 = this.now();
      const compute = s.computeRoute();
      const t1 = await s.nextFrame();
      const r = s.route!;
      const row: Record<string, unknown> = { id: c.id, outcome: r.outcome };
      if (r.outcome === 'PATH') {
        row.nodes = r.nodes;
        row.length_mm = r.lengthMm;
        row.steps = s.steps;
        row.summary = s.summary;
      }
      row.compute_ns = compute;
      row.e2e_ns = t1 - t0;
      route.push(row);
      s.back();
    }
    s.goHome();
    const end = this.now();
    await G1.NativeG1.writeOut(`${runId}.json`, JSON.stringify({
      contract: 'G1-BENCH-SR-1.0', run_id: runId, kind, app: 'B', bundle_version: data.version, start_ns: start, end_ns: end,
      search, route,
    }));
    this.mark('run.done', ['run', runId, 'bench', 'search-route']);
  }

  // ---------------------------------------------------------------- B11-BRIDGE-OVERHEAD

  private localEcho(payload: Uint8Array): [number, number] {
    const entry = this.now();
    const n = Math.min(payload.length, this.echoBuffer.length);
    this.echoBuffer.set(payload.subarray(0, n), 0);
    return [n * TWO_32 + crc32(this.echoBuffer, n), entry];
  }

  private async sleepUntil(dueNs: number): Promise<void> {
    const wait = dueNs - this.now();
    if (wait > 0) await delay(wait / 1e6);
  }

  private async r2n(block: Uint8Array, size: number, n: number, rate: number, control: boolean, sync: boolean): Promise<Series> {
    const latencies = new Array<number>(n).fill(-1);
    const offsets = new Array<number>(n).fill(-1);
    let completed = 0;
    let crcFailures = 0;
    let lastProgress = this.now();
    let resolveAll: () => void = () => {};
    const all = new Promise<void>((r) => (resolveAll = r));
    const t0 = this.now() + 20e6;
    for (let i = 0; i < n; i++) {
      await this.sleepUntil(t0 + Math.round((i * 1e9) / rate));
      const off = offsetOf(i, size);
      const payload = block.subarray(off, off + size);
      const expected = size * TWO_32 + crc32(payload);
      const tSend = this.now();
      offsets[i] = tSend - t0;
      if (control) {
        const [r, entry] = this.localEcho(payload);
        latencies[i] = entry - tSend;
        if (r !== expected) crcFailures++;
        completed++;
      } else if (sync) {
        const reply = G1.NativeG1.echoSyncBase64(encodeBase64(payload));
        if (reply.length === 2) {
          latencies[i] = reply[1] - tSend;
          if (reply[0] !== expected) crcFailures++;
          completed++;
        }
      } else {
        const seq = i;
        G1.NativeG1.echoAsyncBase64(encodeBase64(payload)).then(
          (reply) => {
            latencies[seq] = reply[1] - tSend;
            if (reply[0] !== expected) crcFailures++;
            completed++;
            lastProgress = this.now();
            if (completed === n) resolveAll();
          },
          () => {
            lastProgress = this.now();
          },
        );
      }
    }
    if (!control && !sync && completed < n) {
      let done = false;
      void all.then(() => (done = true));
      while (!done && this.now() - lastProgress < 10e9) await Promise.race([all, delay(100)]);
    }
    return { kind: control ? 'control' : 'measured', t0_ns: t0, send_offsets_ns: offsets, latencies_ns: latencies, completed,
      crc_failures: crcFailures };
  }

  private async n2r(block: Uint8Array, size: number, n: number, rate: number, control: boolean): Promise<Series> {
    const latencies = new Array<number>(n).fill(-1);
    const offsets = new Array<number>(n).fill(-1);
    const expected = Array.from({ length: n }, (_, i) => {
      const off = offsetOf(i, size);
      return crc32(block.subarray(off, off + size));
    });
    let completed = 0;
    let crcFailures = 0;
    let firstSent: number | null = null;
    const handler = (seq: number, sent: number, payloadBase64: string): void => {
      const recv = this.now();
      if (firstSent === null) firstSent = sent;
      if (seq < 0 || seq >= n) return;
      latencies[seq] = recv - sent;
      offsets[seq] = sent - firstSent;
      let payload: Uint8Array | null = null;
      try {
        payload = decodeBase64(payloadBase64);
      } catch {
        payload = null;
      }
      if (payload === null || payload.length !== size || crc32(payload) !== expected[seq]) crcFailures++;
      completed++;
    };
    const t0 = this.now() + 20e6;
    if (control) {
      const encoded = Array.from({ length: n }, (_, i) => encodeBase64(block.subarray(offsetOf(i, size), offsetOf(i, size) + size)));
      for (let i = 0; i < n; i++) {
        await this.sleepUntil(t0 + Math.round((i * 1e9) / rate));
        handler(i, this.now(), encoded[i]);
      }
    } else {
      let done = false;
      let lastProgress = this.now();
      const sub = G1.NativeG1.onN2R((m) => {
        if (m.done) {
          done = true;
          return;
        }
        handler(m.seq, m.sent, m.payload);
        lastProgress = this.now();
      });
      G1.NativeG1.startN2R(size, n, rate);
      while (!done && this.now() - lastProgress < 10e9) await delay(100);
      await delay(50);
      sub.remove();
    }
    return { kind: control ? 'control' : 'measured', t0_ns: firstSent ?? t0, send_offsets_ns: offsets, latencies_ns: latencies, completed,
      crc_failures: crcFailures };
  }

  private async benchBridge(runId: string, workload: string, order: string, n: number, rate: number): Promise<void> {
    this.mark('run.start', ['run', runId, 'bench', 'bridge', 'workload', workload]);
    const result: Record<string, unknown> = { contract: 'G1-BENCH-BRIDGE-1.0', run_id: runId, app: 'B', workload, order, messages: n, rate_hz: rate };
    const m = /^(R2N|N2R)\.(64B|4KiB|64KiB)\.(async|sync)$/.exec(workload);
    if (m === null || (m[3] === 'sync' && m[1] !== 'R2N')) {
      result.outcome = 'FAILED';
    } else {
      const size = SIZES[m[2]];
      const block = await this.state.ensurePayloadBlock();
      const series: Series[] = [];
      for (const control of order === 'measured-first' ? [false, true] : [true, false]) {
        series.push(m[1] === 'R2N' ? await this.r2n(block, size, n, rate, control, m[3] === 'sync') : await this.n2r(block, size, n, rate, control));
      }
      result.series = series;
      result.outcome = series.every((x) => x.completed === n) ? 'OK' : 'FAILED';
    }
    await G1.NativeG1.writeOut(`${runId}.json`, JSON.stringify(result));
    this.mark('run.done', ['run', runId, 'bench', 'bridge', 'outcome', String(result.outcome)]);
  }

  // ---------------------------------------------------------------- B07/B08 windows (G1-UI-SCRIPT-1.0)

  private async window(id: string, warmupS: number, measureS: number, script: boolean): Promise<void> {
    const s = this.state;
    s.goHome();
    await s.nextFrame();
    const totalMs = (warmupS + measureS) * 1000;
    const events: Array<{ at: number; k: Keyframe | null; phase: string | null }> = [
      { at: 0, k: null, phase: 'warmup.start' },
      { at: warmupS * 1000, k: null, phase: 'measure.start' },
    ];
    if (script) {
      for (let cycle = 0; cycle < totalMs; cycle += UI_CYCLE_MS) {
        for (const k of UI_SCRIPT) if (cycle + k.at_ms < totalMs) events.push({ at: cycle + k.at_ms, k, phase: null });
      }
    }
    events.sort((x, y) => x.at - y.at); // stable: phases stay before keyframes at the same time
    const start = this.now();
    for (const e of events) {
      await this.sleepUntil(start + e.at * 1e6);
      if (e.phase !== null) this.mark('session.window', ['session', id, 'phase', e.phase]);
      else if (e.k!.action === 'floor') s.setFloor(e.k!.floor);
      else s.camera?.easeTo(lonOf(e.k!.center_mm[0]), latOf(e.k!.center_mm[1]), e.k!.zoom, e.k!.duration_ms);
    }
    await this.sleepUntil(start + totalMs * 1e6);
    this.mark('session.window', ['session', id, 'phase', 'end']);
  }

  // ---------------------------------------------------------------- B16 crash fixtures

  private async crash(caseId: string, canaryValue: string | null): Promise<void> {
    this.canary = canaryValue; // held in app state; must never reach a trace
    this.mark('crash.trigger', ['case', caseId]);
    switch (caseId) {
      case 'CR1':
        try {
          throw new RangeError('G1 synthetic CR1');
        } catch (e) {
          await G1.NativeG1.writeOut('crash-CR1.json', JSON.stringify({ case: 'CR1', handled: true, type: (e as Error).name }));
        }
        break;
      case 'CR2':
        requestAnimationFrame(() => {
          throw new Error('G1 synthetic CR2');
        });
        break;
      case 'CR3':
      case 'CR4':
        G1.NativeG1.crash(caseId);
        break;
      case 'CR6': {
        const hog: Uint8Array[] = [];
        for (;;) {
          hog.push(new Uint8Array(16 * 1024 * 1024).fill(1));
          await delay(0);
        }
      }
    }
  }

  // ---------------------------------------------------------------- B16 fuzz targets

  private async fuzzOne(target: string, input: Uint8Array): Promise<string> {
    const text = decodeUtf8(input);
    try {
      switch (target) {
        case 'FUZ01':
          return String((await G1.validateQr(text)).outcome);
        case 'FUZ02':
          parseGraph(text);
          return 'OK';
        default:
          return decodeEnvelope(text);
      }
    } catch (e) {
      if (e instanceof FormatError) return 'REJECT_FORMAT';
      const code = (e as { code?: unknown })?.code;
      if (typeof code === 'string') return `REJECT_${code}`;
      return `UNEXPECTED_${e instanceof Error ? e.name : typeof e}`;
    }
  }

  private async fuzz(runId: string, target: string, corpus: string): Promise<void> {
    this.mark('run.start', ['run', runId, 'fuzz', target]);
    const doc: unknown = JSON.parse(await G1.NativeG1.readImportText(corpus));
    if (!isObject(doc) || !Array.isArray(doc.inputs)) throw new FormatError('corpus');
    const inputs = doc.inputs as unknown[];
    const outcomes: Record<string, number> = {};
    const perInput: string[] = [];
    for (const b64 of inputs) {
      const code = typeof b64 === 'string' ? await this.fuzzOne(target, decodeBase64(b64)) : 'REJECT_CORPUS';
      outcomes[code] = (outcomes[code] ?? 0) + 1;
      perInput.push(code);
      // TH-FUZ-04 hang bound: the harness requires progress within 10 s of every input
      this.mark('fuzz.progress', ['run', runId, 'n', String(perInput.length)]);
    }
    const unexpected = perInput.filter((c) => c.startsWith('UNEXPECTED_')).length;
    await G1.NativeG1.writeOut(`${runId}.json`, JSON.stringify({ contract: 'G1-FUZZ-1.0', run_id: runId, app: 'B', target,
      count: inputs.length, outcomes, unexpected, per_input: perInput }));
    this.mark('run.done', ['run', runId, 'fuzz', target]);
  }

  // ---------------------------------------------------------------- B16 bridge attacks

  /** Calls the boundary and expects a rejection whose code is in codes (thrown before native code, or a rejected promise). */
  private async expectError(call: () => unknown, codes: Set<string>): Promise<Record<string, unknown>> {
    let pending: unknown;
    try {
      pending = call();
    } catch (e) {
      const code = errorCode(e, true);
      return { outcome: codes.has(code) ? 'PASS' : 'FAIL', code, at: 'call' };
    }
    try {
      const v = await pending;
      return { outcome: 'FAIL', detail: 'accepted', value: String(v) };
    } catch (e) {
      const code = errorCode(e, false);
      return { outcome: codes.has(code) ? 'PASS' : 'FAIL', code, at: 'promise' };
    }
  }

  private async attack(runId: string, caseId: string): Promise<void> {
    this.mark('run.start', ['run', runId, 'attack', caseId]);
    const s = this.state;
    const raw = G1.NativeG1 as unknown as Record<string, (...args: unknown[]) => unknown>;
    const before = await G1.NativeG1.bundleInfo();
    let r: Record<string, unknown>;
    switch (caseId) {
      case 'BRG01': {
        const payloads = ['G1SYN:', 'G1SYN:1:A01', `G1SYN:9:A01:G1SYN-1.0.0:20271001T000000Z:${'A'.repeat(86)}`, 'G1SYN:1:A1:x:y:z',
          'javascript:alert(1)', `G1SYN:1:A01:G1SYN-1.0.0:20271001T000000Z:${'!'.repeat(86)}`];
        const codes: string[] = [];
        for (const p of payloads) codes.push(String((await G1.validateQr(p)).outcome));
        r = { outcome: codes.every((c) => c.startsWith('REJECT_')) ? 'PASS' : 'FAIL', codes };
        break;
      }
      case 'BRG02': {
        const inputs = ['{', '[]', '{"nodes":{}}', '{"nodes":[],"edges":[{"id":1}]}', '{"nodes":[{"id":"N1"}],"edges":[]}'];
        const codes = inputs.map((i) => {
          try {
            parseGraph(i);
            return 'ACCEPTED';
          } catch (e) {
            return e instanceof FormatError ? 'REJECT_FORMAT' : 'UNEXPECTED';
          }
        });
        r = { outcome: codes.every((c) => c === 'REJECT_FORMAT') ? 'PASS' : 'FAIL', codes };
        break;
      }
      case 'BRG03': {
        // a TurboModule exposes only the methods of its spec: an unknown name resolves to no callable at all
        const fn = raw['g1.noSuchMethod'];
        r = typeof fn !== 'function'
          ? { outcome: 'PASS', code: 'UNKNOWN_METHOD', at: 'lookup' }
          : await this.expectError(() => fn({}), new Set(['UNKNOWN_METHOD']));
        break;
      }
      case 'BRG04': {
        const q = await G1.validateQr(`G1SYN:${'A'.repeat(3000)}`);
        const echo = await this.expectError(() => G1.NativeG1.echoAsyncBase64(encodeBase64(new Uint8Array(64 * 1024 + 1))),
          new Set(['PAYLOAD_TOO_LARGE']));
        r = { outcome: q.outcome === 'REJECT_MALFORMED' && echo.outcome === 'PASS' ? 'PASS' : 'FAIL', qr: q.outcome, echo };
        break;
      }
      case 'BRG05': {
        const x = await this.expectError(() => raw.validateQr(42), new Set(['BAD_ARGUMENT']));
        const y = await this.expectError(() => raw.echoAsyncBase64(42), new Set(['BAD_ARGUMENT']));
        const z = await this.expectError(() => raw.setArGuidance('x', 'yes'), new Set(['BAD_ARGUMENT']));
        r = { outcome: [x, y, z].every((e) => e.outcome === 'PASS') ? 'PASS' : 'FAIL', cases: [x, y, z] };
        break;
      }
      case 'BRG06': {
        // the receiving screen is dropped right after the request; the native events that follow must be ignored
        const ignoredBefore = s.ignoredArEvents;
        await s.openAr('[["TRACKING",100],["LOST",300]]');
        const id = s.activeAr;
        s.dropAr();
        await delay(1500);
        if (id !== null) G1.NativeG1.closeAr(id);
        await delay(500);
        r = { outcome: s.activeAr === null && s.ignoredArEvents > ignoredBefore ? 'PASS' : 'FAIL', ignored: s.ignoredArEvents - ignoredBefore };
        break;
      }
      case 'BRG07': {
        const first = G1.scanQr('dup-1');
        const second = await G1.scanQr('dup-1');
        r = { outcome: second.error === 'DUPLICATE_REQUEST' ? 'PASS' : 'FAIL', second };
        void first.then(() => undefined);
        break;
      }
      default:
        r = { outcome: 'FAIL', detail: 'unknown case' };
    }
    const after = await G1.NativeG1.bundleInfo();
    r.state_unchanged = before === after;
    if (before !== after) r.outcome = 'FAIL';
    await G1.NativeG1.writeOut(`${runId}.json`, JSON.stringify({ contract: 'G1-ATTACK-1.0', run_id: runId, app: 'B', case: caseId, ...r }));
    this.mark('run.done', ['run', runId, 'attack', caseId, 'outcome', String(r.outcome)]);
  }
}
