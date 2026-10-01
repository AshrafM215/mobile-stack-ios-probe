// Candidate A (Flutter) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// G1-STYLE-1.0 in Dart: local bundle URLs, floor filters, label language and the route source.
import 'dart:convert';

import 'bundle_data.dart';
import 'route.dart';

/// Replaces `["==", ["get", "floor"], n]` by the selected floor anywhere in a filter expression.
Object? withFloor(Object? expr, int floor) {
  if (expr is List) {
    if (expr.length == 3 && expr[0] == '==' && expr[1] is List && (expr[1] as List).length == 2 &&
        (expr[1] as List)[0] == 'get' && (expr[1] as List)[1] == 'floor' && expr[2] is int) {
      return ['==', ['get', 'floor'], floor];
    }
    return [for (final e in expr) withFloor(e, floor)];
  }
  return expr;
}

Object? _replaceUrls(Object? v, String baseUrl) {
  if (v is String) return v.startsWith('g1bundle://') ? baseUrl + v.substring('g1bundle://'.length) : v;
  if (v is List) return [for (final e in v) _replaceUrls(e, baseUrl)];
  if (v is Map) return {for (final e in v.entries) e.key as String: _replaceUrls(e.value, baseUrl)};
  return v;
}

List<Object?> textField(String lang) => ['get', lang == 'ar' ? 'name_ar' : 'name_en'];

/// The style for the bundle directory, floor and language (initial load).
String buildStyle(String styleJson, String bundleDir, int floor, String lang) {
  final base = Uri.directory(bundleDir, windows: false).toString();
  final style = _replaceUrls(jsonDecode(styleJson), base.endsWith('/') ? base : '$base/') as Map<String, Object?>;
  final meta = style['metadata'] as Map<String, Object?>;
  final floorLayers = (meta['runtime_floor_layers'] as List).cast<String>().toSet();
  final langLayers = (meta['runtime_language_layers'] as List).cast<String>().toSet();
  for (final l in (style['layers'] as List).cast<Map<String, Object?>>()) {
    if (floorLayers.contains(l['id']) && l.containsKey('filter')) l['filter'] = withFloor(l['filter'], floor);
    if (langLayers.contains(l['id'])) (l['layout'] as Map<String, Object?>)['text-field'] = textField(lang);
  }
  return jsonEncode(style);
}

/// Floor filter per runtime floor layer of the original style (for setFilter on floor changes).
Map<String, Object?> floorFilters(String styleJson, int floor) {
  final style = jsonDecode(styleJson) as Map<String, Object?>;
  final floorLayers = ((style['metadata'] as Map)['runtime_floor_layers'] as List).cast<String>().toSet();
  return {
    for (final l in (style['layers'] as List).cast<Map<String, Object?>>())
      if (floorLayers.contains(l['id']) && l.containsKey('filter')) l['id'] as String: withFloor(l['filter'], floor),
  };
}

/// FeatureCollection with copies of the path edge geometries (vertical edges have none).
Map<String, Object?> routeFeatures(BundleData data, RouteGraph graph, List<String> path) {
  final features = <Object?>[];
  for (var i = 0; i + 1 < path.length; i++) {
    final e = graph.edge(path[i], path[i + 1]);
    final f = e == null ? null : data.edgeFeatures[e.edge];
    if (f != null) features.add(f);
  }
  return {'type': 'FeatureCollection', 'features': features};
}

const Map<String, Object?> emptyFeatures = {'type': 'FeatureCollection', 'features': <Object?>[]};

/// Empty style shown when no verified bundle is installed (bundle.remove): nothing of a removed bundle stays on screen.
String emptyStyle(List<num> center, num zoom) => jsonEncode({
      'version': 8,
      'center': center,
      'zoom': zoom,
      'sources': <String, Object?>{},
      'layers': [
        {'id': 'background', 'type': 'background', 'paint': {'background-color': '#EEF1F4'}},
      ],
    });

/// Layers reported by map.inspect (G1-MAP-INSPECT-1.0).
const List<String> inspectLayers = ['floors', 'rooms', 'pois', 'room-labels', 'route'];

/// The floor n of the first `["==", ["get", "floor"], n]` test in a filter expression as returned by the binding.
int? floorOfFilter(Object? expr) {
  if (expr is List) {
    if (expr.length == 3 && expr[0] == '==' && expr[1] is List && (expr[1] as List).length == 2 &&
        (expr[1] as List)[0] == 'get' && (expr[1] as List)[1] == 'floor' && expr[2] is num) {
      return (expr[2] as num).toInt();
    }
    for (final e in expr) {
      final f = floorOfFilter(e);
      if (f != null) return f;
    }
  }
  return null;
}
