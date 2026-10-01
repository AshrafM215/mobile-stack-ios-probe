// Candidate C (native iOS) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// In-app bilingual strings (contract/strings/en.json and ar.json, copied into the app resources).
import Foundation

struct Strings {
    let lang: String
    private let map: [String: String]

    init(lang: String, map: [String: String]) {
        self.lang = lang
        self.map = map
    }

    var rtl: Bool { map["_meta.direction"] == "rtl" }

    /// The string for key with {name} placeholders replaced; a missing key is returned as "[key]" (caught by the tests).
    func t(_ key: String, _ params: [String: Any?] = [:]) -> String {
        guard var s = map[key] else { return "[\(key)]" }
        for (k, v) in params { s = s.replacingOccurrences(of: "{\(k)}", with: v.map { "\($0)" } ?? "nil") }
        return s
    }

    func has(_ key: String) -> Bool { map[key] != nil }

    var keys: Set<String> { Set(map.keys) }

    static func parse(_ lang: String, _ json: String) throws -> Strings {
        guard let o = try JSON.decode(json) as? [String: Any] else { throw FormatError("strings") }
        var m: [String: String] = [:]
        for (k, v) in o {
            guard let s = v as? String else { throw FormatError("strings") }
            m[k] = s
        }
        return Strings(lang: lang, map: m)
    }
}
