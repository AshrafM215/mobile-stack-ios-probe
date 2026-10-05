// Candidate A (Flutter) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// G1-SEARCH-1.0 in Dart. Dart has no built-in Unicode normalization: NFKC comes from the pure-Dart package unorm_dart.
import 'package:unorm_dart/unorm_dart.dart' as unorm;

import 'bundle_data.dart';

final RegExp _remove = RegExp(r'[\u{0640}\u{064B}-\u{065F}\u{0670}\u{061C}\u{200B}-\u{200F}\u{202A}-\u{202E}\u{2060}-\u{2069}\u{FEFF}]',
    unicode: true);
final RegExp _separators = RegExp(
    r'[\u{0009}-\u{000D}\u{0020}\u{0085}\u{00A0}\u{1680}\u{2000}-\u{200A}\u{2028}\u{2029}\u{202F}\u{205F}\u{3000}\u{002D}\u{2010}-\u{2015}\u{2212}]+',
    unicode: true);
final RegExp _code = RegExp(r'^SB[0-9]+F[0-9]+R[0-9]+$');

String normalize(String s) {
  final nfkc = unorm.nfkc(s);
  final out = StringBuffer();
  for (final r in nfkc.runes) {
    if (r >= 0x0660 && r <= 0x0669) {
      out.writeCharCode(r - 0x0660 + 48);
    } else if (r >= 0x06F0 && r <= 0x06F9) {
      out.writeCharCode(r - 0x06F0 + 48);
    } else if (r >= 0x41 && r <= 0x5A) {
      out.writeCharCode(r + 32);
    } else {
      out.writeCharCode(r);
    }
  }
  return out.toString().replaceAll(_remove, '');
}

List<String> tokens(String s) => [for (final t in normalize(s).split(_separators)) if (t.isNotEmpty) t];

String codeKey(String s) {
  final out = StringBuffer();
  for (final r in tokens(s).join().runes) {
    out.writeCharCode(r >= 0x61 && r <= 0x7A ? r - 32 : r);
  }
  return out.toString();
}

class SearchResult {
  SearchResult(this.outcome, this.ids);

  final String outcome; // UNIQUE_MATCH | AMBIGUOUS | NO_MATCH
  final List<String> ids;
}

class _Entry {
  _Entry(this.id, this.codeKey, this.tokens);

  final String id;
  final String codeKey;
  final Set<String> tokens;
}

class SearchIndex {
  SearchIndex(List<Destination> destinations)
      : _entries = [
          for (final d in destinations)
            _Entry(d.id, codeKey(d.code), {
              ...tokens(d.nameEn),
              ...tokens(d.nameAr),
              d.building.toLowerCase(),
              'f${d.floor}',
              'r${d.roomNumber}',
              d.roomNumber,
              codeKey(d.code).toLowerCase(),
            }),
        ];

  final List<_Entry> _entries;

  SearchResult search(String query) {
    final t = tokens(query);
    if (t.isEmpty) return SearchResult('NO_MATCH', const []);
    final key = codeKey(query);
    final List<String> ids;
    if (_code.hasMatch(key)) {
      ids = [for (final e in _entries) if (e.codeKey == key) e.id];
    } else {
      ids = [for (final e in _entries) if (t.every(e.tokens.contains)) e.id];
    }
    ids.sort();
    if (ids.isEmpty) return SearchResult('NO_MATCH', const []);
    return SearchResult(ids.length == 1 ? 'UNIQUE_MATCH' : 'AMBIGUOUS', ids);
  }
}
