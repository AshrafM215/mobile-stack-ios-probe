// G1 candidate B (React Native) adapter API - NON-PRODUCTION / SYNTHETIC DATA ONLY.
import NativeG1 from './NativeG1';

export type { ArEvent, LabCommandEvent, N2RMessage } from './NativeG1';
export { NativeG1 };

/** Monotonic nanoseconds of the common module clock, read synchronously through JSI. */
export const nowNanos = (): number => NativeG1.nowNanos();

export const mark = (name: string, kv: string[] = [], rt: number = NativeG1.nowNanos()): void => NativeG1.mark(name, rt, kv);

export async function ensureBundle(): Promise<Record<string, unknown>> {
  return JSON.parse(await NativeG1.ensureBundle());
}

export async function bundleInfo(): Promise<Record<string, unknown>> {
  return JSON.parse(await NativeG1.bundleInfo());
}

export async function validateQr(payload: string | null): Promise<Record<string, unknown>> {
  return JSON.parse(await NativeG1.validateQr(payload));
}

export async function scanQr(requestId: string): Promise<{ payload: string | null; error: string | null }> {
  return JSON.parse(await NativeG1.scanQr(requestId));
}

export async function launchCommand(): Promise<{ name: string; args: string } | null> {
  const s = await NativeG1.launchCommand();
  return s === null ? null : JSON.parse(s);
}
