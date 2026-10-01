// Candidate A (Flutter) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// Lab hooks of G1-CIC-1.0 (present in every benchmark lab build). Commands arrive from the common module (Android intent
// extras / iOS launch arguments or URL) and drive the same handlers as the UI.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:g1_native/g1_native.dart';

import '../app_state.dart';
import '../core/bundle_data.dart';
import '../core/crc32.dart';

const Set<String> labCommands = {
  'bench.search-route', 'bench.bridge', 'bench.ui-session', 'bench.idle', 'nav.home', 'nav.details', 'nav.route',
  'nav.open-route-ar', 'lang.set', 'bundle.import', 'bundle.rollback', 'bundle.update', 'qr.inject', 'ar.inject',
  'session.start', 'session.end', 'session.status', 'crash', 'fuzz', 'bridge.attack', 'search.set', 'a11y.seed',
  'bundle.remove', 'map.inspect', 'map.camera',
};

/// G1-UI-SCRIPT-1.0 keyframes (contract ui_session_script; checked against contract.json by the unit tests).
const List<Map<String, Object>> uiScript = [
  {'at_ms': 0, 'action': 'camera', 'center_mm': [72000, 33000], 'zoom': 17.0, 'duration_ms': 2000},
  {'at_ms': 3000, 'action': 'floor', 'floor': 2},
  {'at_ms': 4000, 'action': 'camera', 'center_mm': [272000, 33000], 'zoom': 17.0, 'duration_ms': 4000},
  {'at_ms': 9000, 'action': 'camera', 'center_mm': [272000, 33000], 'zoom': 18.5, 'duration_ms': 2000},
  {'at_ms': 12000, 'action': 'floor', 'floor': 3},
  {'at_ms': 13000, 'action': 'camera', 'center_mm': [472000, 33000], 'zoom': 18.5, 'duration_ms': 5000},
  {'at_ms': 19000, 'action': 'camera', 'center_mm': [472000, 33000], 'zoom': 16.5, 'duration_ms': 3000},
  {'at_ms': 23000, 'action': 'floor', 'floor': 1},
  {'at_ms': 24000, 'action': 'camera', 'center_mm': [72000, 33000], 'zoom': 17.0, 'duration_ms': 5000},
];
const int uiCycleMs = 30000;

/// Runtime-side decoder of the lab command envelope `{"method": name, "args": {...}}` (fuzz target FUZ03).
String decodeEnvelope(String text) {
  if (text.length > 16 * 1024) return 'REJECT_SIZE';
  Object? v;
  try {
    v = jsonDecode(text);
  } on FormatException {
    return 'REJECT_JSON';
  }
  if (v is! Map<String, Object?>) return 'REJECT_SHAPE';
  final m = v['method'];
  if (m is! String || !labCommands.contains(m)) return 'REJECT_METHOD';
  if (v['args'] is! Map<String, Object?>) return 'REJECT_ARGS';
  if (v.length != 2) return 'REJECT_SHAPE';
  return 'ACCEPT';
}

class LabController {
  LabController(this.state);

  final AppState state;
  final List<Map<Object?, Object?>> _queue = [];
  bool _busy = false;
  String? canary;

  int now() => G1Native.nowNanos();

  Future<void> _mark(String name, [List<String> kv = const []]) => G1Native.mark(name, rt: now(), kv: kv);

  Future<void> start() async {
    G1Native.events.listen((e) {
      if (e['type'] == 'command') {
        _enqueue(e);
      } else if (e['type'] == 'ar') {
        state.onArEvent(e['requestId'] as String, e['event'] as String);
      }
    });
    final deadline = now() + 60 * 1000000000;
    while (!state.ready && now() < deadline && (state.bundleInfo == null || state.trusted)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    final launch = await G1Native.launchCommand();
    if (launch != null) _enqueue(launch);
  }

  void _enqueue(Map<Object?, Object?> cmd) {
    _queue.add(cmd);
    if (!_busy) unawaited(_drain());
  }

  Future<void> _drain() async {
    _busy = true;
    while (_queue.isNotEmpty) {
      final cmd = _queue.removeAt(0);
      final name = cmd['name'] as String?;
      Map<String, Object?>? args;
      try {
        final v = jsonDecode(cmd['args'] as String? ?? '{}');
        if (v is Map<String, Object?>) args = v;
      } catch (_) {
        args = null;
      }
      if (name == null || args == null || decodeEnvelope(jsonEncode({'method': name, 'args': args})) != 'ACCEPT') {
        await _mark('command.rejected', ['reason', 'runtime_envelope']);
        continue;
      }
      try {
        await _exec(name, args);
      } catch (e) {
        await _mark('command.failed', ['cmd', name, 'error', e.runtimeType.toString()]);
      }
    }
    _busy = false;
  }

  Future<void> _exec(String name, Map<String, Object?> a) async {
    String str(String k) => a[k] is String ? a[k] as String : throw FormatException('arg $k');
    switch (name) {
      case 'nav.home':
        state.goHome();
      case 'nav.details':
        state.goHome();
        state.openDetails(str('destination'));
      case 'nav.route':
        await _openCaseRoute(a);
      case 'nav.open-route-ar':
        await _openCaseRoute(a);
        await state.openAr();
      case 'ar.inject':
        await _openCaseRoute(a);
        await state.openAr(script: jsonEncode(a['script']));
      case 'lang.set':
        state.setLang(str('lang'));
      case 'bundle.import':
        await state.importBundleFile(str('file'));
      case 'bundle.rollback':
        await state.rollback();
      case 'bundle.update':
        await state.update(str('url'));
      case 'qr.inject':
        await state.injectQr(str('file'));
      case 'session.start':
        await G1Native.sessionStart(str('marker'));
      case 'session.end':
        await G1Native.sessionEnd();
      case 'session.status':
        await G1Native.sessionActive();
      case 'crash':
        await _crash(str('case'), a['canary'] as String?);
      case 'bench.search-route':
        await _benchSearchRoute(str('run_id'), str('kind'));
      case 'bench.bridge':
        await _benchBridge(a);
      case 'bench.ui-session':
        await _window(str('session_id'), (a['warmup_s'] as int?) ?? 60, (a['measure_s'] as int?) ?? 300, script: true);
      case 'bench.idle':
        await _window(str('session_id'), (a['warmup_s'] as int?) ?? 60, (a['measure_s'] as int?) ?? 300, script: false);
      case 'fuzz':
        await _fuzz(str('run_id'), str('target'), str('corpus'));
      case 'bridge.attack':
        await _attack(str('run_id'), str('case'));
      case 'search.set':
        await state.setSearch(str('text'));
      case 'a11y.seed':
        if (!await state.seedDefect(str('defect'))) await _mark('command.rejected', ['reason', 'unknown_defect']);
      case 'bundle.remove':
        await state.removeBundles();
      case 'map.inspect':
        await _mapInspect(str('run_id'));
      case 'map.camera':
        await _mapCamera(a);
    }
  }

  // ---------------------------------------------------------------- B02 map inspection (G1-MAP-INSPECT-1.0)

  /// Registered render view: home screen, the floor through the UI handler, the camera moved without animation.
  Future<void> _mapCamera(Map<String, Object?> a) async {
    final x = a['x_mm'], y = a['y_mm'], zoom = a['zoom'], floor = a['floor'];
    if (x is! int || y is! int || zoom is! num) throw const FormatException('arg camera');
    state.goHome();
    if (floor is int) state.setFloor(floor);
    await state.map?.moveCamera(lonOf(x), latOf(y), zoom.toDouble(), 1); // the binding requires a positive duration
    await state.nextFrame();
    await state.nextFrame();
    await _mark('map.camera.done', ['floor', '${state.floor}']);
  }

  Future<void> _mapInspect(String runId) async {
    await _mark('run.start', ['run', runId, 'map', 'inspect']);
    await state.nextFrame();
    final m = await state.map?.inspect() ?? const {'available': false};
    await G1Native.writeOut('$runId.json', jsonEncode({
      'contract': 'G1-MAP-INSPECT-1.0',
      'run_id': runId,
      'app': 'A',
      'app_floor': state.floor,
      'app_lang': state.lang,
      ...m,
    }));
    await _mark('run.done', ['run', runId, 'map', 'inspect']);
  }

  RouteCase? _case(Object? id) => id is String ? state.data?.routeCases.where((c) => c.id == id).firstOrNull : null;

  Future<void> _openCaseRoute(Map<String, Object?> a) async {
    final c = _case(a['case']);
    state.goHome();
    if (c != null) {
      state.openRoute(c.destination, fromOrigin: c.origin, stepFreeOnly: c.stepFree, blockedEdges: c.blocked);
    } else {
      state.openRoute(a['destination'] as String,
          fromOrigin: a['origin'] as String?, stepFreeOnly: a['step_free'] as bool? ?? false, blockedEdges: const []);
    }
    await state.nextFrame();
    state.computeRoute();
    await state.nextFrame();
  }

  // ---------------------------------------------------------------- B07-SEARCH / B03-ROUTING-GRAPH

  /// Idle point (G1-CIC-1.0): a timed handler never starts inside a frame callback; the loop yields to the event loop
  /// (a zero-duration timer runs after the current frame task has completed).
  Future<void> _idle() => Future<void>(() {});

  Future<void> _benchSearchRoute(String runId, String kind) async {
    final data = state.data;
    if (data == null) return;
    await _mark('run.start', ['run', runId, 'bench', 'search-route']);
    final start = now();
    state.goHome();
    await state.nextFrame();
    final search = <Map<String, Object?>>[];
    for (final q in data.queries) {
      state.setQuery(q.text, fromField: false);
      await state.nextFrame(); // the typed query is on screen before the timed submit
      await _idle();
      final t0 = now();
      final compute = state.submitSearch();
      final t1 = await state.nextFrame();
      final r = state.results!;
      search.add({'id': q.id, 'outcome': r.outcome, 'ids': r.ids, 'compute_ns': compute, 'e2e_ns': t1 - t0});
    }
    state.clearSearch();
    final route = <Map<String, Object?>>[];
    for (final c in data.routeCases) {
      state.openRoute(c.destination, fromOrigin: c.origin, stepFreeOnly: c.stepFree, blockedEdges: c.blocked);
      await state.nextFrame();
      await _idle();
      final t0 = now();
      final compute = state.computeRoute();
      final t1 = await state.nextFrame();
      final r = state.route!;
      route.add({
        'id': c.id,
        'outcome': r.outcome,
        if (r.outcome == 'PATH') 'nodes': r.nodes,
        if (r.outcome == 'PATH') 'length_mm': r.lengthMm,
        if (r.outcome == 'PATH') 'steps': [for (final s in state.steps) s.toJson()],
        if (r.outcome == 'PATH') 'summary': state.summary!.toJson(),
        'compute_ns': compute,
        'e2e_ns': t1 - t0,
      });
      state.back();
    }
    state.goHome();
    final end = now();
    await G1Native.writeOut('$runId.json', jsonEncode({
      'contract': 'G1-BENCH-SR-1.0',
      'run_id': runId,
      'kind': kind,
      'app': 'A',
      'bundle_version': data.version,
      'start_ns': start,
      'end_ns': end,
      'search': search,
      'route': route,
    }));
    await _mark('run.done', ['run', runId, 'bench', 'search-route']);
  }

  // ---------------------------------------------------------------- B11-BRIDGE-OVERHEAD

  final Uint8List _echoBuffer = Uint8List(64 * 1024);

  (int, int) _localEcho(Uint8List payload) {
    final entry = now();
    final n = payload.length < _echoBuffer.length ? payload.length : _echoBuffer.length;
    _echoBuffer.setRange(0, n, payload);
    return ((n << 32) | Crc32.of(_echoBuffer, n), entry);
  }

  static int _offset(int seq, int size) => (seq * 64) % (65536 - size + 1);

  Future<void> _sleepUntil(int dueNs) async {
    final wait = dueNs - now();
    if (wait > 0) await Future<void>.delayed(Duration(microseconds: wait ~/ 1000));
  }

  Future<Map<String, Object?>> _r2n(Uint8List block, int size, int n, int rate, {required bool control}) async {
    final latencies = List<int>.filled(n, -1);
    final offsets = List<int>.filled(n, -1);
    var completed = 0, crcFailures = 0;
    final all = Completer<void>();
    final t0 = now() + 20000000;
    var lastProgress = now();
    for (var i = 0; i < n; i++) {
      await _sleepUntil(t0 + (i * 1e9 / rate).round());
      final off = _offset(i, size);
      final payload = Uint8List.sublistView(block, off, off + size);
      final expected = (size << 32) | Crc32.of(payload);
      final tSend = now();
      offsets[i] = tSend - t0;
      if (control) {
        final (r, entry) = _localEcho(payload);
        latencies[i] = entry - tSend;
        if (r != expected) crcFailures++;
        completed++;
      } else {
        final seq = i;
        unawaited(G1Native.echoAsync(payload).then((reply) {
          latencies[seq] = reply[1] - tSend;
          if (reply[0] != expected) crcFailures++;
          completed++;
          lastProgress = now();
          if (completed == n && !all.isCompleted) all.complete();
        }));
      }
    }
    if (!control && completed < n) {
      while (!all.isCompleted && now() - lastProgress < 10 * 1000000000) {
        await Future.any([all.future, Future<void>.delayed(const Duration(milliseconds: 100))]);
      }
    }
    return {'kind': control ? 'control' : 'measured', 't0_ns': t0, 'send_offsets_ns': offsets, 'latencies_ns': latencies,
      'completed': completed, 'crc_failures': crcFailures};
  }

  Future<Map<String, Object?>> _n2r(Uint8List block, int size, int n, int rate, {required bool control}) async {
    final latencies = List<int>.filled(n, -1);
    final offsets = List<int>.filled(n, -1);
    final expected = List<int>.generate(n, (i) {
      final off = _offset(i, size);
      return Crc32.of(Uint8List.sublistView(block, off, off + size));
    });
    var completed = 0, crcFailures = 0;
    int? firstSent;
    void handler(int seq, int sent, Uint8List payload) {
      final recv = now();
      firstSent ??= sent;
      if (seq < 0 || seq >= n) return;
      latencies[seq] = recv - sent;
      offsets[seq] = sent - firstSent!;
      if (payload.length != size || Crc32.of(payload) != expected[seq]) crcFailures++;
      completed++;
    }

    final t0 = now() + 20000000;
    if (control) {
      for (var i = 0; i < n; i++) {
        await _sleepUntil(t0 + (i * 1e9 / rate).round());
        final off = _offset(i, size);
        handler(i, now(), Uint8List.sublistView(block, off, off + size));
      }
    } else {
      final done = Completer<void>();
      var lastProgress = now();
      final sub = G1Native.n2r.listen((m) {
        if (m.done) {
          if (!done.isCompleted) done.complete();
          return;
        }
        handler(m.seq, m.sentNanos, m.payload);
        lastProgress = now();
      });
      await G1Native.startN2R(size, n, rate);
      while (!done.isCompleted && now() - lastProgress < 10 * 1000000000) {
        await Future.any([done.future, Future<void>.delayed(const Duration(milliseconds: 100))]);
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();
    }
    return {'kind': control ? 'control' : 'measured', 't0_ns': firstSent ?? t0, 'send_offsets_ns': offsets,
      'latencies_ns': latencies, 'completed': completed, 'crc_failures': crcFailures};
  }

  Future<void> _benchBridge(Map<String, Object?> a) async {
    final runId = a['run_id'] as String;
    final workload = a['workload'] as String;
    final order = a['order'] as String? ?? 'control-first';
    final n = (a['messages'] as int?) ?? 1000;
    final rate = (a['rate_hz'] as int?) ?? 200;
    await _mark('run.start', ['run', runId, 'bench', 'bridge', 'workload', workload]);
    final result = <String, Object?>{'contract': 'G1-BENCH-BRIDGE-1.0', 'run_id': runId, 'app': 'A', 'workload': workload,
      'order': order, 'messages': n, 'rate_hz': rate};
    final m = RegExp(r'^(R2N|N2R)\.(64B|4KiB|64KiB)\.(async|sync)$').firstMatch(workload);
    if (m == null) {
      result['outcome'] = 'FAILED';
    } else if (m.group(3) == 'sync') {
      result['outcome'] = 'UNSUPPORTED'; // platform channels have no synchronous path
      result['series'] = const [];
    } else {
      final size = const {'64B': 64, '4KiB': 4096, '64KiB': 65536}[m.group(2)]!;
      final block = state.payloadBlock ??= await G1Native.payloadBlock();
      final series = <Map<String, Object?>>[];
      for (final control in order == 'measured-first' ? const [false, true] : const [true, false]) {
        series.add(m.group(1) == 'R2N'
            ? await _r2n(block, size, n, rate, control: control)
            : await _n2r(block, size, n, rate, control: control));
      }
      result['series'] = series;
      result['outcome'] = series.every((s) => s['completed'] == n) ? 'OK' : 'FAILED';
    }
    await G1Native.writeOut('$runId.json', jsonEncode(result));
    await _mark('run.done', ['run', runId, 'bench', 'bridge', 'outcome', '${result['outcome']}']);
  }

  // ---------------------------------------------------------------- B07/B08 windows (G1-UI-SCRIPT-1.0)

  Future<void> _window(String id, int warmupS, int measureS, {required bool script}) async {
    state.goHome();
    await state.nextFrame();
    final totalMs = (warmupS + measureS) * 1000;
    final events = <(int, Map<String, Object>?, String?)>[(0, null, 'warmup.start'), (warmupS * 1000, null, 'measure.start')];
    if (script) {
      for (var cycle = 0; cycle < totalMs; cycle += uiCycleMs) {
        for (final k in uiScript) {
          final at = cycle + (k['at_ms'] as int);
          if (at < totalMs) events.add((at, k, null));
        }
      }
    }
    events.sort((x, y) => x.$1.compareTo(y.$1));
    final start = now();
    for (final (at, k, phase) in events) {
      await _sleepUntil(start + at * 1000000);
      if (phase != null) {
        await _mark('session.window', ['session', id, 'phase', phase]);
      } else if (k!['action'] == 'floor') {
        state.setFloor(k['floor'] as int);
      } else {
        final c = (k['center_mm'] as List).cast<int>();
        unawaited(state.map?.moveCamera(lonOf(c[0]), latOf(c[1]), (k['zoom'] as num).toDouble(), k['duration_ms'] as int));
      }
    }
    await _sleepUntil(start + totalMs * 1000000);
    await _mark('session.window', ['session', id, 'phase', 'end']);
  }

  // ---------------------------------------------------------------- B16 crash fixtures

  Future<void> _crash(String caseId, String? canaryValue) async {
    canary = canaryValue; // held in app state; must never reach a trace
    await _mark('crash.trigger', ['case', caseId]);
    switch (caseId) {
      case 'CR1':
        try {
          throw StateError('G1 synthetic CR1');
        } on StateError catch (e) {
          await G1Native.writeOut('crash-CR1.json', jsonEncode({'case': 'CR1', 'handled': true, 'type': e.runtimeType.toString()}));
        }
      case 'CR2':
        SchedulerBinding.instance.addPostFrameCallback((_) => throw StateError('G1 synthetic CR2'));
        SchedulerBinding.instance.scheduleFrame();
      case 'CR3':
      case 'CR4':
        await G1Native.crash(caseId);
      case 'CR6':
        final hog = <Uint8List>[];
        while (true) {
          hog.add(Uint8List(16 * 1024 * 1024)..fillRange(0, 16 * 1024 * 1024, 1));
          await Future<void>.delayed(Duration.zero);
        }
    }
  }

  // ---------------------------------------------------------------- B16 fuzz targets

  Future<String> _fuzzOne(String target, Uint8List input) async {
    final text = utf8.decode(input, allowMalformed: true);
    try {
      switch (target) {
        case 'FUZ01':
          return (await G1Native.validateQr(text))['outcome'] as String;
        case 'FUZ02':
          parseGraph(text);
          return 'OK';
        default:
          return decodeEnvelope(text);
      }
    } on FormatException {
      return 'REJECT_FORMAT';
    } on PlatformException catch (e) {
      return 'REJECT_${e.code}';
    } catch (e) {
      return 'UNEXPECTED_${e.runtimeType}';
    }
  }

  Future<void> _fuzz(String runId, String target, String corpus) async {
    await _mark('run.start', ['run', runId, 'fuzz', target]);
    final doc = jsonDecode(await G1Native.readImportText(corpus)) as Map<String, Object?>;
    final inputs = (doc['inputs'] as List).cast<String>();
    final outcomes = <String, int>{};
    final perInput = <String>[];
    for (final b64 in inputs) {
      final code = await _fuzzOne(target, base64Decode(b64));
      outcomes[code] = (outcomes[code] ?? 0) + 1;
      perInput.add(code);
      // TH-FUZ-04 hang bound: the harness requires progress within 10 s of every input
      unawaited(_mark('fuzz.progress', ['run', runId, 'n', '${perInput.length}']));
    }
    final unexpected = perInput.where((c) => c.startsWith('UNEXPECTED_')).length;
    await G1Native.writeOut('$runId.json', jsonEncode({'contract': 'G1-FUZZ-1.0', 'run_id': runId, 'app': 'A', 'target': target,
      'count': inputs.length, 'outcomes': outcomes, 'unexpected': unexpected, 'per_input': perInput}));
    await _mark('run.done', ['run', runId, 'fuzz', target]);
  }

  // ---------------------------------------------------------------- B16 bridge attacks

  Future<Map<String, Object?>> _expectError(Future<Object?> Function() call, Set<String> codes) async {
    try {
      final v = await call();
      return {'outcome': 'FAIL', 'detail': 'accepted', 'value': '$v'};
    } on PlatformException catch (e) {
      return {'outcome': codes.contains(e.code) ? 'PASS' : 'FAIL', 'code': e.code};
    } on MissingPluginException {
      return {'outcome': codes.contains('UNKNOWN_METHOD') ? 'PASS' : 'FAIL', 'code': 'UNKNOWN_METHOD'};
    }
  }

  Future<void> _attack(String runId, String caseId) async {
    await _mark('run.start', ['run', runId, 'attack', caseId]);
    final before = jsonEncode(await G1Native.bundleInfo());
    Map<String, Object?> r;
    switch (caseId) {
      case 'BRG01':
        final payloads = ['G1SYN:', 'G1SYN:1:A01', 'G1SYN:9:A01:G1SYN-1.0.0:20271001T000000Z:${'A' * 86}', 'G1SYN:1:A1:x:y:z',
          'javascript:alert(1)', 'G1SYN:1:A01:G1SYN-1.0.0:20271001T000000Z:${'!' * 86}'];
        final codes = [for (final p in payloads) (await G1Native.validateQr(p))['outcome'] as String];
        r = {'outcome': codes.every((c) => c.startsWith('REJECT_')) ? 'PASS' : 'FAIL', 'codes': codes};
      case 'BRG02':
        final inputs = ['{', '[]', '{"nodes":{}}', '{"nodes":[],"edges":[{"id":1}]}', '{"nodes":[{"id":"N1"}],"edges":[]}'];
        final codes = <String>[];
        for (final i in inputs) {
          try {
            parseGraph(i);
            codes.add('ACCEPTED');
          } on FormatException {
            codes.add('REJECT_FORMAT');
          }
        }
        r = {'outcome': codes.every((c) => c == 'REJECT_FORMAT') ? 'PASS' : 'FAIL', 'codes': codes};
      case 'BRG03':
        r = await _expectError(() => G1Native.rawCall('g1.noSuchMethod', const {}), {'UNKNOWN_METHOD'});
      case 'BRG04':
        final a = await G1Native.validateQr('G1SYN:${'A' * 3000}');
        final b = await _expectError(() => G1Native.echoAsync(Uint8List(64 * 1024 + 1)), {'PAYLOAD_TOO_LARGE'});
        r = {'outcome': a['outcome'] == 'REJECT_MALFORMED' && b['outcome'] == 'PASS' ? 'PASS' : 'FAIL', 'qr': a['outcome'], 'echo': b};
      case 'BRG05':
        final x = await _expectError(() => G1Native.rawCall('validateQr', {'payload': 42}), {'BAD_ARGUMENT'});
        final y = await _expectError(() => G1Native.rawCall('echoAsync', {'payload': 'text'}), {'BAD_ARGUMENT'});
        final z = await _expectError(() => G1Native.rawCall('setArGuidance', {'requestId': 'x', 'allowed': 'yes'}), {'BAD_ARGUMENT'});
        r = {'outcome': [x, y, z].every((e) => e['outcome'] == 'PASS') ? 'PASS' : 'FAIL', 'cases': [x, y, z]};
      case 'BRG06':
        // the receiving screen is dropped right after the request; the native events that follow must be ignored
        final ignoredBefore = state.ignoredArEvents;
        await state.openAr(script: '[["TRACKING",100],["LOST",300]]');
        final id = state.activeAr;
        state.dropAr();
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        if (id != null) await G1Native.closeAr(id);
        await Future<void>.delayed(const Duration(milliseconds: 500));
        r = {'outcome': state.activeAr == null && state.ignoredArEvents > ignoredBefore ? 'PASS' : 'FAIL',
          'ignored': state.ignoredArEvents - ignoredBefore};
      case 'BRG07':
        final first = G1Native.scanQr('dup-1');
        final second = await G1Native.scanQr('dup-1');
        r = {'outcome': second['error'] == 'DUPLICATE_REQUEST' ? 'PASS' : 'FAIL', 'second': second};
        unawaited(first.then((_) {}));
      default:
        r = {'outcome': 'FAIL', 'detail': 'unknown case'};
    }
    final after = jsonEncode(await G1Native.bundleInfo());
    r['state_unchanged'] = before == after;
    if (before != after) r['outcome'] = 'FAIL';
    await G1Native.writeOut('$runId.json', jsonEncode({'contract': 'G1-ATTACK-1.0', 'run_id': runId, 'app': 'A', 'case': caseId, ...r}));
    await _mark('run.done', ['run', runId, 'attack', caseId, 'outcome', '${r['outcome']}']);
  }
}
