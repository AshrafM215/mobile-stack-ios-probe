// G1 synthetic data generator - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// Reference implementation of the route step contract G1-ROUTE-STEPS-1.0 (every candidate implements the same contract).
//
// Input: the published graph.json (directed edges), the published destinations.json and a PATH node sequence.
// Walk along the path edges accumulating length for corridor, spur, outdoor and entrance edges. An entrance edge first
// adds its length, flushes the walk, then emits exit (indoor -> outdoor, building of the indoor node) or enter
// (outdoor -> indoor, building of the indoor node). A stairs or elevator edge flushes the walk and emits stairs/elevator
// with the floor of the next node. At the end the walk is flushed and arrive is emitted with the destination code.
// Flushing emits a walk step only when the accumulated length is above 0 mm. Whole metres: floor((mm + 500) / 1000).
// Summary: length_m = whole metres of the route length, steps = number of steps (arrive included), floors = the floors
// of the path nodes in first-visit order without repeats (nodes without a floor skipped), joined by "-".

export const STEPS_CONTRACT = 'G1-ROUTE-STEPS-1.0';

export const metres = (mm) => Math.floor((mm + 500) / 1000);

export function stepIndex(graph) {
  const nodes = new Map(graph.nodes.map((n) => [n.id, n]));
  const edges = new Map(graph.edges.map((e) => [`${e.from}>${e.to}`, e]));
  return { nodes, edges };
}

export function routeSteps(index, path, destination) {
  const steps = [];
  let walk = 0;
  let total = 0;
  const flush = () => {
    if (walk > 0) steps.push({ kind: 'walk', m: metres(walk) });
    walk = 0;
  };
  for (let i = 0; i + 1 < path.length; i++) {
    const u = index.nodes.get(path[i]);
    const v = index.nodes.get(path[i + 1]);
    const e = index.edges.get(`${path[i]}>${path[i + 1]}`);
    if (!u || !v || !e) throw new Error(`no edge ${path[i]} -> ${path[i + 1]}`);
    total += e.length_mm;
    switch (e.kind) {
      case 'corridor':
      case 'spur':
      case 'outdoor':
        walk += e.length_mm;
        break;
      case 'entrance':
        walk += e.length_mm;
        flush();
        if (u.building && !v.building) steps.push({ kind: 'exit', building: u.building });
        else steps.push({ kind: 'enter', building: v.building });
        break;
      case 'stairs':
      case 'elevator':
        flush();
        steps.push({ kind: e.kind, floor: v.floor });
        break;
      default:
        throw new Error(`unknown edge kind ${e.kind}`);
    }
  }
  flush();
  steps.push({ kind: 'arrive', code: destination.code });
  const floors = [];
  for (const id of path) {
    const f = index.nodes.get(id).floor;
    if (f !== undefined && f !== null && !floors.includes(f)) floors.push(f);
  }
  return { steps, summary: { length_m: metres(total), steps: steps.length, floors: floors.join('-') } };
}
