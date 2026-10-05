// Candidate C (native iOS) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// Strict JSON access over Foundation's JSONSerialization (RFC 8259; booleans are never numbers, integers are never
// floating point) and a deterministic writer for the lab result files.
import Foundation
#if canImport(CoreFoundation)
import CoreFoundation
#endif

struct FormatError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

enum JSON {
    static let maxChars = 16 * 1024 * 1024

    static func decode(_ text: String) throws -> Any {
        if text.utf16.count > maxChars { throw FormatError("too large") }
        do {
            return try JSONSerialization.jsonObject(with: Data(text.utf8), options: [])
        } catch {
            throw FormatError("json")
        }
    }

    static func isBool(_ v: Any) -> Bool {
        #if canImport(Darwin)
        if let n = v as? NSNumber { return CFGetTypeID(n as CFTypeRef) == CFBooleanGetTypeID() }
        return false
        #else
        // swift-corelibs-foundation: JSON booleans are __NSCFBoolean; a numeric NSNumber of 0 or 1 also casts to Bool, so
        // only the dynamic type distinguishes them (plain Swift Bool values come from the app's own writer input)
        return String(describing: type(of: v)) == "__NSCFBoolean" || type(of: v) == Bool.self
        #endif
    }

    private static let integerTypes: Set<String> = ["c", "s", "i", "l", "q", "C", "S", "I", "L", "Q"]

    /// A JSON integer (no fraction or exponent, never a boolean), else nil.
    static func integer(_ v: Any?) -> Int64? {
        guard let v, !(v is NSNull), !isBool(v) else { return nil }
        if let n = v as? NSNumber {
            return integerTypes.contains(String(cString: n.objCType)) ? n.int64Value : nil
        }
        if let i = v as? Int { return Int64(i) }
        return nil
    }

    static func bool(_ v: Any?) -> Bool? {
        guard let v, isBool(v) else { return nil }
        if let n = v as? NSNumber { return n.boolValue }
        return v as? Bool
    }

    // ---------------- writer ----------------

    static func quote(_ s: String) -> String {
        var out = "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if u.value < 0x20 { out += String(format: "\\u%04x", u.value) } else { out.unicodeScalars.append(u) }
            }
        }
        return out + "\""
    }

    /// Ordered object for result files.
    struct Object {
        var pairs: [(String, Any?)]
        init(_ pairs: [(String, Any?)]) { self.pairs = pairs }
    }

    /// Values: nil/NSNull, Object, String, Bool, integers, Double, arrays, [String: Any] (keys sorted) or parsed JSON values.
    static func encode(_ value: Any?) -> String {
        guard let v = value, !(v is NSNull) else { return "null" }
        if let o = v as? Object { return "{" + o.pairs.map { quote($0.0) + ":" + encode($0.1) }.joined(separator: ",") + "}" }
        if let s = v as? String { return quote(s) }
        if isBool(v) { return (bool(v) ?? false) ? "true" : "false" }
        if type(of: v) == Int.self, let i = v as? Int { return String(i) }
        if type(of: v) == Int64.self, let i = v as? Int64 { return String(i) }
        if type(of: v) == UInt64.self, let i = v as? UInt64 { return String(i) }
        if type(of: v) == Double.self, let d = v as? Double { return d.isFinite ? String(d) : "null" }
        if let i = integer(v) { return String(i) }
        if let a = v as? [Any?] { return "[" + a.map { encode($0) }.joined(separator: ",") + "]" }
        if let a = v as? [Any] { return "[" + a.map { encode($0) }.joined(separator: ",") + "]" }
        if let m = v as? [String: Any] { return "{" + m.keys.sorted().map { quote($0) + ":" + encode(m[$0]) }.joined(separator: ",") + "}" }
        if let n = v as? NSNumber { return n.doubleValue.isFinite ? String(n.doubleValue) : "null" }
        return quote(String(describing: v))
    }
}
