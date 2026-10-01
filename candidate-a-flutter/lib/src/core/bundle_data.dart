// Candidate A (Flutter) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// The verified bundle as the runtime sees it. Parsers are strict: any structural problem is a FormatException (fuzz
// target FUZ02 and bridge attack BRG02 rely on that), never a crash or a partially loaded state.
import 'dart:convert';
import 'dart:io';

class Destination {
  Destination(this.id, this.code, this.building, this.floor, this.node, this.roomNumber, this.nameEn, this.nameAr,
      this.reachable);

  final String id;
  final String code;
  final String building;
  final int floor;
  final String node;
  final String roomNumber;
  final String nameEn;
  final String nameAr;
  final bool reachable;

  String name(String lang) => lang == 'ar' ? nameAr : nameEn;
}

class GraphNode {
  GraphNode(this.id, this.kind, this.building, this.floor, this.xMm, this.yMm, this.entrance);

  final String id;
  final String kind;
  final String? building;
  final int? floor;
  final int xMm;
  final int yMm;
  final bool entrance;
}

class GraphEdge {
  GraphEdge(this.id, this.from, this.to, this.edge, this.kind, this.lengthMm, this.stepFree);

  final String id;
  final String from;
  final String to;
  final String edge;
  final String kind;
  final int lengthMm;
  final bool stepFree;
}

class GraphData {
  GraphData(this.nodes, this.edges);

  final List<GraphNode> nodes;
  final List<GraphEdge> edges;
}

class ScheduleEntry {
  ScheduleEntry(this.code, this.labelEn, this.labelAr, this.destination, this.start, this.end);

  final String code;
  final String labelEn;
  final String labelAr;
  final String destination;
  final String start;
  final String end;
}

class RouteCase {
  RouteCase(this.id, this.origin, this.destination, this.stepFree, this.blocked);

  final String id;
  final String origin;
  final String destination;
  final bool stepFree;
  final List<String> blocked;
}

class Query {
  Query(this.id, this.text);

  final String id;
  final String text;
}

const int maxJsonChars = 16 * 1024 * 1024;

Object? _decode(String json) {
  if (json.length > maxJsonChars) throw const FormatException('too large');
  return jsonDecode(json);
}

Map<String, Object?> _obj(Object? v, String what) {
  if (v is Map<String, Object?>) return v;
  throw FormatException('$what: object expected');
}

List<Object?> _list(Map<String, Object?> m, String k) {
  final v = m[k];
  if (v is List<Object?>) return v;
  throw FormatException('$k: array expected');
}

String _str(Map<String, Object?> m, String k) {
  final v = m[k];
  if (v is String) return v;
  throw FormatException('$k: string expected');
}

String? _optStr(Map<String, Object?> m, String k) {
  final v = m[k];
  if (v == null || v is String) return v as String?;
  throw FormatException('$k: string or null expected');
}

int _int(Map<String, Object?> m, String k) {
  final v = m[k];
  if (v is int) return v;
  throw FormatException('$k: integer expected');
}

int? _optInt(Map<String, Object?> m, String k) {
  final v = m[k];
  if (v == null || v is int) return v as int?;
  throw FormatException('$k: integer or null expected');
}

bool _bool(Map<String, Object?> m, String k, {bool? fallback}) {
  final v = m[k];
  if (v is bool) return v;
  if (v == null && fallback != null) return fallback;
  throw FormatException('$k: boolean expected');
}

/// graph.json (G1-ROUTE-1.0 input).
GraphData parseGraph(String json) {
  final root = _obj(_decode(json), 'graph');
  final nodes = <GraphNode>[];
  final ids = <String>{};
  for (final n in _list(root, 'nodes')) {
    final m = _obj(n, 'node');
    final node = GraphNode(_str(m, 'id'), _str(m, 'kind'), _optStr(m, 'building'), _optInt(m, 'floor'), _int(m, 'x_mm'),
        _int(m, 'y_mm'), _bool(m, 'entrance', fallback: false));
    if (!ids.add(node.id)) throw FormatException('duplicate node ${node.id}');
    nodes.add(node);
  }
  final edges = <GraphEdge>[];
  for (final e in _list(root, 'edges')) {
    final m = _obj(e, 'edge');
    final edge = GraphEdge(_str(m, 'id'), _str(m, 'from'), _str(m, 'to'), _str(m, 'edge'), _str(m, 'kind'),
        _int(m, 'length_mm'), _bool(m, 'step_free'));
    if (!ids.contains(edge.from) || !ids.contains(edge.to)) throw FormatException('edge ${edge.id}: unknown node');
    if (edge.lengthMm < 0) throw FormatException('edge ${edge.id}: negative length');
    edges.add(edge);
  }
  return GraphData(nodes, edges);
}

/// destinations.json
List<Destination> parseDestinations(String json) {
  final root = _obj(_decode(json), 'destinations');
  final out = <Destination>[];
  final ids = <String>{};
  for (final d in _list(root, 'destinations')) {
    final m = _obj(d, 'destination');
    final dest = Destination(_str(m, 'id'), _str(m, 'code'), _str(m, 'building'), _int(m, 'floor'), _str(m, 'node'),
        _str(m, 'room_number'), _str(m, 'name_en'), _str(m, 'name_ar'), _bool(m, 'reachable_from_entrances'));
    if (!ids.add(dest.id)) throw FormatException('duplicate destination ${dest.id}');
    out.add(dest);
  }
  return out;
}

List<ScheduleEntry> parseSchedule(String json) {
  final root = _obj(_decode(json), 'schedule');
  return [
    for (final e in _list(root, 'entries'))
      () {
        final m = _obj(e, 'entry');
        return ScheduleEntry(_str(m, 'code'), _str(m, 'label_en'), _str(m, 'label_ar'), _str(m, 'destination'),
            _str(m, 'start'), _str(m, 'end'));
      }(),
  ];
}

List<RouteCase> parseRouteCases(String json) {
  final root = _obj(_decode(json), 'route cases');
  return [
    for (final c in _list(root, 'cases'))
      () {
        final m = _obj(c, 'case');
        return RouteCase(_str(m, 'id'), _str(m, 'origin'), _str(m, 'destination'), _bool(m, 'step_free'),
            [for (final b in _list(m, 'blocked')) b is String ? b : throw const FormatException('blocked: string expected')]);
      }(),
  ];
}

List<Query> parseQueries(String json) {
  final root = _obj(_decode(json), 'query corpus');
  return [
    for (final q in _list(root, 'queries'))
      () {
        final m = _obj(q, 'query');
        return Query(_str(m, 'id'), _str(m, 'text'));
      }(),
  ];
}

/// geometry.geojson LineString features of the non-vertical edges, by undirected edge id (route display, G1-STYLE-1.0).
Map<String, Map<String, Object?>> parseEdgeFeatures(String json) {
  final root = _obj(_decode(json), 'geometry');
  final out = <String, Map<String, Object?>>{};
  for (final f in _list(root, 'features')) {
    final m = _obj(f, 'feature');
    final props = _obj(m['properties'], 'properties');
    final geom = _obj(m['geometry'], 'geometry');
    final id = props['id'];
    if (id is String && id.startsWith('E') && geom['type'] == 'LineString') out[id] = m;
  }
  return out;
}

/// Everything the app needs from the active verified bundle directory.
class BundleData {
  BundleData._(this.version, this.dir, this.destinations, this.graph, this.schedule, this.routeCases, this.queries,
      this.styleJson, this.edgeFeatures)
      : byId = {for (final d in destinations) d.id: d},
        entrances = ([for (final n in graph.nodes) if (n.entrance && n.building != null) n.id]..sort());

  final String version;
  final String dir;
  final List<Destination> destinations;
  final Map<String, Destination> byId;
  final GraphData graph;
  final List<ScheduleEntry> schedule;
  final List<RouteCase> routeCases;
  final List<Query> queries;
  final String styleJson;
  final Map<String, Map<String, Object?>> edgeFeatures;
  final List<String> entrances;

  List<ScheduleEntry> scheduleFor(String destinationId) =>
      [for (final e in schedule) if (e.destination == destinationId) e]..sort((a, b) => a.start.compareTo(b.start));

  static BundleData load(String version, String dir) {
    String read(String rel) => File('$dir/$rel').readAsStringSync();
    return BundleData._(
      version,
      dir,
      parseDestinations(read('destinations.json')),
      parseGraph(read('graph.json')),
      parseSchedule(read('schedule.json')),
      parseRouteCases(read('route_cases.json')),
      parseQueries(read('query_corpus.json')),
      read('style.json'),
      parseEdgeFeatures(read('geometry.geojson')),
    );
  }
}
