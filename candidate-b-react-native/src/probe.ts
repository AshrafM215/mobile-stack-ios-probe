// G1 candidate B (React Native) - NON-PRODUCTION / SYNTHETIC DATA ONLY.

/** Text shown for the AR capability result; unsupported devices keep the safe 2D/text fallback. */
export function describeAr(supported: boolean): string {
  return supported ? 'supported' : 'unsupported (safe 2D/text fallback)';
}

/** Synthetic log marker for feasibility evidence; no personal or device data. */
export function mark(event: string, detail = ''): void {
  console.log(`G1_PROBE app=candidate-b-react-native event=${event} ${detail}`);
}
