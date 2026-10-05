// G1 common native module (iOS) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
import Foundation

/// G1-QR-1.0 validation (same order and codes as QrValidator.java): foreign payload (not "G1SYN:") -> size (<= 2,953 UTF-8
/// bytes) -> field format (6 fields, version "1", anchor A##, bundle version, basic UTC expiry, 86-character base64url
/// signature) -> trusted time -> signature by a trusted, unrevoked, unexpired key over the UTF-8 prefix before the last colon
/// -> expiry -> known anchor in the active bundle -> bundle version equals the active bundle.
/// A valid identity NEVER establishes pose, floor or arrival.
public enum QrValidator {
    public static let maxPayloadBytes = 2953

    public struct Anchor {
        public let id: String
        public let node: String
        public let building: String
        public let floor: Int
        public let kind: String
    }

    public struct Outcome {
        public let code: String
        public let anchor: Anchor?

        /// {"outcome", "anchor"?, "building"?, "floor"?, "kind"?, "pose_established": false} in this key order.
        public func toJson() -> String {
            var pairs: [(String, Any?)] = [("outcome", code)]
            if let a = anchor {
                pairs.append(("anchor", a.id))
                pairs.append(("building", a.building))
                pairs.append(("floor", a.floor))
                pairs.append(("kind", a.kind))
            }
            pairs.append(("pose_established", false))
            return Json.object(pairs)
        }
    }

    public static func parseAnchors(_ qrIdentitiesJson: Data) throws -> [String: Anchor] {
        let root = try Json.parseObject(qrIdentitiesJson)
        guard let arr = root["anchors"] as? [Any] else { throw Json.Invalid() }
        var out: [String: Anchor] = [:]
        for item in arr {
            guard let a = item as? [String: Any], let id = Json.string(a["id"]), let node = Json.string(a["node"]),
                  let building = Json.string(a["building"]), let floor = Json.number(a["floor"]), let kind = Json.string(a["kind"]) else {
                throw Json.Invalid()
            }
            out[id] = Anchor(id: id, node: node, building: building, floor: floor.intValue, kind: kind)
        }
        return out
    }

    private static func isDigit(_ c: UInt8) -> Bool { c >= 48 && c <= 57 }

    static func anchorFormat(_ u: ArraySlice<UInt8>) -> Bool {
        let a = Array(u)
        return a.count == 3 && a[0] == 65 && isDigit(a[1]) && isDigit(a[2])
    }

    static func signatureFormat(_ u: ArraySlice<UInt8>) -> Bool {
        u.count == 86 && u.allSatisfy { c in (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || isDigit(c) || c == 95 || c == 45 }
    }

    /// Byte-level (UTF-8) semantics so that the colon split and the prefix checks match the Android implementation exactly.
    public static func validate(_ payload: String?, store: TrustStore, anchors: [String: Anchor]?, activeVersion: String?,
                                nowMs: Int64, timeTrusted: Bool) -> Outcome {
        guard let payload else { return Outcome(code: TrustCodes.rejectForeignPayload, anchor: nil) }
        let bytes = Array(payload.utf8)
        if !bytes.starts(with: Array("G1SYN:".utf8)) { return Outcome(code: TrustCodes.rejectForeignPayload, anchor: nil) }
        if bytes.count > maxPayloadBytes { return Outcome(code: TrustCodes.rejectMalformed, anchor: nil) }
        let parts = bytes.split(separator: 0x3A, omittingEmptySubsequences: false)
        guard parts.count == 6, Array(parts[1]) == [0x31], anchorFormat(parts[2]),
              BundleVerifier.parseVersion(String(decoding: parts[3], as: UTF8.self)) != nil,
              let expiry = IsoTime.parseBasic(String(decoding: parts[4], as: UTF8.self)), signatureFormat(parts[5]) else {
            return Outcome(code: TrustCodes.rejectMalformed, anchor: nil)
        }
        if !timeTrusted { return Outcome(code: TrustCodes.rejectUntrustedTime, anchor: nil) }
        let lastColon = bytes.lastIndex(of: 0x3A)!
        let prefix = Data(bytes[0..<lastColon])
        guard let sig = Hex.fromBase64Url(String(decoding: parts[5], as: UTF8.self)) else {
            return Outcome(code: TrustCodes.rejectBadSignature, anchor: nil)
        }
        var ok = false
        for k in store.keys where !k.revoked && nowMs <= k.validUntilMs {
            if Ed25519.verify(publicKey: k.publicKey, message: prefix, signature: sig) {
                ok = true
                break
            }
        }
        if !ok { return Outcome(code: TrustCodes.rejectBadSignature, anchor: nil) }
        if nowMs > expiry { return Outcome(code: TrustCodes.rejectExpired, anchor: nil) }
        guard let anchors, let activeVersion else { return Outcome(code: TrustCodes.rejectNoBundle, anchor: nil) }
        guard let a = anchors[String(decoding: parts[2], as: UTF8.self)] else {
            return Outcome(code: TrustCodes.rejectUnknownAnchor, anchor: nil)
        }
        if String(decoding: parts[3], as: UTF8.self) != activeVersion { return Outcome(code: TrustCodes.rejectBundleMismatch, anchor: nil) }
        return Outcome(code: TrustCodes.identityValid, anchor: a)
    }
}
