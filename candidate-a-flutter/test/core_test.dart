// Candidate A (Flutter) unit tests - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// The Dart implementations of G1-SEARCH-1.0, G1-ROUTE-1.0, G1-ROUTE-STEPS-1.0 and G1-STYLE-1.0 against the generated
// oracle (spikes/synthetic-data/out), plus strings, lab-hook and envelope checks.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:g1_candidate_a/src/core/bundle_data.dart';
import 'package:g1_candidate_a/src/core/crc32.dart';
import 'package:g1_candidate_a/src/core/format.dart';
import 'package:g1_candidate_a/src/core/route.dart';
import 'package:g1_candidate_a/src/core/search.dart';
import 'package:g1_candidate_a/src/core/steps.dart';
import 'package:g1_candidate_a/src/core/strings.dart';
import 'package:g1_candidate_a/src/core/style.dart';
import 'package:g1_candidate_a/src/lab/lab.dart';

const String out = '../synthetic-data/out';

/// Entries of a stored (method 0) ZIP, enough for the synthetic bundle.
Map<String, Uint8List> storedZip(Uint8List z) {
  final b = ByteData.sublistView(z);
  final eocd = z.length - 22;
  final count = b.getUint16(eocd + 10, Endian.little);
  var p = b.getUint32(eocd + 16, Endian.little);
  final outMap = <String, Uint8List>{};
  for (var i = 0; i < count; i++) {
    final size = b.getUint32(p + 24, Endian.little);
    final nameLen = b.getUint16(p + 28, Endian.little);
    final local = b.getUint32(p + 42, Endian.little);
    final name = utf8.decode(z.sublist(p + 46, p + 46 + nameLen));
    final lName = b.getUint16(local + 26, Endian.little);
    final start = local + 30 + lName;
    outMap[name] = Uint8List.sublistView(z, start, start + size);
    p += 46 + nameLen;
  }
  return outMap;
}

void main() {
  final bundle = storedZip(File('$out/bundle/G1SYN-1.0.0.zip').readAsBytesSync());
  String text(String name) => utf8.decode(bundle[name]!);
  final destinations = parseDestinations(text('destinations.json'));
  final graphData = parseGraph(text('graph.json'));
  final graph = RouteGraph(graphData);
  final nodes = {for (final n in graphData.nodes) n.id: n};
  final byId = {for (final d in destinations) d.id: d};

  test('G1-SEARCH-1.0 agrees with the oracle on all 500 queries', () {
    final index = SearchIndex(destinations);
    final queries = parseQueries(text('query_corpus.json'));
    final oracle = (jsonDecode(File('$out/oracle/search_oracle.json').readAsStringSync())['results'] as List).cast<Map<String, Object?>>();
    expect(queries.length, 500);
    for (var i = 0; i < queries.length; i++) {
      final r = index.search(queries[i].text);
      expect(r.outcome, oracle[i]['outcome'], reason: queries[i].id);
      expect(r.ids, (oracle[i]['ids'] as List).cast<String>(), reason: queries[i].id);
    }
  });

  test('G1-ROUTE-1.0 and G1-ROUTE-STEPS-1.0 agree with the oracle on all 30 cases', () {
    final cases = parseRouteCases(text('route_cases.json'));
    final oracle = (jsonDecode(File('$out/oracle/route_oracle.json').readAsStringSync())['results'] as List).cast<Map<String, Object?>>();
    expect(cases.length, 30);
    for (var i = 0; i < cases.length; i++) {
      final c = cases[i];
      final d = byId[c.destination]!;
      final r = graph.route(c.origin, d.node, stepFree: c.stepFree, blocked: c.blocked);
      expect(r.outcome, oracle[i]['outcome'], reason: c.id);
      if (r.outcome == 'PATH') {
        expect(r.nodes, (oracle[i]['nodes'] as List).cast<String>(), reason: c.id);
        expect(r.lengthMm, oracle[i]['length_mm'], reason: c.id);
        final (steps, summary) = routeSteps(graph, nodes, r.nodes, d);
        expect(jsonEncode([for (final s in steps) s.toJson()]), jsonEncode(oracle[i]['steps']), reason: c.id);
        expect(jsonEncode(summary.toJson()), jsonEncode(oracle[i]['summary']), reason: c.id);
      }
    }
  });

  test('parsers reject malformed input with FormatException only', () {
    for (final input in ['', '{', '[]', '{"nodes":{}}', '{"nodes":[],"edges":[{"id":1}]}', '{"nodes":[{"id":"N1"}],"edges":[]}',
      '{"nodes":[{"id":"N1","kind":"corridor","x_mm":0,"y_mm":0},{"id":"N1","kind":"corridor","x_mm":0,"y_mm":0}],"edges":[]}']) {
      expect(() => parseGraph(input), throwsFormatException, reason: input);
    }
    expect(() => parseDestinations('{"destinations":[{"id":"D1"}]}'), throwsFormatException);
  });

  test('G1-STYLE-1.0 transforms', () {
    final styleJson = text('style.json');
    final s = jsonDecode(buildStyle(styleJson, '/data/g1/v-1', 2, 'en')) as Map<String, Object?>;
    expect(s['glyphs'], 'file:///data/g1/v-1/glyphs/{fontstack}/{range}.pbf');
    expect((s['sources'] as Map)['synthetic']['data'], 'file:///data/g1/v-1/geometry.geojson');
    final layers = {for (final l in (s['layers'] as List).cast<Map<String, Object?>>()) l['id']: l};
    expect(jsonEncode(layers['rooms']!['filter']), '["all",["==",["get","kind"],"room"],["==",["get","floor"],2]]');
    expect(jsonEncode(layers['route']!['filter']), '["any",["!",["has","floor"]],["==",["get","floor"],2]]');
    expect(jsonEncode((layers['room-labels']!['layout'] as Map)['text-field']), '["get","name_en"]');
    expect(floorFilters(styleJson, 3).length, 7);
  });

  test('strings: same keys in both languages and every referenced key exists', () {
    final en = Strings.parse('en', File('assets/strings/en.json').readAsStringSync());
    final ar = Strings.parse('ar', File('assets/strings/ar.json').readAsStringSync());
    expect(en.keys.toSet(), ar.keys.toSet());
    expect(ar.rtl, isTrue);
    expect(en.rtl, isFalse);
    expect(File('assets/strings/en.json').readAsStringSync(), File('../contract/strings/en.json').readAsStringSync());
    expect(File('assets/strings/ar.json').readAsStringSync(), File('../contract/strings/ar.json').readAsStringSync());
    for (final s in [en, ar]) {
      expect(stepText(s, const RouteStep('walk', m: 12)), isNot(startsWith('[')));
      expect(trustText(s, null), isNot(startsWith('[')));
      for (final code in ['IDENTITY_VALID', 'REJECT_EXPIRED', 'REJECT_NO_BUNDLE', 'CAMERA_UNAVAILABLE', 'PERMISSION_DENIED', 'CANCELLED']) {
        expect(qrText(s, {'outcome': code, 'anchor': 'A01', 'building': 'SB1', 'floor': 1, 'kind': 'stairs'}), isNot(contains('[')));
      }
      for (var d = 1; d <= 7; d++) {
        expect(s.has('day.$d'), isTrue);
      }
    }
    final schedule = parseSchedule(text('schedule.json'));
    expect(scheduleItem(en, schedule.first), contains('Tuesday'));
  });

  test('lab hooks: registered commands, UI script and envelope decoder match the contract', () {
    final contract = jsonDecode(File('../contract/contract.json').readAsStringSync()) as Map<String, Object?>;
    expect(labCommands, ((contract['lab_hooks'] as Map)['commands'] as Map).keys.toSet());
    expect(jsonEncode(uiScript), jsonEncode((contract['ui_session_script'] as Map)['keyframes']));
    expect(decodeEnvelope('{"method":"nav.home","args":{}}'), 'ACCEPT');
    expect(decodeEnvelope('{"method":"shell","args":{}}'), 'REJECT_METHOD');
    expect(decodeEnvelope('{"method":"nav.home","args":[]}'), 'REJECT_ARGS');
    expect(decodeEnvelope('{"method":"nav.home","args":{},"x":1}'), 'REJECT_SHAPE');
    expect(decodeEnvelope('{'), 'REJECT_JSON');
    expect(decodeEnvelope('x' * 20000), 'REJECT_SIZE');
  });

  test('runtime CRC-32 equals the standard check value', () {
    expect(Crc32.of(Uint8List.fromList(utf8.encode('123456789'))), 0xCBF43926);
  });
}
