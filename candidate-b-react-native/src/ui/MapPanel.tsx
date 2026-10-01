// Candidate B (React Native) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// The home map through the candidate's MapLibre binding (@maplibre/maplibre-react-native 11, declarative API),
// following G1-STYLE-1.0 and the map policy: the static style goes to mapStyle; the runtime floor/language layers and
// the route source are components whose filter/layout props follow the app state.
import React, { useEffect, useRef } from 'react';
import { StyleSheet, View } from 'react-native';
import {
  Camera,
  GeoJSONSource,
  Layer,
  Map,
  type CameraRef,
  type LayerProps,
  type MapRef,
  type StyleSpecification,
} from '@maplibre/maplibre-react-native';

import type { AppState } from '../state';
import { layerFor, textField, withFloor } from '../core/style';

/** Layers reported by map.inspect (G1-MAP-INSPECT-1.0). */
export const INSPECT_LAYERS = ['floors', 'rooms', 'pois', 'room-labels', 'route'];

/** The floor n of the first ["==", ["get", "floor"], n] test in a filter expression. */
export function floorOfFilter(expr: unknown): number | null {
  if (!Array.isArray(expr)) return null;
  if (expr.length === 3 && expr[0] === '==' && Array.isArray(expr[1]) && expr[1][0] === 'get' && expr[1][1] === 'floor' && typeof expr[2] === 'number') {
    return expr[2];
  }
  for (const e of expr) {
    const f = floorOfFilter(e);
    if (f !== null) return f;
  }
  return null;
}

export function MapPanel({ state }: { state: AppState }): React.JSX.Element {
  const s = state.s;
  const camera = useRef<CameraRef>(null);
  const map = useRef<MapRef>(null);

  useEffect(() => {
    state.camera = {
      easeTo: (lon, lat, zoom, durationMs) => camera.current?.easeTo({ center: [lon, lat], zoom, duration: durationMs }),
      inspect: async () => {
        const m = map.current;
        const st = state.style;
        if (!m || !st) return { available: false };
        const [center, zoom, bearing, pitch] = await Promise.all([m.getCenter(), m.getZoom(), m.getBearing(), m.getPitch()]);
        const out: Record<string, unknown> = {
          available: true,
          style_loaded: state.styleLoaded,
          camera: { lon: center[0], lat: center[1], zoom, bearing, pitch },
          // gesture policy as declared on the binding's map component (the binding has no getter)
          gestures: { pan: true, zoom: true, rotate: false, tilt: false },
          gestures_source: 'declared',
        };
        if (!state.styleLoaded) return out;
        // floor and label field as passed to the declarative layer components (the binding has no getter)
        const rooms = st.runtimeLayers.find((l) => l.def.id === 'rooms');
        out.floor = rooms ? floorOfFilter(withFloor(rooms.def.filter, state.floor)) : null;
        out.floor_source = 'declared';
        const labelField = (textField(state.lang) as string[])[1];
        out.label_field = labelField;
        out.label_field_source = 'declared';
        const rendered: Array<Record<string, unknown>> = [];
        for (const layer of INSPECT_LAYERS) {
          const seen = new Set<string>();
          for (const f of await m.queryRenderedFeatures({ layers: [layer] })) {
            const p = (f.properties ?? {}) as Record<string, unknown>;
            const id = p.id;
            if (typeof id !== 'string' || seen.has(id)) continue; // a feature split across tiles is reported once
            seen.add(id);
            rendered.push({
              layer,
              id,
              kind: p.kind ?? null,
              building: p.building ?? null,
              floor: typeof p.floor === 'number' ? p.floor : null,
              label: layer === 'room-labels' ? p[labelField] ?? null : null,
            });
          }
        }
        out.rendered = rendered;
        return out;
      },
    };
    return () => {
      state.camera = null;
    };
  }, [state]);

  const st = state.style;
  const layer = (def: Record<string, unknown>, afterId: string) => {
    const props = { ...layerFor(def, state.floor, state.lang, st!.languageLayers), afterId } as unknown as LayerProps;
    return <Layer key={def.id as string} {...props} />;
  };

  return (
    <View
      testID="home.map"
      accessible
      accessibilityLabel={s.t('home.map.label', { floor: state.floor })}
      style={styles.map}
    >
      {st && (
        <Map
          ref={map}
          key={state.styleGeneration}
          style={StyleSheet.absoluteFill}
          mapStyle={st.mapStyle as unknown as StyleSpecification}
          touchRotate={false}
          touchPitch={false}
          compass={false}
          onDidFinishLoadingStyle={() => state.onStyleLoaded()}
        >
          <Camera ref={camera} initialViewState={{ center: st.center, zoom: st.zoom }} />
          {st.runtimeLayers.map(({ def, afterId }) =>
            def.source === 'route' ? (
              <GeoJSONSource key="route-source" id="route" data={state.routeFc as unknown as GeoJSON.GeoJSON}>
                {layer(def, afterId)}
              </GeoJSONSource>
            ) : (
              layer(def, afterId)
            ),
          )}
        </Map>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  map: { flex: 3, minHeight: 160, backgroundColor: '#eef1f4' },
});
