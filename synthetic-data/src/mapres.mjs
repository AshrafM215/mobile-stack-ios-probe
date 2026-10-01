// G1 synthetic data generator - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// Map resources: geometry.geojson (RFC 7946), one local MapLibre style, generated sprites and composite SDF glyphs.
import { roundHalfEven7, LABEL } from './canonical.mjs';
import { encodePng } from './binary.mjs';

export const STYLE_CONTRACT = 'G1-STYLE-1.0';
export const FONTSTACK = 'G1Sans';
export const GLYPH_RANGES = [[0, 255], [1536, 1791], [8192, 8447], [64256, 64511], [64512, 64767], [64768, 65023], [65024, 65279]];
export const lon = (xmm) => Number(roundHalfEven7(xmm * 100, 11131949079));
export const lat = (ymm) => Number(roundHalfEven7(ymm * 10, 1105742727));
const pt = (x, y) => [lon(x), lat(y)];
const ring = (x0, y0, x1, y1) => [pt(x0, y0), pt(x1, y0), pt(x1, y1), pt(x0, y1), pt(x0, y0)]; // counter-clockwise

function bbox(list) {
  let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
  for (const n of list) {
    x0 = Math.min(x0, n.x_mm); y0 = Math.min(y0, n.y_mm); x1 = Math.max(x1, n.x_mm); y1 = Math.max(y1, n.y_mm);
  }
  return [x0, y0, x1, y1];
}

export function buildGeoJson(nodes, edges, dests, anchorList, bundleVersion) {
  const byId = new Map(nodes.map((n) => [n.id, n]));
  const features = [];
  for (const b of [1, 2, 3]) {
    const [x0, y0, x1, y1] = bbox(nodes.filter((n) => n.building === b));
    features.push({ type: 'Feature', properties: { id: `SB${b}`, kind: 'building', building: `SB${b}` },
      geometry: { type: 'Polygon', coordinates: [ring(x0 - 5000, y0 - 5000, x1 + 5000, y1 + 5000)] } });
  }
  for (const b of [1, 2, 3]) {
    for (const f of [1, 2, 3]) {
      const [x0, y0, x1, y1] = bbox(nodes.filter((n) => n.building === b && n.floor === f));
      features.push({ type: 'Feature', properties: { id: `SB${b}F${f}`, kind: 'floor', building: `SB${b}`, floor: f },
        geometry: { type: 'Polygon', coordinates: [ring(x0 - 5000, y0 - 5000, x1 + 5000, y1 + 5000)] } });
    }
  }
  for (const d of dests) {
    const n = byId.get(d.node);
    features.push({ type: 'Feature', properties: { id: d.id, kind: 'room', building: `SB${d.building}`, floor: d.floor, code: d.code, name_ar: d.name_ar, name_en: d.name_en },
      geometry: { type: 'Polygon', coordinates: [ring(n.x_mm - 2000, n.y_mm - 2000, n.x_mm + 2000, n.y_mm + 2000)] } });
  }
  for (const e of edges) {
    if (e.kind === 'stairs' || e.kind === 'elevator') continue;
    const a = byId.get(e.a);
    const c = byId.get(e.b);
    const props = { id: e.id, kind: e.kind };
    const indoor = a.building ? a : c.building ? c : null;
    if (indoor) { props.building = `SB${indoor.building}`; props.floor = indoor.floor; }
    features.push({ type: 'Feature', properties: props, geometry: { type: 'LineString', coordinates: [pt(a.x_mm, a.y_mm), pt(c.x_mm, c.y_mm)] } });
  }
  for (const b of [1, 2, 3]) {
    for (const f of [1, 2, 3]) {
      for (const [col, kind] of [[6, 'stairs'], [18, 'elevator']]) {
        const n = nodes.find((x) => x.kind === 'corridor' && !x.wing && x.building === b && x.floor === f && x.c === col && x.r === 0);
        features.push({ type: 'Feature', properties: { id: `${kind.toUpperCase()}-SB${b}F${f}`, kind, building: `SB${b}`, floor: f, node: n.id },
          geometry: { type: 'Point', coordinates: pt(n.x_mm, n.y_mm) } });
      }
    }
  }
  for (const a of anchorList) {
    const n = byId.get(a.node);
    features.push({ type: 'Feature', properties: { id: a.id, kind: 'qr_anchor', building: a.building, floor: a.floor, node: a.node },
      geometry: { type: 'Point', coordinates: pt(n.x_mm, n.y_mm) } });
  }
  return { type: 'FeatureCollection', label: LABEL, bundle_version: bundleVersion, frame: 'G1-SYNTH-LOCAL', features };
}

const floorFilter = (extra) => ['all', extra, ['==', ['get', 'floor'], 1]];

/** One local style; "g1bundle://" is replaced by each app with the file URL of the active verified bundle directory. */
export function buildStyle(bundleVersion) {
  return {
    version: 8,
    name: 'G1 synthetic style 1.0 - NON-PRODUCTION / SYNTHETIC DATA ONLY',
    metadata: { label: LABEL, style_contract: STYLE_CONTRACT, bundle_version: bundleVersion, runtime_floor_layers: ['floors', 'rooms', 'room-outlines', 'corridors', 'route', 'pois', 'room-labels'], runtime_language_layers: ['room-labels'] },
    center: [lon(272000), lat(30000)],
    zoom: 16.5,
    glyphs: `g1bundle://glyphs/{fontstack}/{range}.pbf`,
    sprite: 'g1bundle://sprites/sprite',
    sources: {
      synthetic: { type: 'geojson', data: 'g1bundle://geometry.geojson' },
      route: { type: 'geojson', data: { type: 'FeatureCollection', features: [] } },
    },
    layers: [
      { id: 'background', type: 'background', paint: { 'background-color': '#f4f1ea' } },
      { id: 'buildings', type: 'fill', source: 'synthetic', filter: ['==', ['get', 'kind'], 'building'], paint: { 'fill-color': '#e9e4d8', 'fill-outline-color': '#5c5345' } },
      { id: 'outdoor', type: 'line', source: 'synthetic', filter: ['==', ['get', 'kind'], 'outdoor'], paint: { 'line-color': '#6b6b6b', 'line-width': 2, 'line-dasharray': [2, 2] } },
      { id: 'floors', type: 'fill', source: 'synthetic', filter: floorFilter(['==', ['get', 'kind'], 'floor']), paint: { 'fill-color': '#d9d2c3', 'fill-outline-color': '#5c5345' } },
      { id: 'rooms', type: 'fill', source: 'synthetic', filter: floorFilter(['==', ['get', 'kind'], 'room']), paint: { 'fill-color': '#bcd6ee' } },
      { id: 'room-outlines', type: 'line', source: 'synthetic', filter: floorFilter(['==', ['get', 'kind'], 'room']), paint: { 'line-color': '#1f4e79', 'line-width': 1.5 } },
      { id: 'corridors', type: 'line', source: 'synthetic', filter: floorFilter(['in', ['get', 'kind'], ['literal', ['corridor', 'spur', 'entrance']]]), paint: { 'line-color': '#4a4a4a', 'line-width': 3 } },
      { id: 'route', type: 'line', source: 'route', filter: ['any', ['!', ['has', 'floor']], ['==', ['get', 'floor'], 1]], layout: { 'line-join': 'round', 'line-cap': 'round' }, paint: { 'line-color': '#b3261e', 'line-width': 5 } },
      { id: 'pois', type: 'symbol', source: 'synthetic', filter: floorFilter(['in', ['get', 'kind'], ['literal', ['stairs', 'elevator', 'qr_anchor']]]), layout: { 'icon-image': ['get', 'kind'], 'icon-allow-overlap': true, 'icon-offset': ['match', ['get', 'kind'], 'qr_anchor', ['literal', [0, -14]], ['literal', [0, 0]]] } },
      { id: 'room-labels', type: 'symbol', source: 'synthetic', minzoom: 18, filter: floorFilter(['==', ['get', 'kind'], 'room']), layout: { 'text-field': ['get', 'name_ar'], 'text-font': [FONTSTACK], 'text-size': 12, 'text-max-width': 8 }, paint: { 'text-color': '#1b1b1b', 'text-halo-color': '#ffffff', 'text-halo-width': 1.5 } },
    ],
  };
}

/** Generated geometric icons (project-owned synthetic): stairs, elevator, qr_anchor; 1x (24 px) and 2x (48 px). */
export function buildSprites() {
  const icons = ['elevator', 'qr_anchor', 'stairs'];
  const out = {};
  for (const ratio of [1, 2]) {
    const s = 24 * ratio;
    const w = s * icons.length;
    const px = Buffer.alloc(w * s * 4, 0);
    const set = (x, y, rgba) => { const i = (y * w + x) * 4; px[i] = rgba[0]; px[i + 1] = rgba[1]; px[i + 2] = rgba[2]; px[i + 3] = rgba[3]; };
    const dark = [32, 32, 32, 255];
    const white = [255, 255, 255, 255];
    const json = {};
    icons.forEach((name, k) => {
      const ox = k * s;
      for (let y = 0; y < s; y += 1) {
        for (let x = 0; x < s; x += 1) {
          const u = Math.floor((x * 24) / s);
          const v = Math.floor((y * 24) / s);
          let c = dark;
          if (u === 0 || v === 0 || u === 23 || v === 23) c = white;
          else if (name === 'stairs') { const step = Math.floor((u - 3) / 6); if (u >= 3 && u <= 20 && v >= 20 - 6 * (step + 1) && v <= 20 && step >= 0 && step <= 2) c = white; }
          else if (name === 'elevator') { const up = v >= 4 && v <= 10 && Math.abs(u - 12) <= v - 4; const down = v >= 13 && v <= 19 && Math.abs(u - 12) <= 19 - v; if (up || down) c = white; }
          else if (name === 'qr_anchor') { const inBox = (a, b, n) => u >= a && u < a + n && v >= b && v < b + n; if ((inBox(3, 3, 7) && !inBox(4, 4, 5)) || inBox(5, 5, 3) || (inBox(14, 3, 7) && !inBox(15, 4, 5)) || inBox(16, 5, 3) || (inBox(3, 14, 7) && !inBox(4, 15, 5)) || inBox(5, 16, 3) || ((u + v) % 3 === 0 && u >= 13 && v >= 13 && u <= 20 && v <= 20)) c = white; }
          set(ox + x, y, c);
        }
      }
      json[name] = { x: ox, y: 0, width: s, height: s, pixelRatio: ratio };
    });
    const suffix = ratio === 1 ? '' : '@2x';
    out[`sprites/sprite${suffix}.png`] = encodePng(w, s, px, { colorType: 6, text: { Comment: LABEL } });
    out[`sprites/sprite${suffix}.json`] = Buffer.from(JSON.stringify(json, null, 2) + '\n', 'utf8');
  }
  return out;
}

/** Composite SDF glyph ranges for the single fontstack G1Sans (Noto Sans first, then Noto Sans Arabic). */
export async function buildGlyphs(fontnik, fonts) {
  const rangeOf = (font, start, end) => new Promise((resolve, reject) => fontnik.range({ font, start, end }, (e, r) => (e ? reject(e) : resolve(r))));
  const composite = (bufs) => new Promise((resolve, reject) => fontnik.composite(bufs, (e, r) => (e ? reject(e) : resolve(r))));
  const out = {};
  for (const [start, end] of GLYPH_RANGES) {
    const parts = [];
    for (const font of fonts) parts.push(await rangeOf(font, start, end));
    out[`glyphs/${FONTSTACK}/${start}-${end}.pbf`] = Buffer.from(await composite(parts));
  }
  return out;
}
