// G1 common native module (iOS) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation

/// Small encoding helpers shared by the trust and QR code (same semantics as Hex.java on Android).
public enum Hex {
    public static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Strict base64url without padding; nil for any other character, an impossible length or non-zero trailing bits.
    public static func fromBase64Url(_ s: String) -> Data? {
        let chars = Array(s.utf8)
        if chars.count % 4 == 1 { return nil }
        var out = Data(capacity: chars.count * 3 / 4)
        var acc: UInt32 = 0
        var bits = 0
        for c in chars {
            let v: UInt32
            switch c {
            case 65...90: v = UInt32(c - 65)
            case 97...122: v = UInt32(c - 97 + 26)
            case 48...57: v = UInt32(c - 48 + 52)
            case 45: v = 62
            case 95: v = 63
            default: return nil
            }
            acc = ((acc << 6) | v) & 0xFFFFFF
            bits += 6
            if bits >= 8 {
                bits -= 8
                out.append(UInt8((acc >> UInt32(bits)) & 0xFF))
            }
        }
        if bits > 0 && (acc & ((1 << UInt32(bits)) - 1)) != 0 { return nil }
        return out
    }
}

/// Ed25519 verification of the synthetic lab signatures (CryptoKit on iOS).
public enum Ed25519 {
    public static func verify(publicKey: Data, message: Data, signature: Data) -> Bool {
        guard publicKey.count == 32, signature.count == 64,
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey) else { return false }
        return key.isValidSignature(signature, for: message)
    }
}
