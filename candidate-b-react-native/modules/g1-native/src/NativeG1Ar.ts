// G1 synthetic native bridge - NON-PRODUCTION / SYNTHETIC DATA ONLY.
import type { TurboModule } from 'react-native';
import { TurboModuleRegistry } from 'react-native';

export interface Spec extends TurboModule {
  isSupported(): boolean;
}

export default TurboModuleRegistry.getEnforcing<Spec>('NativeG1Ar');
