// Candidate A (Flutter) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// In-app bilingual strings (contract/strings/en.json and ar.json, compiled in as assets).
import 'dart:convert';

class Strings {
  Strings(this.lang, this._map);

  final String lang;
  final Map<String, String> _map;

  bool get rtl => _map['_meta.direction'] == 'rtl';

  static Strings parse(String lang, String json) {
    final raw = jsonDecode(json) as Map<String, Object?>;
    return Strings(lang, raw.map((k, v) => MapEntry(k, v as String)));
  }

  /// The string for key with {name} placeholders replaced; a missing key is returned as "[key]" (caught by the tests).
  String t(String key, [Map<String, Object?> params = const {}]) {
    var s = _map[key];
    if (s == null) return '[$key]';
    params.forEach((k, v) => s = s!.replaceAll('{$k}', '$v'));
    return s!;
  }

  bool has(String key) => _map.containsKey(key);

  Iterable<String> get keys => _map.keys;
}
