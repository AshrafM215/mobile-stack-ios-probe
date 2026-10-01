// Candidate A (Flutter) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// Application state and the handlers shared by the UI and the lab hooks (the lab hooks call the same handlers).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:g1_native/g1_native.dart';

import 'core/bundle_data.dart';
import 'core/route.dart';
import 'core/search.dart';
import 'core/steps.dart';
import 'core/strings.dart';
import 'core/style.dart' as style;

enum ScreenKind { home, details, route, fallback, qr, settings }

class ScreenEntry {
  const ScreenEntry(this.kind, [this.destination]);

  final ScreenKind kind;
  final String? destination;
}

/// Commands from the state to the map view (the map binding is asynchronous).
abstract class MapPort {
  Future<void> setFloor(int floor);
  Future<void> setLanguage(String lang);
  Future<void> setRoute(Map<String, Object?> featureCollection);
  Future<void> moveCamera(double lon, double lat, double zoom, int durationMs);
  Future<void> reload(String style);
}

const String labUpdateOrigin = 'https://localhost:8443/';
const String defaultUpdateUrl = 'https://localhost:8443/update/G1SYN-update.zip';

double lonOf(int xMm) => xMm * 100 / 11131949079;
double latOf(int yMm) => yMm * 10 / 1105742727;

class AppState extends ChangeNotifier {
  AppState(this._strings);

  final Map<String, Strings> _strings;
  String lang = 'ar';
  Strings get s => _strings[lang]!;
  Strings strings(String l) => _strings[l]!;

  Map<String, Object?>? bundleInfo;
  BundleData? data;
  SearchIndex? index;
  RouteGraph? graph;
  Map<String, GraphNode> nodes = const {};
  String? initialStyle;
  String arAvailability = 'UNKNOWN';

  final List<ScreenEntry> stack = [const ScreenEntry(ScreenKind.home)];
  ScreenEntry get top => stack.last;
  int floor = 1;

  String query = '';
  int queryEpoch = 0; // bumps when the field must show `query` (lab hooks, clear)
  SearchResult? results;

  String origin = 'N0001';
  bool stepFree = false;
  List<String> blocked = const [];
  RouteResult? route;
  List<RouteStep> steps = const [];
  RouteSummary? summary;

  Map<String, Object?>? qrOutcome;
  String? lastResult;
  String? updateStatus;
  int updatePercent = 0;

  MapPort? map;
  bool styleLoaded = false;
  bool _homeShown = false;
  bool _ready = false;
  int _arCounter = 0;
  String? activeAr;

  bool get trusted => bundleInfo?['state'] == 'VALID' && data != null;

  int now() => G1Native.nowNanos();

  void _mark(String name, [List<String> kv = const []]) => unawaited(G1Native.mark(name, rt: now(), kv: kv));

  // ---------------- start ----------------

  Future<void> boot() async {
    bundleInfo = await G1Native.ensureBundle();
    _loadData();
    arAvailability = await G1Native.arAvailability();
    notifyListeners();
  }

  void _loadData() {
    data = null;
    index = null;
    graph = null;
    nodes = const {};
    initialStyle = null;
    final info = bundleInfo;
    if (info == null || info['state'] != 'VALID') return;
    try {
      final d = BundleData.load(info['version'] as String, info['dir'] as String);
      data = d;
      index = SearchIndex(d.destinations);
      graph = RouteGraph(d.graph);
      nodes = {for (final n in d.graph.nodes) n.id: n};
      initialStyle = style.buildStyle(d.styleJson, d.dir, floor, lang);
      if (!d.entrances.contains(origin) && d.entrances.isNotEmpty) origin = d.entrances.first;
    } catch (e) {
      data = null;
      _mark('bundle.loaded', ['state', 'PARSE_ERROR']);
    }
  }

  /// Called by the home screen once its search field is enabled and by the map once the style is loaded.
  void homeShown() {
    if (_homeShown) return;
    _homeShown = true;
    _checkReady();
  }

  void onStyleLoaded() {
    styleLoaded = true;
    _mark('map.style.loaded', ['floor', '$floor']);
    _checkReady();
  }

  void _checkReady() {
    if (_ready || !_homeShown || !styleLoaded || !trusted || index == null) return;
    _ready = true;
    final rt = now();
    // the first frame callback after the READY predicate holds (G1-CIC-1.0 frame rule)
    SchedulerBinding.instance.scheduleFrameCallback((_) => unawaited(G1Native.reportReady(rt)));
  }

  bool get ready => _ready;

  void onResumed() {
    final rt = now();
    SchedulerBinding.instance.scheduleFrameCallback((_) => unawaited(G1Native.reportResumeReady(rt)));
  }

  // ---------------- navigation ----------------

  void _push(ScreenEntry e, String screenId) {
    stack.add(e);
    _mark('screen.shown', ['screen', screenId]);
    notifyListeners();
  }

  void back() {
    if (stack.length > 1) stack.removeLast();
    if (top.kind == ScreenKind.home) _mark('screen.shown', ['screen', 'S01']);
    notifyListeners();
  }

  void goHome() {
    stack
      ..clear()
      ..add(const ScreenEntry(ScreenKind.home));
    _mark('screen.shown', ['screen', 'S01']);
    notifyListeners();
  }

  void setLang(String l) {
    if (l != 'ar' && l != 'en' || l == lang) return;
    lang = l;
    _mark('lang.changed', ['lang', l]);
    unawaited(map?.setLanguage(l));
    notifyListeners();
  }

  void toggleLang() => setLang(lang == 'ar' ? 'en' : 'ar');

  void setFloor(int f) {
    if (f < 1 || f > 3 || f == floor) return;
    floor = f;
    _mark('floor.changed', ['floor', '$f']);
    unawaited(map?.setFloor(f));
    notifyListeners();
  }

  // ---------------- search ----------------

  void setQuery(String text, {bool fromField = true}) {
    query = text;
    if (!fromField) queryEpoch++;
    notifyListeners();
  }

  /// Submit handler of home.search.submit; returns the compute-only duration (ns).
  int submitSearch() {
    final idx = index;
    if (idx == null || !trusted) {
      results = SearchResult('NO_MATCH', const []);
      notifyListeners();
      return 0;
    }
    final t0 = now();
    final r = idx.search(query);
    final compute = now() - t0;
    results = r;
    _mark('search.result', ['outcome', r.outcome, 'count', '${r.ids.length}']);
    notifyListeners();
    return compute;
  }

  void clearSearch() {
    query = '';
    queryEpoch++;
    results = null;
    notifyListeners();
  }

  // ---------------- destination and route ----------------

  void openDetails(String id) {
    if (data?.byId[id] == null) return;
    _push(ScreenEntry(ScreenKind.details, id), 'S04');
  }

  void showOnMap(String id) {
    final d = data?.byId[id];
    final n = d == null ? null : nodes[d.node];
    goHome();
    if (d == null || n == null) return;
    setFloor(d.floor);
    unawaited(map?.moveCamera(lonOf(n.xMm), latOf(n.yMm), 19, 600));
  }

  void openRoute(String destinationId, {String? fromOrigin, bool? stepFreeOnly, List<String> blockedEdges = const []}) {
    if (fromOrigin != null) origin = fromOrigin;
    if (stepFreeOnly != null) stepFree = stepFreeOnly;
    blocked = blockedEdges;
    route = null;
    steps = const [];
    summary = null;
    unawaited(map?.setRoute(style.emptyFeatures));
    _push(ScreenEntry(ScreenKind.route, destinationId), 'S07');
  }

  void setOrigin(String id) {
    origin = id;
    notifyListeners();
  }

  void setStepFree(bool v) {
    stepFree = v;
    notifyListeners();
  }

  String? get routeDestination => top.kind == ScreenKind.route ? top.destination : null;

  /// Handler of route.compute; returns the compute-only duration (ns).
  int computeRoute() {
    final destId = routeDestination;
    final d = destId == null ? null : data?.byId[destId];
    final g = graph;
    if (!trusted || g == null) {
      route = RouteResult('REJECT_UNTRUSTED');
      steps = const [];
      summary = null;
      _mark('route.result', ['outcome', 'REJECT_UNTRUSTED']);
      notifyListeners();
      return 0;
    }
    final t0 = now();
    RouteResult r;
    var st = const <RouteStep>[];
    RouteSummary? sum;
    if (d == null) {
      r = RouteResult('REJECT_UNKNOWN');
    } else {
      r = g.route(origin, d.node, stepFree: stepFree, blocked: blocked);
      if (r.outcome == 'PATH') {
        final (a, b) = routeSteps(g, nodes, r.nodes, d);
        st = a;
        sum = b;
      }
    }
    final compute = now() - t0;
    route = r;
    steps = st;
    summary = sum;
    _mark('route.result', ['outcome', r.outcome, 'steps', '${st.length}']);
    unawaited(map?.setRoute(r.outcome == 'PATH' ? style.routeFeatures(data!, g, r.nodes) : style.emptyFeatures));
    notifyListeners();
    return compute;
  }

  bool get guidanceAllowed => trusted && route?.outcome == 'PATH';

  String _arTexts() => jsonEncode({
        'arrow': s.t('ar.arrow'),
        'close': s.t('ar.close'),
        'tracking': s.t('ar.tracking.ok'),
        'no_pose': s.t('ar.no_pose'),
        'limited': s.t('ar.tracking.limited'),
        'lost': s.t('ar.tracking.lost'),
        'paused': s.t('ar.paused'),
        'initializing': s.t('ar.initializing'),
      });

  /// Handler of route.ar: the native AR screen when supported (or injected in lab), otherwise the text fallback.
  Future<void> openAr({String? script}) async {
    if (script == null && arAvailability != 'SUPPORTED') {
      _push(const ScreenEntry(ScreenKind.fallback), 'S09');
      _mark('fallback.shown', ['reason', arAvailability]);
      return;
    }
    final id = 'ar-${++_arCounter}';
    activeAr = id;
    await G1Native.startAr(id, script: script, texts: _arTexts());
    if (guidanceAllowed) await G1Native.setArGuidance(id, true);
  }

  int ignoredArEvents = 0;

  void onArEvent(String requestId, String json) {
    if (requestId != activeAr) {
      ignoredArEvents++; // late events for a request whose receiving screen is gone are ignored (BRG06)
      return;
    }
    final e = jsonDecode(json) as Map<String, Object?>;
    if (e['type'] == 'closed') activeAr = null;
  }

  /// The receiving screen of the AR request goes away (navigation); later events for it are ignored.
  void dropAr() => activeAr = null;

  // ---------------- QR ----------------

  Future<void> scanQr() async {
    final r = await G1Native.scanQr('qr-${now()}');
    final payload = r['payload'] as String?;
    if (payload == null) {
      _showQr({'outcome': r['error'] as String? ?? 'CANCELLED'});
      return;
    }
    _showQr(await G1Native.validateQr(payload));
  }

  /// Lab hook qr.inject: decode a synthetic image through the common decoder, then the same validation.
  Future<void> injectQr(String file) async {
    final payload = await G1Native.decodeQrImport(file);
    _showQr(payload == null ? {'outcome': 'NO_CODE'} : await G1Native.validateQr(payload));
  }

  void _showQr(Map<String, Object?> outcome) {
    qrOutcome = outcome;
    _mark('qr.result', ['outcome', '${outcome['outcome']}']);
    if (top.kind == ScreenKind.qr) {
      notifyListeners();
    } else {
      _push(const ScreenEntry(ScreenKind.qr), 'QR');
    }
  }

  // ---------------- data and trust ----------------

  void openSettings() {
    if (top.kind != ScreenKind.settings) _push(const ScreenEntry(ScreenKind.settings), 'SETTINGS');
  }

  Future<void> _afterBundleChange(String code) async {
    lastResult = code;
    bundleInfo = await G1Native.bundleInfo();
    final before = data?.version;
    _loadData();
    if (data?.version != before) {
      results = null;
      route = null;
      steps = const [];
      summary = null;
      final st = initialStyle;
      if (st != null) {
        styleLoaded = false;
        unawaited(map?.reload(st));
      }
    }
    openSettings();
    notifyListeners();
  }

  Future<String> importBundleFile(String name) async {
    final code = await G1Native.importBundleFile(name);
    await _afterBundleChange(code);
    return code;
  }

  Future<String> rollback() async {
    final code = await G1Native.rollback();
    await _afterBundleChange(code);
    return code;
  }

  /// Lab update with the candidate's standard HTTP client (dart:io HttpClient), lab origin only.
  Future<String> update([String url = defaultUpdateUrl]) async {
    openSettings();
    if (!url.startsWith(labUpdateOrigin)) {
      updateStatus = 'failed';
      notifyListeners();
      return 'REJECT_URL';
    }
    // dart:io has its own TLS stack (the Android network security config does not apply): the lab CA is the only anchor.
    final ctx = SecurityContext(withTrustedRoots: false)..setTrustedCertificatesBytes(utf8.encode(await G1Native.labCa()));
    final client = HttpClient(context: ctx)..connectionTimeout = const Duration(seconds: 10);
    updateStatus = 'pending';
    updatePercent = 0;
    _mark('update.state', ['state', 'pending']);
    notifyListeners();
    final slow = Timer(const Duration(seconds: 10), () {
      if (updateStatus == 'pending') {
        updateStatus = 'slow';
        _mark('update.state', ['state', 'slow']);
        notifyListeners();
      }
    });
    try {
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close().timeout(const Duration(seconds: 30));
      if (res.statusCode == 404) {
        await res.drain<void>();
        updateStatus = 'none';
        _mark('update.state', ['state', 'none']);
        notifyListeners();
        return 'NONE';
      }
      if (res.statusCode != 200) throw const HttpException('status');
      final total = res.contentLength;
      final buf = BytesBuilder(copy: false);
      await for (final chunk in res.timeout(const Duration(seconds: 30))) {
        buf.add(chunk);
        if (buf.length > 64 * 1024 * 1024) throw const HttpException('too large');
        if (total > 0) {
          updatePercent = (buf.length * 100) ~/ total;
          notifyListeners();
        }
      }
      updateStatus = 'done';
      _mark('update.state', ['state', 'downloaded']);
      final code = await G1Native.importBundleBytes(buf.takeBytes(), 'update');
      await _afterBundleChange(code);
      return code;
    } catch (_) {
      updateStatus = 'failed';
      _mark('update.state', ['state', 'failed']);
      notifyListeners();
      return 'FAILED';
    } finally {
      slow.cancel();
      client.close(force: true);
    }
  }

  // ---------------- frames ----------------

  /// Completes at the first frame callback after the current state has been applied.
  /// Resolves with now() at the first frame callback after the frame that applied the current state (G1-CIC-1.0 frame
  /// rule): the post-frame callback of the frame that built the state registers a transient callback for the next frame.
  Future<int> nextFrame() {
    final c = Completer<int>();
    final binding = SchedulerBinding.instance;
    binding.addPostFrameCallback((_) => binding.scheduleFrameCallback((_) => c.complete(now())));
    binding.scheduleFrame();
    return c.future;
  }

  Uint8List? payloadBlock;
}
