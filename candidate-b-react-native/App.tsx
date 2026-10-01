// G1 candidate B (React Native) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
import React, { useState } from 'react';
import { Button, StyleSheet, Text, View } from 'react-native';
import { Camera, Map } from '@maplibre/maplibre-react-native';
import { SafeAreaProvider, SafeAreaView } from 'react-native-safe-area-context';
import { isArSupported } from 'g1-native';
import { describeAr, mark } from './src/probe';
import syntheticStyle from './probe-style-v0.json';

function App(): React.JSX.Element {
  const [mapStatus, setMapStatus] = useState('loading');
  const [arStatus, setArStatus] = useState('not checked');

  const checkAr = () => {
    const supported = isArSupported();
    mark('ar_check', `supported=${supported}`);
    setArStatus(describeAr(supported));
  };

  return (
    <SafeAreaProvider>
      <SafeAreaView style={styles.container}>
        <Text testID="title" style={styles.title}>
          G1 Candidate B - synthetic probe
        </Text>
        <View style={styles.map} accessible accessibilityLabel="Synthetic map">
          <Map
            style={styles.fill}
            mapStyle={syntheticStyle as object}
            onDidFinishLoadingStyle={() => {
              mark('style_loaded');
              setMapStatus('style loaded');
            }}
          >
            <Camera initialViewState={{ center: [0.0007, 0.0003], zoom: 16 }} />
          </Map>
        </View>
        <Text testID="mapStatus">Map: {mapStatus}</Text>
        <Button testID="checkAR" title="Check AR" onPress={checkAr} />
        <Text testID="arStatus">AR: {arStatus}</Text>
      </SafeAreaView>
    </SafeAreaProvider>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, padding: 16 },
  title: { fontSize: 17, fontWeight: '600', marginBottom: 12 },
  map: { height: 320, marginBottom: 12 },
  fill: { flex: 1 },
});

export default App;
