// G1 candidate B (React Native) TurboModule spec - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// Runtime boundary of candidate B: TurboModule NativeG1 over JSI. Synchronous where the method is declared with a plain
// return type (nowNanos, echoSyncBase64), Promise-based otherwise; binary payloads cross as base64 strings because this
// boundary has no binary type. Events use the codegen event emitters.
import type { CodegenTypes, TurboModule } from 'react-native';
import { TurboModuleRegistry } from 'react-native';

export type ArEvent = { requestId: string; event: string };
export type LabCommandEvent = { name: string; args: string };
export type N2RMessage = { seq: number; sent: number; payload: string; done: boolean; count: number };

export interface Spec extends TurboModule {
  // synchronous (JSI)
  nowNanos(): number;
  echoSyncBase64(payload: string): Array<number>;

  // asynchronous
  mark(name: string, rt: number, kv: Array<string>): void;
  reportReady(rt: number): void;
  reportResumeReady(rt: number): void;
  ensureBundle(): Promise<string>;
  bundleInfo(): Promise<string>;
  bundleDirectoryUrl(): Promise<string | null>;
  readBundleFile(path: string): Promise<string>;
  importBundleFile(name: string): Promise<string>;
  importBundleBase64(zip: string, source: string): Promise<string>;
  rollback(): Promise<string>;
  validateQr(payload: string | null): Promise<string>;
  decodeQrImport(name: string): Promise<string | null>;
  scanQr(requestId: string): Promise<string>;
  arAvailability(): Promise<string>;
  startAr(requestId: string, script: string | null, texts: string): void;
  setArGuidance(requestId: string, allowed: boolean): void;
  closeAr(requestId: string): void;
  payloadBlockBase64(): Promise<string>;
  echoAsyncBase64(payload: string): Promise<Array<number>>;
  startN2R(size: number, count: number, rateHz: number): void;
  sessionStart(marker: string): Promise<boolean>;
  sessionActive(): Promise<boolean>;
  sessionEnd(): Promise<void>;
  crash(caseId: string): void;
  writeOut(name: string, text: string): Promise<string>;
  readImportText(name: string): Promise<string>;
  readImportBase64(name: string): Promise<string>;
  launchCommand(): Promise<string | null>;

  readonly onArEvent: CodegenTypes.EventEmitter<ArEvent>;
  readonly onCommand: CodegenTypes.EventEmitter<LabCommandEvent>;
  readonly onN2R: CodegenTypes.EventEmitter<N2RMessage>;
}

export default TurboModuleRegistry.getEnforcing<Spec>('NativeG1');
