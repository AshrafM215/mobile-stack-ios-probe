// Candidate B (React Native) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// G1-ROUTE-STEPS-1.0 in TypeScript.
import type { Destination, GraphNode } from './bundleData';
import type { RouteGraph } from './route';

export type RouteStep =
  | { kind: 'walk'; m: number }
  | { kind: 'exit' | 'enter'; building: string }
  | { kind: 'stairs' | 'elevator'; floor: number }
  | { kind: 'arrive'; code: string };

export interface RouteSummary {
  length_m: number;
  steps: number;
  floors: string;
}

export const metres = (mm: number): number => Math.floor((mm + 500) / 1000);

export function routeSteps(graph: RouteGraph, nodes: Map<string, GraphNode>, path: string[], dest: Destination): { steps: RouteStep[]; summary: RouteSummary } {
  const steps: RouteStep[] = [];
  let walk = 0;
  let total = 0;
  const flush = () => {
    if (walk > 0) steps.push({ kind: 'walk', m: metres(walk) });
    walk = 0;
  };
  for (let i = 0; i + 1 < path.length; i++) {
    const u = nodes.get(path[i])!;
    const v = nodes.get(path[i + 1])!;
    const e = graph.edge(path[i], path[i + 1]);
    if (!e) throw new Error(`no edge ${path[i]} -> ${path[i + 1]}`);
    total += e.lengthMm;
    switch (e.kind) {
      case 'corridor':
      case 'spur':
      case 'outdoor':
        walk += e.lengthMm;
        break;
      case 'entrance':
        walk += e.lengthMm;
        flush();
        if (u.building !== null && v.building === null) steps.push({ kind: 'exit', building: u.building });
        else steps.push({ kind: 'enter', building: v.building! });
        break;
      case 'stairs':
      case 'elevator':
        flush();
        steps.push({ kind: e.kind, floor: v.floor! });
        break;
      default:
        throw new Error(`unknown edge kind ${e.kind}`);
    }
  }
  flush();
  steps.push({ kind: 'arrive', code: dest.code });
  const floors: number[] = [];
  for (const id of path) {
    const f = nodes.get(id)!.floor;
    if (f !== null && !floors.includes(f)) floors.push(f);
  }
  return { steps, summary: { length_m: metres(total), steps: steps.length, floors: floors.join('-') } };
}
