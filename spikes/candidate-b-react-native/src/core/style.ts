// Candidate B (React Native) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// G1-STYLE-1.0 for the declarative MapLibre React Native binding: the static part of the bundle style goes to mapStyle;
// the runtime floor and language layers (and the route source) are rendered as <Layer>/<GeoJSONSource> components
// whose filter/layout props follow the app state. The resulting map has the same layers, order and filters.
import type { BundleData } from './bundleData';
import type { RouteGraph } from './route';

type Json = unknown;
type Obj = Record<string, Json>;

/** Replaces ["==", ["get", "floor"], n] by the selected floor anywhere in a filter expression. */
export function withFloor(expr: Json, floor: number): Json {
  if (Array.isArray(expr)) {
    if (
      expr.length === 3 && expr[0] === '==' && Array.isArray(expr[1]) && expr[1].length === 2 && expr[1][0] === 'get' &&
      expr[1][1] === 'floor' && typeof expr[2] === 'number'
    ) {
      return ['==', ['get', 'floor'], floor];
    }
    return expr.map((e) => withFloor(e, floor));
  }
  return expr;
}

function replaceUrls(v: Json, baseUrl: string): Json {
  if (typeof v === 'string') return v.startsWith('g1bundle://') ? baseUrl + v.slice('g1bundle://'.length) : v;
  if (Array.isArray(v)) return v.map((e) => replaceUrls(e, baseUrl));
  if (v !== null && typeof v === 'object') {
    const out: Obj = {};
    for (const [k, e] of Object.entries(v as Obj)) out[k] = replaceUrls(e, baseUrl);
    return out;
  }
  return v;
}

export const textField = (lang: string): Json[] => ['get', lang === 'ar' ? 'name_ar' : 'name_en'];

export interface RuntimeLayer {
  /** definition as in style.json */
  def: Obj;
  /** the layer directly below it in style.json order (the binding inserts it above that layer) */
  afterId: string;
}

export interface SplitStyle {
  /** static style: sources (without "route") and the layers that never change */
  mapStyle: Obj;
  /** runtime floor/language layers in style order */
  runtimeLayers: RuntimeLayer[];
  languageLayers: Set<string>;
  center: [number, number];
  zoom: number;
}

export function splitStyle(styleJson: string, baseUrl: string): SplitStyle {
  const style = replaceUrls(JSON.parse(styleJson), baseUrl.endsWith('/') ? baseUrl : `${baseUrl}/`) as Obj;
  const meta = style.metadata as Obj;
  const runtime = new Set([...(meta.runtime_floor_layers as string[]), ...(meta.runtime_language_layers as string[])]);
  const layers = style.layers as Obj[];
  const sources = { ...(style.sources as Obj) };
  delete sources.route;
  const runtimeLayers: RuntimeLayer[] = [];
  layers.forEach((l, i) => {
    if (runtime.has(l.id as string)) {
      if (i === 0) throw new Error('style: a runtime layer cannot be the bottom layer');
      runtimeLayers.push({ def: l, afterId: layers[i - 1].id as string });
    }
  });
  return {
    mapStyle: { ...style, sources, layers: layers.filter((l) => !runtime.has(l.id as string)) },
    runtimeLayers,
    languageLayers: new Set(meta.runtime_language_layers as string[]),
    center: style.center as [number, number],
    zoom: style.zoom as number,
  };
}

/** Layer definition for the given floor and language (filters and label text field). */
export function layerFor(def: Obj, floor: number, lang: string, languageLayers: Set<string>): Obj {
  const out: Obj = { ...def };
  if ('filter' in def) out.filter = withFloor(def.filter, floor);
  if (languageLayers.has(def.id as string)) out.layout = { ...(def.layout as Obj), 'text-field': textField(lang) };
  return out;
}

/** FeatureCollection with copies of the path edge geometries (vertical edges have none). */
export function routeFeatures(data: BundleData, graph: RouteGraph, path: string[]): Obj {
  const features: Json[] = [];
  for (let i = 0; i + 1 < path.length; i++) {
    const e = graph.edge(path[i], path[i + 1]);
    const f = e ? data.edgeFeatures.get(e.edge) : undefined;
    if (f) features.push(f);
  }
  return { type: 'FeatureCollection', features };
}

export const emptyFeatures: Obj = { type: 'FeatureCollection', features: [] };
