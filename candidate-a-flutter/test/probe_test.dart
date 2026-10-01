// G1 candidate A (Flutter) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
import 'package:flutter_test/flutter_test.dart';
import 'package:g1_candidate_a/main.dart';

void main() {
  test('AR capability text keeps the safe fallback for unsupported devices', () {
    expect(describeAr(false), startsWith('unsupported'));
    expect(describeAr(true), 'supported');
  });
}
