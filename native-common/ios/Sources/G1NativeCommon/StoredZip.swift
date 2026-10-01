// G1 common native module (iOS) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
import Foundation

/// Reader for the bundle container of G1-TRUST-1.0 (same rules as StoredZip.java): a ZIP with stored (method 0) entries only,
/// no encryption, no data descriptors, no ZIP64, no archive comment. Names are valid UTF-8 relative paths without "..", ".",
/// backslashes, NUL, empty segments or duplicates. Sizes are bounded before any allocation. Any violation throws Malformed.
public enum StoredZip {
    public static let maxEntries = 256
    public static let maxTotalBytes = 64 * 1024 * 1024
    public static let maxEntryBytes = 16 * 1024 * 1024

    public struct Malformed: Error, CustomStringConvertible {
        public let reason: String
        public var description: String { "malformed container: \(reason)" }
    }

    private static func u16(_ b: UnsafeRawBufferPointer, _ o: Int) -> Int {
        Int(b[o]) | (Int(b[o + 1]) << 8)
    }

    private static func u32(_ b: UnsafeRawBufferPointer, _ o: Int) -> Int {
        Int(b[o]) | (Int(b[o + 1]) << 8) | (Int(b[o + 2]) << 16) | (Int(b[o + 3]) << 24)
    }

    public static func checkName(_ name: String) throws {
        if name.isEmpty || name.hasPrefix("/") || name.hasSuffix("/") || name.contains("\\") || name.unicodeScalars.contains("\u{0}") {
            throw Malformed(reason: "bad name")
        }
        for part in name.split(separator: "/", omittingEmptySubsequences: false) {
            if part.isEmpty || part == "." || part == ".." { throw Malformed(reason: "bad name segment") }
        }
    }

    private static func utf8Name(_ b: UnsafeRawBufferPointer, _ start: Int, _ count: Int) throws -> String {
        guard let s = String(bytes: UnsafeRawBufferPointer(rebasing: b[start..<(start + count)]), encoding: .utf8) else {
            throw Malformed(reason: "name encoding")
        }
        return s
    }

    /// Parses and fully validates a stored ZIP; returns entries by name.
    public static func read(_ zip: Data) throws -> [String: Data] {
        if zip.count < 22 || zip.count > maxTotalBytes + 1024 * 1024 { throw Malformed(reason: "size") }
        return try zip.withUnsafeBytes { (b: UnsafeRawBufferPointer) -> [String: Data] in
            let eocd = b.count - 22
            if u32(b, eocd) != 0x0605_4B50 { throw Malformed(reason: "no end record (comments are not allowed)") }
            let disk = u16(b, eocd + 4), cdDisk = u16(b, eocd + 6)
            let count = u16(b, eocd + 8), total = u16(b, eocd + 10)
            let cdSize = u32(b, eocd + 12), cdOffset = u32(b, eocd + 16)
            if disk != 0 || cdDisk != 0 || count != total || count == 0 || count > maxEntries { throw Malformed(reason: "entries") }
            if cdOffset + cdSize != eocd { throw Malformed(reason: "central directory bounds") }
            var out: [String: Data] = [:]
            var sum = 0
            var p = cdOffset
            for _ in 0..<count {
                if p + 46 > eocd || u32(b, p) != 0x0201_4B50 { throw Malformed(reason: "central header") }
                let flags = u16(b, p + 8), method = u16(b, p + 10)
                let crcValue = u32(b, p + 16), csize = u32(b, p + 20), usize = u32(b, p + 24)
                let nameLen = u16(b, p + 28), extraLen = u16(b, p + 30), commentLen = u16(b, p + 32)
                let localOffset = u32(b, p + 42)
                if (flags & ~0x0800) != 0 || method != 0 || csize != usize || extraLen != 0 || commentLen != 0 {
                    throw Malformed(reason: "unsupported entry")
                }
                sum += usize
                if usize > maxEntryBytes || sum > maxTotalBytes { throw Malformed(reason: "entry too large") }
                if p + 46 + nameLen > eocd { throw Malformed(reason: "name bounds") }
                let name = try utf8Name(b, p + 46, nameLen)
                try checkName(name)
                if out[name] != nil { throw Malformed(reason: "duplicate name") }
                if localOffset + 30 > cdOffset || u32(b, localOffset) != 0x0403_4B50 { throw Malformed(reason: "local header") }
                let lo = localOffset
                let lFlags = u16(b, lo + 6), lMethod = u16(b, lo + 8)
                let lCrc = u32(b, lo + 14), lc = u32(b, lo + 18), lu = u32(b, lo + 22)
                let lName = u16(b, lo + 26), lExtra = u16(b, lo + 28)
                if lFlags != flags || lMethod != 0 || lCrc != crcValue || lc != csize || lu != usize || lName != nameLen || lExtra != 0 {
                    throw Malformed(reason: "local/central mismatch")
                }
                if lo + 30 + lName > cdOffset { throw Malformed(reason: "local name bounds") }
                if try utf8Name(b, lo + 30, lName) != name { throw Malformed(reason: "local name mismatch") }
                let dataStart = lo + 30 + lName
                if dataStart + usize > cdOffset { throw Malformed(reason: "data bounds") }
                let data = Data(UnsafeRawBufferPointer(rebasing: b[dataStart..<(dataStart + usize)]))
                if Int(Crc32.checksum(data)) != crcValue { throw Malformed(reason: "crc") }
                out[name] = data
                p += 46 + nameLen
            }
            if p != eocd { throw Malformed(reason: "trailing central data") }
            return out
        }
    }
}

/// CRC-32 (IEEE 802.3, reflected polynomial 0xEDB88320), table driven; identical to java.util.zip.CRC32.
public enum Crc32 {
    static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? (0xEDB8_8320 ^ (c >> 1)) : (c >> 1) }
        return c
    }

    public static func update(_ crc: UInt32, _ bytes: UnsafeRawBufferPointer) -> UInt32 {
        var c = ~crc
        for byte in bytes { c = table[Int((c ^ UInt32(byte)) & 0xFF)] ^ (c >> 8) }
        return ~c
    }

    public static func checksum(_ data: Data) -> UInt32 {
        data.withUnsafeBytes { update(0, $0) }
    }
}
