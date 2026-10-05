// Candidate A (Flutter) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// G1-ROUTE-1.0 in Dart: Dijkstra on integer millimetres over graph.json; ties take the smallest predecessor id.
import 'dart:typed_data';

import 'bundle_data.dart';

class RouteResult {
  RouteResult(this.outcome, {this.nodes = const [], this.lengthMm = 0});

  /// PATH | REJECT_STEP_FREE_UNAVAILABLE | REJECT_BLOCKED | REJECT_UNREACHABLE | REJECT_UNKNOWN
  final String outcome;
  final List<String> nodes;
  final int lengthMm;
}

class RouteGraph {
  RouteGraph(GraphData g) {
    final ids = [for (final n in g.nodes) n.id]..sort();
    for (var i = 0; i < ids.length; i++) {
      _index[ids[i]] = i;
    }
    _ids = ids;
    final buckets = List<List<int>>.generate(ids.length, (_) => <int>[]);
    for (var k = 0; k < g.edges.length; k++) {
      buckets[_index[g.edges[k].from]!].add(k);
    }
    _edges = g.edges;
    _adj = buckets;
    for (final e in g.edges) {
      _byPair['${e.from}>${e.to}'] = e;
    }
  }

  final Map<String, int> _index = {};
  late final List<String> _ids;
  late final List<GraphEdge> _edges;
  late final List<List<int>> _adj;
  final Map<String, GraphEdge> _byPair = {};

  GraphEdge? edge(String from, String to) => _byPair['$from>$to'];

  bool hasNode(String id) => _index.containsKey(id);

  /// Shortest distances and smallest-id predecessors from origin.
  (Int64List, Int32List) _dijkstra(int origin, bool stepFree, Set<String> blocked) {
    final n = _ids.length;
    final dist = Int64List(n)..fillRange(0, n, -1);
    final prev = Int32List(n)..fillRange(0, n, -1);
    final done = Uint8List(n);
    final heap = _Heap();
    dist[origin] = 0;
    heap.push(0, origin);
    while (heap.isNotEmpty) {
      final d = heap.topDist;
      final u = heap.pop();
      if (done[u] == 1) continue;
      done[u] = 1;
      for (final k in _adj[u]) {
        final e = _edges[k];
        if (blocked.contains(e.edge) || (stepFree && !e.stepFree)) continue;
        final v = _index[e.to]!;
        final nd = d + e.lengthMm;
        final old = dist[v];
        if (old < 0 || nd < old) {
          dist[v] = nd;
          prev[v] = u;
          heap.push(nd, v);
        } else if (nd == old && u < prev[v]) {
          prev[v] = u;
        }
      }
    }
    return (dist, prev);
  }

  RouteResult route(String origin, String targetNode, {bool stepFree = false, List<String> blocked = const []}) {
    final o = _index[origin];
    final t = _index[targetNode];
    if (o == null || t == null) return RouteResult('REJECT_UNKNOWN');
    final blockedSet = blocked.toSet();
    final (dist, prev) = _dijkstra(o, stepFree, blockedSet);
    if (dist[t] >= 0) {
      final path = <String>[];
      for (var v = t; v != -1; v = v == o ? -1 : prev[v]) {
        path.add(_ids[v]);
      }
      return RouteResult('PATH', nodes: path.reversed.toList(), lengthMm: dist[t]);
    }
    if (stepFree && _dijkstra(o, false, blockedSet).$1[t] >= 0) return RouteResult('REJECT_STEP_FREE_UNAVAILABLE');
    if (blockedSet.isNotEmpty && _dijkstra(o, stepFree, const {}).$1[t] >= 0) return RouteResult('REJECT_BLOCKED');
    return RouteResult('REJECT_UNREACHABLE');
  }
}

/// Binary min-heap of (distance, node index); ties by node index.
class _Heap {
  final List<int> _d = [];
  final List<int> _v = [];

  bool get isNotEmpty => _d.isNotEmpty;

  int get topDist => _d[0];

  bool _less(int i, int j) => _d[i] < _d[j] || (_d[i] == _d[j] && _v[i] < _v[j]);

  void _swap(int i, int j) {
    final td = _d[i], tv = _v[i];
    _d[i] = _d[j];
    _v[i] = _v[j];
    _d[j] = td;
    _v[j] = tv;
  }

  void push(int d, int v) {
    _d.add(d);
    _v.add(v);
    var i = _d.length - 1;
    while (i > 0) {
      final p = (i - 1) >> 1;
      if (!_less(i, p)) break;
      _swap(i, p);
      i = p;
    }
  }

  int pop() {
    final top = _v[0];
    final lastD = _d.removeLast();
    final lastV = _v.removeLast();
    if (_d.isNotEmpty) {
      _d[0] = lastD;
      _v[0] = lastV;
      var i = 0;
      while (true) {
        final l = 2 * i + 1, r = l + 1;
        var m = i;
        if (l < _d.length && _less(l, m)) m = l;
        if (r < _d.length && _less(r, m)) m = r;
        if (m == i) break;
        _swap(i, m);
        i = m;
      }
    }
    return top;
  }
}
