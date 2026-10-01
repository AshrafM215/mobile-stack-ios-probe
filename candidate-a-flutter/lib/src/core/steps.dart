// Candidate A (Flutter) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// G1-ROUTE-STEPS-1.0 in Dart.
import 'bundle_data.dart';
import 'route.dart';

class RouteStep {
  const RouteStep(this.kind, {this.m, this.building, this.floor, this.code});

  /// walk | exit | enter | stairs | elevator | arrive
  final String kind;
  final int? m;
  final String? building;
  final int? floor;
  final String? code;

  Map<String, Object?> toJson() => {
        'kind': kind,
        if (m != null) 'm': m,
        if (building != null) 'building': building,
        if (floor != null) 'floor': floor,
        if (code != null) 'code': code,
      };
}

class RouteSummary {
  const RouteSummary(this.lengthM, this.steps, this.floors);

  final int lengthM;
  final int steps;
  final String floors;

  Map<String, Object?> toJson() => {'length_m': lengthM, 'steps': steps, 'floors': floors};
}

int metres(int mm) => (mm + 500) ~/ 1000;

(List<RouteStep>, RouteSummary) routeSteps(RouteGraph graph, Map<String, GraphNode> nodes, List<String> path, Destination dest) {
  final steps = <RouteStep>[];
  var walk = 0;
  var total = 0;
  void flush() {
    if (walk > 0) steps.add(RouteStep('walk', m: metres(walk)));
    walk = 0;
  }

  for (var i = 0; i + 1 < path.length; i++) {
    final u = nodes[path[i]]!;
    final v = nodes[path[i + 1]]!;
    final e = graph.edge(path[i], path[i + 1]) ?? (throw StateError('no edge ${path[i]} -> ${path[i + 1]}'));
    total += e.lengthMm;
    switch (e.kind) {
      case 'corridor':
      case 'spur':
      case 'outdoor':
        walk += e.lengthMm;
      case 'entrance':
        walk += e.lengthMm;
        flush();
        if (u.building != null && v.building == null) {
          steps.add(RouteStep('exit', building: u.building));
        } else {
          steps.add(RouteStep('enter', building: v.building));
        }
      case 'stairs':
      case 'elevator':
        flush();
        steps.add(RouteStep(e.kind, floor: v.floor));
      default:
        throw StateError('unknown edge kind ${e.kind}');
    }
  }
  flush();
  steps.add(RouteStep('arrive', code: dest.code));
  final floors = <int>[];
  for (final id in path) {
    final f = nodes[id]!.floor;
    if (f != null && !floors.contains(f)) floors.add(f);
  }
  return (steps, RouteSummary(metres(total), steps.length, floors.join('-')));
}
