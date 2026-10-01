// G1 candidate B (React Native) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
import { describeAr } from '../src/probe';

test('AR capability text keeps the safe fallback for unsupported devices', () => {
  expect(describeAr(false)).toMatch(/^unsupported/);
  expect(describeAr(true)).toBe('supported');
});
