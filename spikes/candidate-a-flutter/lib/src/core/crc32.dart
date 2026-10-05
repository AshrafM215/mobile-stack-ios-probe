// Candidate A (Flutter) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// CRC-32 (IEEE 802.3, reflected 0xEDB88320) written in Dart: the runtime side of the bridge workload (null control and
// reply checks).
import 'dart:typed_data';

class Crc32 {
  Crc32._();

  static final Uint32List _table = _build();

  static Uint32List _build() {
    final t = Uint32List(256);
    for (var i = 0; i < 256; i++) {
      var c = i;
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
      }
      t[i] = c;
    }
    return t;
  }

  static int of(Uint8List data, [int length = -1]) {
    final n = length < 0 ? data.length : length;
    var c = 0xFFFFFFFF;
    for (var i = 0; i < n; i++) {
      c = _table[(c ^ data[i]) & 0xFF] ^ (c >>> 8);
    }
    return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }
}
