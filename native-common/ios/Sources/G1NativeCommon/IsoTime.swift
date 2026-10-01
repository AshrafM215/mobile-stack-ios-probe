// G1 common native module (iOS) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
import Foundation

/// UTC "YYYY-MM-DDTHH:MM:SSZ" and the QR basic form "YYYYMMDDTHHMMSSZ"; milliseconds since 1970 or nil.
public enum IsoTime {
    static func daysFromCivil(_ y0: Int64, _ m: Int64, _ d: Int64) -> Int64 {
        let y = y0 - (m <= 2 ? 1 : 0)
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }

    private static func digits(_ s: [UInt8], _ from: Int, _ len: Int) -> Int64? {
        var v: Int64 = 0
        for i in from..<(from + len) {
            let c = s[i]
            guard c >= 48 && c <= 57 else { return nil }
            v = v * 10 + Int64(c - 48)
        }
        return v
    }

    private static func millis(_ y: Int64?, _ mo: Int64?, _ d: Int64?, _ h: Int64?, _ mi: Int64?, _ se: Int64?) -> Int64? {
        guard let y, let mo, let d, let h, let mi, let se, (1...12).contains(mo), d >= 1, h <= 23, mi <= 59, se <= 59 else { return nil }
        let leap = (y % 4 == 0 && (y % 100 != 0 || y % 400 == 0))
        let dim: [Int64] = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        guard d <= dim[Int(mo) - 1] else { return nil }
        return ((daysFromCivil(y, mo, d) * 24 + h) * 60 + mi) * 60_000 + se * 1000
    }

    public static func parseExtended(_ str: String) -> Int64? {
        let s = Array(str.utf8)
        guard s.count == 20, s[4] == 45, s[7] == 45, s[10] == 84, s[13] == 58, s[16] == 58, s[19] == 90 else { return nil }
        return millis(digits(s, 0, 4), digits(s, 5, 2), digits(s, 8, 2), digits(s, 11, 2), digits(s, 14, 2), digits(s, 17, 2))
    }

    public static func parseBasic(_ str: String) -> Int64? {
        let s = Array(str.utf8)
        guard s.count == 16, s[8] == 84, s[15] == 90 else { return nil }
        return millis(digits(s, 0, 4), digits(s, 4, 2), digits(s, 6, 2), digits(s, 9, 2), digits(s, 11, 2), digits(s, 13, 2))
    }

    public static func nowMs() -> Int64 { Int64((Date().timeIntervalSince1970 * 1000).rounded(.down)) }
}
