// Candidate C (native iOS) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// G1-SEARCH-1.0 in Swift (NFKC through Foundation's compatibility precomposition), on Unicode scalars.
import Foundation

private func removed(_ v: UInt32) -> Bool {
    v == 0x0640 || (0x064B...0x065F).contains(v) || v == 0x0670 || v == 0x061C || (0x200B...0x200F).contains(v) ||
        (0x202A...0x202E).contains(v) || (0x2060...0x2069).contains(v) || v == 0xFEFF
}

private func separator(_ v: UInt32) -> Bool {
    (0x0009...0x000D).contains(v) || v == 0x0020 || v == 0x0085 || v == 0x00A0 || v == 0x1680 || (0x2000...0x200A).contains(v) ||
        v == 0x2028 || v == 0x2029 || v == 0x202F || v == 0x205F || v == 0x3000 || v == 0x002D || (0x2010...0x2015).contains(v) || v == 0x2212
}

func normalizeScalars(_ s: String) -> [UInt32] {
    var out: [UInt32] = []
    for u in s.precomposedStringWithCompatibilityMapping.unicodeScalars {
        let r = u.value
        let m: UInt32
        if (0x0660...0x0669).contains(r) { m = r - 0x0660 + 48 }
        else if (0x06F0...0x06F9).contains(r) { m = r - 0x06F0 + 48 }
        else if (0x41...0x5A).contains(r) { m = r + 32 }
        else { m = r }
        if !removed(m) { out.append(m) }
    }
    return out
}

private func string(_ scalars: ArraySlice<UInt32>) -> String {
    var s = String.UnicodeScalarView()
    for v in scalars { if let u = Unicode.Scalar(v) { s.append(u) } }
    return String(s)
}

func normalize(_ s: String) -> String { string(normalizeScalars(s)[...]) }

func tokens(_ s: String) -> [String] {
    let n = normalizeScalars(s)
    var out: [String] = []
    var start = 0
    for i in 0...n.count {
        if i == n.count || separator(n[i]) {
            if i > start { out.append(string(n[start..<i])) }
            start = i + 1
        }
    }
    return out
}

func codeKey(_ s: String) -> String {
    String(String.UnicodeScalarView(tokens(s).joined().unicodeScalars.map { ($0.value >= 0x61 && $0.value <= 0x7A) ? Unicode.Scalar($0.value - 32)! : $0 }))
}

/// ^SB[0-9]+F[0-9]+R[0-9]+$
func isCode(_ key: String) -> Bool {
    let b = Array(key.utf8)
    guard b.count >= 7, b[0] == 0x53, b[1] == 0x42 else { return false }
    var i = 2
    func digits() -> Bool {
        let s = i
        while i < b.count, b[i] >= 0x30, b[i] <= 0x39 { i += 1 }
        return i > s
    }
    guard digits(), i < b.count, b[i] == 0x46 else { return false }
    i += 1
    guard digits(), i < b.count, b[i] == 0x52 else { return false }
    i += 1
    return digits() && i == b.count
}

struct SearchResult {
    let outcome: String
    let ids: [String]
}

final class SearchIndex {
    private struct Entry {
        let id: String
        let codeKey: String
        let tokens: Set<String>
    }

    private let entries: [Entry]

    init(_ destinations: [Destination]) {
        entries = destinations.map { d in
            var set = Set(tokens(d.nameEn))
            set.formUnion(tokens(d.nameAr))
            set.insert(d.building.lowercased())
            set.insert("f\(d.floor)")
            set.insert("r\(d.roomNumber)")
            set.insert(d.roomNumber)
            set.insert(codeKey(d.code).lowercased())
            return Entry(id: d.id, codeKey: codeKey(d.code), tokens: set)
        }
    }

    func search(_ query: String) -> SearchResult {
        let t = tokens(query)
        if t.isEmpty { return SearchResult(outcome: "NO_MATCH", ids: []) }
        let key = codeKey(query)
        let ids = (isCode(key) ? entries.filter { $0.codeKey == key } : entries.filter { e in t.allSatisfy { e.tokens.contains($0) } })
            .map { $0.id }.sorted()
        if ids.isEmpty { return SearchResult(outcome: "NO_MATCH", ids: []) }
        return SearchResult(outcome: ids.count == 1 ? "UNIQUE_MATCH" : "AMBIGUOUS", ids: ids)
    }
}
