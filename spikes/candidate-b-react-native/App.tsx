// G1 candidate B (React Native) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// Synthetic wayfinding benchmark app (G1-CIC-1.0). Not a product; synthetic data only; not for navigation.
import React, { useEffect, useLayoutEffect, useSyncExternalStore } from 'react';
import { AppState as PlatformAppState, BackHandler, StatusBar } from 'react-native';
import { SafeAreaProvider } from 'react-native-safe-area-context';

import { Strings } from './src/core/strings';
import { LabController } from './src/lab';
import { AppState } from './src/state';
import { Root } from './src/ui/screens';
import ar from './src/strings/ar.json';
import en from './src/strings/en.json';

const state = new AppState({ ar: new Strings('ar', ar as Record<string, string>), en: new Strings('en', en as Record<string, string>) });

let started = false;
function start(): void {
  if (started) return;
  started = true;
  void state.boot().then(() => new LabController(state).start());
}

function App(): React.JSX.Element {
  useSyncExternalStore(state.subscribe, state.getSnapshot);

  // every commit of the tree: resolves the frame waiters of the bench loops (requestAnimationFrame after commit)
  useLayoutEffect(() => state.onCommit());

  useEffect(() => {
    start();
    let previous = PlatformAppState.currentState;
    const lifecycle = PlatformAppState.addEventListener('change', (next) => {
      if (next === 'active' && previous !== 'active') state.onResumed();
      previous = next;
    });
    const back = BackHandler.addEventListener('hardwareBackPress', () => {
      if (state.stack.length > 1) {
        state.back();
        return true;
      }
      return false;
    });
    return () => {
      lifecycle.remove();
      back.remove();
    };
  }, []);

  return (
    <SafeAreaProvider>
      <StatusBar barStyle="dark-content" />
      <Root state={state} />
    </SafeAreaProvider>
  );
}

export default App;
