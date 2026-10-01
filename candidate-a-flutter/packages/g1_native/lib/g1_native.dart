// Candidate A adapter to the G1 common native module (Dart side) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
//
// Runtime boundary of candidate A: MethodChannel "g1/native" (asynchronous only; there is no synchronous platform-channel
// path), EventChannel "g1/events" (AR events, lab commands) and EventChannel "g1/n2r" (native-to-runtime bridge workload).
// The monotonic clock is read directly through dart:ffi (CLOCK_BOOTTIME on Android, CLOCK_MONOTONIC_RAW on iOS), the
// same clock the common module stamps its markers with.
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';

final class _Timespec extends Struct {
  @Long()
  external int tvSec;
  @Long()
  external int tvNsec;
}

typedef _ClockGettimeC = Int32 Function(Int32, Pointer<_Timespec>);
typedef _ClockGettimeDart = int Function(int, Pointer<_Timespec>);
typedef _NsecNpC = Uint64 Function(Int32);
typedef _NsecNpDart = int Function(int);

/// Monotonic nanoseconds of the common module clock, read in-process through dart:ffi.
class G1Clock {
  G1Clock._();

  static const int _clockBoottime = 7; // Linux/Android
  static const int _clockMonotonicRaw = 4; // Darwin
  static final Stopwatch _fallback = Stopwatch()..start();
  static Pointer<_Timespec>? _ts;
  static _ClockGettimeDart? _gettime;
  static _NsecNpDart? _nsecNp;
  static bool _resolved = false;

  static void _resolve() {
    _resolved = true;
    try {
      if (Platform.isIOS) {
        _nsecNp = DynamicLibrary.process().lookupFunction<_NsecNpC, _NsecNpDart>('clock_gettime_nsec_np');
      } else if (Platform.isAndroid) {
        DynamicLibrary lib;
        try {
          lib = DynamicLibrary.process();
          lib.lookup('clock_gettime');
        } catch (_) {
          lib = DynamicLibrary.open('libc.so');
        }
        _gettime = lib.lookupFunction<_ClockGettimeC, _ClockGettimeDart>('clock_gettime');
        _ts = calloc<_Timespec>();
      }
    } catch (_) {
      _gettime = null;
      _nsecNp = null;
    }
  }

  /// True when the native clock is used (false only in host-side unit tests).
  static bool get native {
    if (!_resolved) _resolve();
    return _gettime != null || _nsecNp != null;
  }

  static int nowNanos() {
    if (!_resolved) _resolve();
    final np = _nsecNp;
    if (np != null) return np(_clockMonotonicRaw);
    final g = _gettime;
    final ts = _ts;
    if (g != null && ts != null) {
      g(_clockBoottime, ts);
      return ts.ref.tvSec * 1000000000 + ts.ref.tvNsec;
    }
    return _fallback.elapsedMicroseconds * 1000;
  }
}

/// One N2R message or the end-of-series record.
class N2RMessage {
  N2RMessage(this.seq, this.sentNanos, this.payload, {this.done = false, this.sent = 0, this.dropped = 0});

  final int seq;
  final int sentNanos;
  final Uint8List payload;
  final bool done;
  final int sent;
  final int dropped;
}

class G1Native {
  G1Native._();

  static const MethodChannel _ch = MethodChannel('g1/native');
  static const EventChannel _events = EventChannel('g1/events');
  static const EventChannel _n2r = EventChannel('g1/n2r');
  static Stream<Map<Object?, Object?>>? _eventStream;
  static Stream<N2RMessage>? _n2rStream;

  static int nowNanos() => G1Clock.nowNanos();

  static Future<T?> _call<T>(String method, [Map<String, Object?>? args]) => _ch.invokeMethod<T>(method, args);

  /// Low-level access for the bridge-attack cases (BRG03/BRG05): any method name and arguments.
  static Future<Object?> rawCall(String method, Object? args) => _ch.invokeMethod<Object?>(method, args);

  static Stream<Map<Object?, Object?>> get events =>
      _eventStream ??= _events.receiveBroadcastStream().map((e) => (e as Map<Object?, Object?>)).asBroadcastStream();

  static Stream<N2RMessage> get n2r => _n2rStream ??= _n2r.receiveBroadcastStream().map((e) {
        final m = e as Map<Object?, Object?>;
        if (m['done'] == true) {
          return N2RMessage(-1, 0, Uint8List(0), done: true, sent: m['sent'] as int, dropped: m['dropped'] as int);
        }
        return N2RMessage(m['seq'] as int, m['sent'] as int, m['payload'] as Uint8List);
      }).asBroadcastStream();

  /// Marker through the common module (values must be ids, codes, enums or numbers).
  static Future<void> mark(String name, {int rt = -1, List<String> kv = const []}) =>
      _call<void>('mark', {'name': name, 'rt': rt, 'kv': kv});

  static Future<void> reportReady(int rt) => _call<void>('reportReady', {'rt': rt});

  static Future<void> reportResumeReady(int rt) => _call<void>('reportResumeReady', {'rt': rt});

  static Future<Map<String, Object?>> ensureBundle() async =>
      jsonDecode((await _call<String>('ensureBundle'))!) as Map<String, Object?>;

  static Future<Map<String, Object?>> bundleInfo() async =>
      jsonDecode((await _call<String>('bundleInfo'))!) as Map<String, Object?>;

  static Future<String> importBundleFile(String name) async => (await _call<String>('importBundleFile', {'name': name}))!;

  static Future<String> importBundleBytes(Uint8List zip, String source) async =>
      (await _call<String>('importBundleBytes', {'bytes': zip, 'source': source}))!;

  static Future<String> rollback() async => (await _call<String>('rollback'))!;

  /// Lab hook bundle.remove (Android lab hook; the common module removes every stored bundle).
  static Future<String> removeBundles() async => (await _call<String>('removeBundles'))!;

  static Future<Map<String, Object?>> validateQr(String? payload) async =>
      jsonDecode((await _call<String>('validateQr', {'payload': payload}))!) as Map<String, Object?>;

  static Future<String?> decodeQrImport(String name) => _call<String>('decodeQrImport', {'name': name});

  /// {payload, error}: exactly one is non-null.
  static Future<Map<Object?, Object?>> scanQr(String requestId) async =>
      (await _call<Map<Object?, Object?>>('scanQr', {'requestId': requestId}))!;

  static Future<String> arAvailability() async => (await _call<String>('arAvailability'))!;

  static Future<void> startAr(String requestId, {String? script, required String texts}) =>
      _call<void>('startAr', {'requestId': requestId, 'script': script, 'texts': texts});

  static Future<void> closeAr(String requestId) => _call<void>('closeAr', {'requestId': requestId});

  static Future<void> setArGuidance(String requestId, bool allowed) =>
      _call<void>('setArGuidance', {'requestId': requestId, 'allowed': allowed});

  static Future<Uint8List> payloadBlock() async => (await _call<Uint8List>('payloadBlock'))!;

  /// [length << 32 | crc, native entry nanos]
  static Future<Int64List> echoAsync(Uint8List payload) async =>
      (await _call<Int64List>('echoAsync', {'payload': payload}))!;

  static Future<void> startN2R(int size, int count, int rateHz) =>
      _call<void>('startN2R', {'size': size, 'count': count, 'rateHz': rateHz});

  static Future<bool> sessionStart(String marker) async => (await _call<bool>('sessionStart', {'marker': marker}))!;

  static Future<bool> sessionActive() async => (await _call<bool>('sessionActive'))!;

  static Future<void> sessionEnd() => _call<void>('sessionEnd');

  static Future<void> crash(String caseId) => _call<void>('crash', {'case': caseId});

  static Future<String> writeOut(String name, String text) async =>
      (await _call<String>('writeOut', {'name': name, 'text': text}))!;

  static Future<String> readImportText(String name) async => (await _call<String>('readImportText', {'name': name}))!;

  static Future<Uint8List> readImportBytes(String name) async =>
      (await _call<Uint8List>('readImportBytes', {'name': name}))!;

  static Future<String> labCa() async => (await _call<String>('labCa'))!;

  static Future<String> readBundleFile(String path) async => (await _call<String>('readBundleFile', {'path': path}))!;

  /// The lab command delivered with the launch (Android intent extras / iOS launch arguments), once.
  static Future<Map<Object?, Object?>?> launchCommand() => _call<Map<Object?, Object?>>('launchCommand');
}
