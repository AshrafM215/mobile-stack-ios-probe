// Candidate B (React Native) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// Application state and the handlers shared by the UI and the lab hooks (the lab hooks call the same handlers).
import * as G1 from 'g1-native';

import { BundleData, type GraphNode } from './core/bundleData';
import { decodeBase64 } from './core/base64';
import { RouteGraph, type RouteResult } from './core/route';
import { SearchIndex, type SearchResult } from './core/search';
import { routeSteps, type RouteStep, type RouteSummary } from './core/steps';
import { Strings } from './core/strings';
import { emptyFeatures, routeFeatures, splitStyle, type SplitStyle } from './core/style';

export type ScreenKind = 'home' | 'details' | 'route' | 'fallback' | 'qr' | 'settings';

export interface ScreenEntry {
  kind: ScreenKind;
  destination?: string;
}

/** Imperative camera and inspection of the map binding. */
export interface CameraPort {
  easeTo(lon: number, lat: number, zoom: number, durationMs: number): void;
  /** Lab hook map.inspect: the map state as the binding reports it (G1-MAP-INSPECT-1.0). */
  inspect(): Promise<Record<string, unknown>>;
}

/** Seeded accessibility defects of the lab build (a11y.seed; detector validation of the B05 tooling, never on by default). */
export const SEED_DEFECTS: ReadonlySet<string> = new Set([
  'missing-label', 'duplicate-label', 'small-target', 'low-contrast', 'focus-trap', 'unlabeled-image', 'wrong-role',
  'missing-state-announcement',
]);

export const LAB_UPDATE_ORIGIN = 'https://localhost:8443/';
export const DEFAULT_UPDATE_URL = 'https://localhost:8443/update/G1SYN-update.zip';

export const lonOf = (xMm: number): number => (xMm * 100) / 11131949079;
export const latOf = (yMm: number): number => (yMm * 10) / 1105742727;

const INACTIVITY_MS = 30000;

/** One GET through React Native's standard networking with the inactivity watchdog of the update transfer policy. */
function download(url: string, onProgress: (percent: number) => void): Promise<{ status: number; body: Uint8Array | null }> {
  return new Promise((resolve, reject) => {
    const xhr = new XMLHttpRequest();
    let watchdog: ReturnType<typeof setTimeout> | null = null;
    const stop = () => {
      if (watchdog !== null) clearTimeout(watchdog);
      watchdog = null;
    };
    const arm = () => {
      stop();
      watchdog = setTimeout(() => {
        xhr.abort();
        reject(new Error('inactivity timeout'));
      }, INACTIVITY_MS);
    };
    xhr.open('GET', url);
    xhr.responseType = 'arraybuffer';
    xhr.onprogress = (e) => {
      arm();
      if (e.lengthComputable && e.total > 0) onProgress(Math.floor((e.loaded * 100) / e.total));
    };
    xhr.onload = () => {
      stop();
      resolve({ status: xhr.status, body: xhr.status === 200 ? new Uint8Array(xhr.response as ArrayBuffer) : null });
    };
    xhr.onerror = () => {
      stop();
      reject(new Error('network'));
    };
    arm();
    xhr.send();
  });
}

export class AppState {
  // ---------------- store plumbing (useSyncExternalStore) ----------------
  private readonly listeners = new Set<() => void>();
  private revision = 0;
  private readonly commitWaiters: Array<() => void> = [];

  subscribe = (listener: () => void): (() => void) => {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  };

  getSnapshot = (): number => this.revision;

  notify(): void {
    this.revision++;
    this.listeners.forEach((l) => l());
  }

  /** Called by the root component's layout effect after every commit. */
  onCommit(): void {
    const waiters = this.commitWaiters.splice(0);
    waiters.forEach((w) => w());
  }

  /**
   * Resolves at the first frame callback after the frame that applied the current state (G1-CIC-1.0 frame rule): the
   * committed tree is mounted in the frame of the first requestAnimationFrame after the commit, so the second one is the
   * first frame callback after it.
   */
  nextFrame(): Promise<number> {
    return new Promise((resolve) => {
      this.commitWaiters.push(() => requestAnimationFrame(() => requestAnimationFrame(() => resolve(G1.nowNanos()))));
      this.notify();
    });
  }

  // ---------------- state ----------------
  lang: 'ar' | 'en' = 'ar';
  bundleInfo: Record<string, unknown> | null = null;
  data: BundleData | null = null;
  index: SearchIndex | null = null;
  graph: RouteGraph | null = null;
  nodes = new Map<string, GraphNode>();
  style: SplitStyle | null = null;
  styleGeneration = 0;
  arAvailability = 'UNKNOWN';

  stack: ScreenEntry[] = [{ kind: 'home' }];
  floor = 1;
  query = '';
  queryEpoch = 0;
  results: SearchResult | null = null;

  origin = 'N0001';
  stepFree = false;
  blocked: string[] = [];
  route: RouteResult | null = null;
  steps: RouteStep[] = [];
  summary: RouteSummary | null = null;
  routeFc: Record<string, unknown> = emptyFeatures;

  qrOutcome: Record<string, unknown> | null = null;
  lastResult: string | null = null;
  updateStatus: string | null = null;
  updatePercent = 0;

  camera: CameraPort | null = null;
  styleLoaded = false;
  /** Lab hook a11y.seed: the seeded defect shown on the home screen (null: the clean reference state). */
  seededDefect: string | null = null;
  private homeShownFlag = false;
  private readyFlag = false;
  private arCounter = 0;
  activeAr: string | null = null;
  ignoredArEvents = 0;
  payloadBlock: Uint8Array | null = null;

  constructor(private readonly strings: Record<'ar' | 'en', Strings>) {}

  get s(): Strings {
    return this.strings[this.lang];
  }

  stringsFor(l: 'ar' | 'en'): Strings {
    return this.strings[l];
  }

  get top(): ScreenEntry {
    return this.stack[this.stack.length - 1];
  }

  get trusted(): boolean {
    return this.bundleInfo?.state === 'VALID' && this.data !== null;
  }

  get ready(): boolean {
    return this.readyFlag;
  }

  private mark(name: string, kv: string[] = []): void {
    G1.mark(name, kv);
  }

  // ---------------- start ----------------

  async boot(): Promise<void> {
    this.bundleInfo = await G1.ensureBundle();
    await this.loadData();
    this.arAvailability = await G1.NativeG1.arAvailability();
    this.notify();
  }

  private async loadData(): Promise<void> {
    this.data = null;
    this.index = null;
    this.graph = null;
    this.nodes = new Map();
    this.style = null;
    const info = this.bundleInfo;
    if (!info || info.state !== 'VALID') return;
    try {
      const dirUrl = (await G1.NativeG1.bundleDirectoryUrl()) ?? '';
      const d = await BundleData.load(info.version as string, dirUrl, (p) => G1.NativeG1.readBundleFile(p));
      this.data = d;
      this.index = new SearchIndex(d.destinations);
      this.graph = new RouteGraph(d.graph);
      this.nodes = new Map(d.graph.nodes.map((n) => [n.id, n]));
      this.style = splitStyle(d.styleJson, dirUrl);
      this.styleGeneration++;
      if (!d.entrances.includes(this.origin) && d.entrances.length > 0) this.origin = d.entrances[0];
    } catch {
      this.data = null;
      this.mark('bundle.loaded', ['state', 'PARSE_ERROR']);
    }
  }

  homeShown(): void {
    if (this.homeShownFlag) return;
    this.homeShownFlag = true;
    this.checkReady();
  }

  onStyleLoaded(): void {
    this.styleLoaded = true;
    this.mark('map.style.loaded', ['floor', String(this.floor)]);
    this.checkReady();
  }

  private checkReady(): void {
    if (this.readyFlag || !this.homeShownFlag || !this.styleLoaded || !this.trusted || this.index === null) return;
    this.readyFlag = true;
    const rt = G1.nowNanos();
    requestAnimationFrame(() => G1.NativeG1.reportReady(rt));
  }

  onResumed(): void {
    const rt = G1.nowNanos();
    requestAnimationFrame(() => G1.NativeG1.reportResumeReady(rt));
  }

  // ---------------- navigation ----------------

  private push(e: ScreenEntry, screenId: string): void {
    this.stack = [...this.stack, e];
    this.mark('screen.shown', ['screen', screenId]);
    this.notify();
  }

  back = (): void => {
    if (this.stack.length > 1) this.stack = this.stack.slice(0, -1);
    if (this.top.kind === 'home') this.mark('screen.shown', ['screen', 'S01']);
    this.notify();
  };

  goHome = (): void => {
    this.stack = [{ kind: 'home' }];
    this.mark('screen.shown', ['screen', 'S01']);
    this.notify();
  };

  setLang = (l: string): void => {
    if ((l !== 'ar' && l !== 'en') || l === this.lang) return;
    this.lang = l;
    this.mark('lang.changed', ['lang', l]);
    this.notify();
  };

  toggleLang = (): void => this.setLang(this.lang === 'ar' ? 'en' : 'ar');

  setFloor = (f: number): void => {
    if (f < 1 || f > 3 || f === this.floor) return;
    this.floor = f;
    this.mark('floor.changed', ['floor', String(f)]);
    this.notify();
  };

  // ---------------- search ----------------

  setQuery = (text: string, fromField = true): void => {
    this.query = text;
    if (!fromField) this.queryEpoch++;
    this.notify();
  };

  /** Submit handler of home.search.submit; returns the compute-only duration (ns). */
  submitSearch = (): number => {
    const idx = this.index;
    if (idx === null || !this.trusted) {
      this.results = { outcome: 'NO_MATCH', ids: [] };
      this.notify();
      return 0;
    }
    const t0 = G1.nowNanos();
    const r = idx.search(this.query);
    const compute = G1.nowNanos() - t0;
    this.results = r;
    this.mark('search.result', ['outcome', r.outcome, 'count', String(r.ids.length)]);
    this.notify();
    return compute;
  };

  clearSearch = (): void => {
    this.query = '';
    this.queryEpoch++;
    this.results = null;
    this.notify();
  };

  // ---------------- destination and route ----------------

  openDetails = (id: string): void => {
    if (!this.data?.byId.has(id)) return;
    this.push({ kind: 'details', destination: id }, 'S04');
  };

  showOnMap = (id: string): void => {
    const d = this.data?.byId.get(id);
    const n = d ? this.nodes.get(d.node) : undefined;
    this.goHome();
    if (!d || !n) return;
    this.setFloor(d.floor);
    this.camera?.easeTo(lonOf(n.xMm), latOf(n.yMm), 19, 600);
  };

  openRoute = (destinationId: string, origin?: string | null, stepFree?: boolean, blocked: string[] = []): void => {
    if (origin) this.origin = origin;
    if (stepFree !== undefined) this.stepFree = stepFree;
    this.blocked = blocked;
    this.route = null;
    this.steps = [];
    this.summary = null;
    this.routeFc = emptyFeatures;
    this.push({ kind: 'route', destination: destinationId }, 'S07');
  };

  setOrigin = (id: string): void => {
    this.origin = id;
    this.notify();
  };

  setStepFree = (v: boolean): void => {
    this.stepFree = v;
    this.notify();
  };

  get routeDestination(): string | undefined {
    return this.top.kind === 'route' ? this.top.destination : undefined;
  }

  /** Handler of route.compute; returns the compute-only duration (ns). */
  computeRoute = (): number => {
    const destId = this.routeDestination;
    const d = destId ? this.data?.byId.get(destId) : undefined;
    const g = this.graph;
    if (!this.trusted || g === null) {
      this.route = { outcome: 'REJECT_UNTRUSTED', nodes: [], lengthMm: 0 };
      this.steps = [];
      this.summary = null;
      this.mark('route.result', ['outcome', 'REJECT_UNTRUSTED']);
      this.notify();
      return 0;
    }
    const t0 = G1.nowNanos();
    let r: RouteResult;
    let st: RouteStep[] = [];
    let sum: RouteSummary | null = null;
    if (!d) {
      r = { outcome: 'REJECT_UNKNOWN', nodes: [], lengthMm: 0 };
    } else {
      r = g.route(this.origin, d.node, this.stepFree, this.blocked);
      if (r.outcome === 'PATH') {
        const out = routeSteps(g, this.nodes, r.nodes, d);
        st = out.steps;
        sum = out.summary;
      }
    }
    const compute = G1.nowNanos() - t0;
    this.route = r;
    this.steps = st;
    this.summary = sum;
    this.routeFc = r.outcome === 'PATH' && this.data ? routeFeatures(this.data, g, r.nodes) : emptyFeatures;
    this.mark('route.result', ['outcome', r.outcome, 'steps', String(st.length)]);
    this.notify();
    return compute;
  };

  get guidanceAllowed(): boolean {
    return this.trusted && this.route?.outcome === 'PATH';
  }

  private arTexts(): string {
    const s = this.s;
    return JSON.stringify({
      arrow: s.t('ar.arrow'),
      close: s.t('ar.close'),
      tracking: s.t('ar.tracking.ok'),
      no_pose: s.t('ar.no_pose'),
      limited: s.t('ar.tracking.limited'),
      lost: s.t('ar.tracking.lost'),
      paused: s.t('ar.paused'),
      initializing: s.t('ar.initializing'),
    });
  }

  /** Handler of route.ar: the native AR screen when supported (or injected in lab), otherwise the text fallback. */
  openAr = async (script: string | null = null): Promise<void> => {
    if (script === null && this.arAvailability !== 'SUPPORTED') {
      this.push({ kind: 'fallback' }, 'S09');
      this.mark('fallback.shown', ['reason', this.arAvailability]);
      return;
    }
    const id = `ar-${++this.arCounter}`;
    this.activeAr = id;
    G1.NativeG1.startAr(id, script, this.arTexts());
    if (this.guidanceAllowed) G1.NativeG1.setArGuidance(id, true);
  };

  onArEvent(requestId: string, json: string): void {
    if (requestId !== this.activeAr) {
      this.ignoredArEvents++; // late events for a request whose receiving screen is gone are ignored (BRG06)
      return;
    }
    const e = JSON.parse(json) as Record<string, unknown>;
    if (e.type === 'closed') this.activeAr = null;
  }

  dropAr(): void {
    this.activeAr = null;
  }

  // ---------------- QR ----------------

  scanQr = async (): Promise<void> => {
    const r = await G1.scanQr(`qr-${G1.nowNanos()}`);
    if (r.payload === null) {
      this.showQr({ outcome: r.error ?? 'CANCELLED' });
      return;
    }
    this.showQr(await G1.validateQr(r.payload));
  };

  async injectQr(file: string): Promise<void> {
    const payload = await G1.NativeG1.decodeQrImport(file);
    this.showQr(payload === null ? { outcome: 'NO_CODE' } : await G1.validateQr(payload));
  }

  private showQr(outcome: Record<string, unknown>): void {
    this.qrOutcome = outcome;
    this.mark('qr.result', ['outcome', String(outcome.outcome)]);
    if (this.top.kind === 'qr') this.notify();
    else this.push({ kind: 'qr' }, 'QR');
  }

  // ---------------- data and trust ----------------

  openSettings = (): void => {
    if (this.top.kind !== 'settings') this.push({ kind: 'settings' }, 'SETTINGS');
  };

  private async afterBundleChange(code: string): Promise<void> {
    this.lastResult = code;
    this.bundleInfo = await G1.bundleInfo();
    const before = this.data?.version;
    await this.loadData();
    if (this.data?.version !== before) {
      this.results = null;
      this.route = null;
      this.steps = [];
      this.summary = null;
      this.routeFc = emptyFeatures;
      this.styleLoaded = false;
    }
    this.openSettings();
    this.notify();
  }

  async importBundleFile(name: string): Promise<string> {
    const code = await G1.NativeG1.importBundleFile(name);
    await this.afterBundleChange(code);
    return code;
  }

  async rollback(): Promise<string> {
    const code = await G1.NativeG1.rollback();
    await this.afterBundleChange(code);
    return code;
  }

  /** Lab hook bundle.remove (OFF02): every stored bundle removed; the app shows its no-verified-data state on the home screen. */
  async removeBundles(): Promise<string> {
    const code = await G1.NativeG1.removeBundles();
    this.bundleInfo = await G1.bundleInfo();
    await this.loadData(); // no verified bundle: style null, the map component is unmounted
    this.query = '';
    this.queryEpoch++;
    this.results = null;
    this.route = null;
    this.steps = [];
    this.summary = null;
    this.routeFc = emptyFeatures;
    this.styleLoaded = false;
    this.goHome();
    return code;
  }

  /** Lab hook search.set: the query as if typed (text the input service cannot type), then the UI submit handler. */
  async setSearch(text: string): Promise<void> {
    this.goHome();
    this.setQuery(text, false);
    await this.nextFrame();
    await new Promise<void>((r) => setTimeout(r, 0)); // idle point: outside the frame callback
    this.submitSearch();
  }

  /** Lab hook a11y.seed: shows one seeded defect ("none" restores the clean state); G1MARK a11y.seeded after the frame. */
  async seedDefect(defect: string): Promise<boolean> {
    if (defect !== 'none' && !SEED_DEFECTS.has(defect)) return false;
    this.goHome();
    this.seededDefect = defect === 'none' ? null : defect;
    await this.nextFrame();
    this.mark('a11y.seeded', ['defect', defect]);
    return true;
  }

  /**
   * Lab update with React Native's standard networking (XMLHttpRequest, which fetch is built on; it reports download
   * progress), lab origin only, under the contract's update transfer policy: inactivity timeout 30 s (XMLHttpRequest has
   * no separate connect phase, so the same watchdog covers connect and first byte), no total cap, slow state after 10 s,
   * progress from Content-Length.
   */
  update = async (url: string = DEFAULT_UPDATE_URL): Promise<string> => {
    this.openSettings();
    if (!url.startsWith(LAB_UPDATE_ORIGIN)) {
      this.updateStatus = 'failed';
      this.notify();
      return 'REJECT_URL';
    }
    this.updateStatus = 'pending';
    this.updatePercent = 0;
    this.mark('update.state', ['state', 'pending']);
    this.notify();
    const slow = setTimeout(() => {
      if (this.updateStatus === 'pending') {
        this.updateStatus = 'slow';
        this.mark('update.state', ['state', 'slow']);
        this.notify();
      }
    }, 10000);
    try {
      const res = await download(url, (percent) => {
        if (percent !== this.updatePercent) {
          this.updatePercent = percent;
          this.notify();
        }
      });
      if (res.status === 404) {
        this.updateStatus = 'none';
        this.mark('update.state', ['state', 'none']);
        this.notify();
        return 'NONE';
      }
      if (res.status !== 200 || res.body === null) throw new Error('status');
      if (res.body.length > 64 * 1024 * 1024) throw new Error('too large');
      this.updatePercent = 100;
      this.updateStatus = 'done';
      this.mark('update.state', ['state', 'downloaded']);
      const { encodeBase64 } = await import('./core/base64');
      const code = await G1.NativeG1.importBundleBase64(encodeBase64(res.body), 'update');
      await this.afterBundleChange(code);
      return code;
    } catch {
      this.updateStatus = 'failed';
      this.mark('update.state', ['state', 'failed']);
      this.notify();
      return 'FAILED';
    } finally {
      clearTimeout(slow);
    }
  };

  async ensurePayloadBlock(): Promise<Uint8Array> {
    if (this.payloadBlock === null) this.payloadBlock = decodeBase64(await G1.NativeG1.payloadBlockBase64());
    return this.payloadBlock;
  }
}
