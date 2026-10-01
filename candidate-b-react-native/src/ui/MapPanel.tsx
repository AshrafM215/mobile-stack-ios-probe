// Candidate B (React Native) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// The home map through the candidate's MapLibre binding (@maplibre/maplibre-react-native 11, declarative API),
// following G1-STYLE-1.0 and the map policy: the static style goes to mapStyle; the runtime floor/language layers and
// the route source are components whose filter/layout props follow the app state.
import React, { useEffect, useRef } from 'react';
import { StyleSheet, View } from 'react-native';
import { Camera, GeoJSONSource, Layer, Map, type CameraRef, type LayerProps, type StyleSpecification } from '@maplibre/maplibre-react-native';

import type { AppState } from '../state';
import { layerFor } from '../core/style';

export function MapPanel({ state }: { state: AppState }): React.JSX.Element {
  const s = state.s;
  const camera = useRef<CameraRef>(null);

  useEffect(() => {
    state.camera = {
      easeTo: (lon, lat, zoom, durationMs) => camera.current?.easeTo({ center: [lon, lat], zoom, duration: durationMs }),
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
