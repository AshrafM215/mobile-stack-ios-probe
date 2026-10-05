// G1 common native module (iOS) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
import Foundation
#if canImport(CoreFoundation)
import CoreFoundation
#endif

/// Strict JSON access over JSONSerialization results (booleans are never numbers) and a small deterministic writer.
public enum Json {
    public struct Invalid: Error {}

    public static func parseObject(_ data: Data) throws -> [String: Any] {
        guard let o = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else { throw Invalid() }
        return o
    }

    public static func isBool(_ v: Any) -> Bool {
        #if canImport(Darwin)
        if let n = v as? NSNumber { return CFGetTypeID(n as CFTypeRef) == CFBooleanGetTypeID() }
        return false
        #else
        return String(describing: type(of: v)) == "__NSCFBoolean"
        #endif
    }

    /// A JSON number (never a boolean), else nil.
    public static func number(_ v: Any?) -> NSNumber? {
        guard let v, !(v is NSNull), !isBool(v), let n = v as? NSNumber else { return nil }
        return n
    }

    public static func string(_ v: Any?) -> String? { v as? String }

    public static func isNullOrMissing(_ v: Any?) -> Bool { v == nil || v is NSNull }

    /// JSON string literal with the minimal escapes (same output for every runtime).
    public static func quote(_ s: String) -> String {
        var out = "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if u.value < 0x20 {
                    out += String(format: "\\u%04x", u.value)
                } else {
                    out.unicodeScalars.append(u)
                }
            }
        }
        return out + "\""
    }

    /// Ordered writer for flat result objects: values are String, Bool, Int, Int64, UInt64, Double, nil (null) or a
    /// pre-encoded JSON fragment (Raw).
    public struct Raw { public let json: String; public init(_ json: String) { self.json = json } }

    public static func object(_ pairs: [(String, Any?)]) -> String {
        var parts: [String] = []
        for (k, v) in pairs { parts.append(quote(k) + ":" + value(v)) }
        return "{" + parts.joined(separator: ",") + "}"
    }

    public static func array(_ values: [Any?]) -> String { "[" + values.map { value($0) }.joined(separator: ",") + "]" }

    public static func value(_ v: Any?) -> String {
        switch v {
        case nil: return "null"
        case let r as Raw: return r.json
        case let s as String: return quote(s)
        case let b as Bool: return b ? "true" : "false"
        case let i as Int: return String(i)
        case let i as Int64: return String(i)
        case let i as UInt64: return String(i)
        case let i as Int32: return String(i)
        case let d as Double: return d.isFinite ? String(d) : "null"
        default: return quote(String(describing: v!))
        }
    }
}
