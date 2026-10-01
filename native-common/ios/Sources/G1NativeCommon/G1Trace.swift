// G1 common native module (iOS) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
import Foundation
#if canImport(os)
import os
#endif

/// Common clock and trace markers (IR-COMMON-MARKERS): unified log subsystem com.example.g1bench, category G1MARK (public).
/// One line per marker: "G1MARK v=1 app=<A|B|C> seq=<n> name=<name> t=<native ns> rt=<runtime ns> k=v ...". Keys and values are
/// encoded exactly like java.net.URLEncoder (UTF-8) on Android. Values are identifiers, codes, enums or numbers only: never
/// user-entered text, payloads, routes or canaries.
public enum G1Trace {
    #if canImport(os)
    private static let logger = Logger(subsystem: "com.example.g1bench", category: "G1MARK")
    #endif
    private static let lock = NSLock()
    private static var seq: UInt64 = 0
    private static var appId = "?"

    public static var app: String { lock.lock(); defer { lock.unlock() }; return appId }

    public static func setApp(_ id: String) {
        lock.lock()
        appId = id
        lock.unlock()
    }

    /// CLOCK_MONOTONIC_RAW nanoseconds (mach_continuous_time base: monotonic, includes sleep, like CLOCK_BOOTTIME on
    /// Android); the runtimes read the same clock (A: dart:ffi, B: JSI, C: direct).
    public static func nowNanos() -> UInt64 {
        #if canImport(Darwin)
        return clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)
        #else
        var ts = timespec()
        clock_gettime(CLOCK_MONOTONIC_RAW, &ts)
        return UInt64(ts.tv_sec) * 1_000_000_000 + UInt64(ts.tv_nsec)
        #endif
    }

    /// java.net.URLEncoder.encode(s, "UTF-8"): [A-Za-z0-9.*_-] kept, space as '+', every other UTF-8 byte as %XX (upper case).
    public static func encode(_ value: String) -> String {
        var out = ""
        out.reserveCapacity(value.utf8.count)
        let hex = Array("0123456789ABCDEF")
        for b in value.utf8 {
            switch b {
            case 0x30...0x39, 0x41...0x5A, 0x61...0x7A, 0x2E, 0x2D, 0x2A, 0x5F:
                out.append(Character(UnicodeScalar(b)))
            case 0x20:
                out.append("+")
            default:
                out.append("%")
                out.append(hex[Int(b >> 4)])
                out.append(hex[Int(b & 0x0F)])
            }
        }
        return out
    }

    /// Builds the marker line (exposed for tests); `fields` are key/value pairs in order.
    public static func line(_ name: String, runtimeNanos: Int64, _ fields: [(String, String)], seq n: UInt64, t: UInt64) -> String {
        var line = "G1MARK v=1 app=\(app) seq=\(n) name=\(encode(name)) t=\(t) rt=\(runtimeNanos < 0 ? "-" : String(runtimeNanos))"
        for (k, v) in fields { line += " \(encode(k))=\(encode(v))" }
        return line
    }

    public static func mark(_ name: String, runtimeNanos: Int64 = -1, _ fields: [(String, String)] = []) {
        lock.lock()
        seq += 1
        let n = seq
        lock.unlock()
        let text = line(name, runtimeNanos: runtimeNanos, fields, seq: n, t: nowNanos())
        #if canImport(os)
        logger.notice("\(text, privacy: .public)") // default level: persisted, visible to `log show` without flags
        #endif
        // Lab builds also write the same line to standard error (one write per line, serialized), which the simulator
        // harness captures with `simctl launch --stderr`; iOS markers are feasibility evidence only (no iOS measurement).
        if BuildFlags.lab {
            let bytes = Data((text + "\n").utf8)
            lock.lock()
            FileHandle.standardError.write(bytes)
            lock.unlock()
        }
    }
}
