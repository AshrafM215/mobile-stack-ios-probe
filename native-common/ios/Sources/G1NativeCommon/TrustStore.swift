// G1 common native module (iOS) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
import Foundation

/// Synthetic lab trust store compiled into every build (public keys only; identical for A, B and C).
public final class TrustStore {
    public struct Key {
        public let keyId: String
        public let publicKey: Data
        public let revoked: Bool
        public let validUntilMs: Int64 // Int64.max when unlimited
    }

    public let keys: [Key]

    private init(keys: [Key]) { self.keys = keys }

    public static func parse(_ json: Data) throws -> TrustStore {
        let root = try Json.parseObject(json)
        guard Json.string(root["trust_contract"]) == "G1-TRUST-1.0", Json.string(root["algorithm"]) == "Ed25519",
              let arr = root["keys"] as? [Any] else { throw Json.Invalid() }
        var list: [Key] = []
        for item in arr {
            guard let k = item as? [String: Any], let keyId = Json.string(k["key_id"]), let pubText = Json.string(k["public_key"]),
                  let status = Json.string(k["status"]) else { throw Json.Invalid() }
            guard let pub = Hex.fromBase64Url(pubText), pub.count == 32 else { throw Json.Invalid() }
            var until = Int64.max
            if !Json.isNullOrMissing(k["valid_until"]) {
                guard let text = Json.string(k["valid_until"]), let v = IsoTime.parseExtended(text) else { throw Json.Invalid() }
                until = v
            }
            list.append(Key(keyId: keyId, publicKey: pub, revoked: status == "revoked", validUntilMs: until))
        }
        return TrustStore(keys: list)
    }

    public func find(_ keyId: String) -> Key? { keys.first { $0.keyId == keyId } }
}
