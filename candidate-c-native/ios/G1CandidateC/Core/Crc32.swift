// Candidate C (native iOS) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// CRC-32 (IEEE 802.3, reflected 0xEDB88320) written in Swift: the runtime side of the bridge workload control series.
import Foundation

enum Crc32 {
    private static let table: [UInt32] = (0..<256).map { i in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func of(_ bytes: UnsafeRawBufferPointer) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        for b in bytes { c = table[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFF_FFFF
    }

    static func of(_ data: Data) -> UInt32 { data.withUnsafeBytes { of($0) } }
}
