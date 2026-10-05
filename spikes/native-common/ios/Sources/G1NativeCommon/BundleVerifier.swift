// G1 common native module (iOS) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
import Foundation

/// G1-TRUST-1.0 verification of one offered bundle, in this exact order (the first failing step decides the code; same as
/// BundleVerifier.java): container -> manifest/signature records -> trusted time -> key (unknown/revoked/expired) -> signature
/// over MANIFEST.json -> schema_version == 1 -> bundle_version format and major <= 1 -> every listed file present with size
/// and SHA-256 and no unlisted file -> validity window -> version policy against the active bundle (older = downgrade,
/// equal = already active).
public enum BundleVerifier {
    public static let manifestName = "MANIFEST.json"
    public static let signatureName = "bundle_signature.json"

    public struct Result {
        public let code: String
        public let version: String?
        public let validFromMs: Int64
        public let validUntilMs: Int64
        public let manifestSha256: String?
        /// Every entry to persist (payload, manifest, signature) on success; nil on rejection.
        public let files: [String: Data]?

        public var ok: Bool { files != nil }

        static func reject(_ code: String) -> Result {
            Result(code: code, version: nil, validFromMs: 0, validUntilMs: 0, manifestSha256: nil, files: nil)
        }
    }

    /// "G1SYN-<major>.<minor>.<patch>" with 1-4 ASCII digits per part; nil when malformed.
    public static func parseVersion(_ v: String?) -> [Int]? {
        guard let v, v.hasPrefix("G1SYN-") else { return nil }
        let parts = v.dropFirst(6).split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var out: [Int] = []
        for p in parts {
            guard (1...4).contains(p.utf8.count), p.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }), let n = Int(p) else { return nil }
            out.append(n)
        }
        return out
    }

    public static func compareVersions(_ a: [Int], _ b: [Int]) -> Int {
        for i in 0..<3 where a[i] != b[i] { return a[i] < b[i] ? -1 : 1 }
        return 0
    }

    public static func verifyZip(_ zip: Data, store: TrustStore, nowMs: Int64, timeTrusted: Bool, activeVersion: String?) -> Result {
        let entries: [String: Data]
        do {
            entries = try StoredZip.read(zip)
        } catch {
            return .reject(TrustCodes.rejectMalformedContainer)
        }
        return verifyEntries(entries, store: store, nowMs: nowMs, timeTrusted: timeTrusted, activeVersion: activeVersion, applyVersionPolicy: true)
    }

    /// Verifies an already extracted file set (also used for the startup re-verification of the active bundle).
    public static func verifyEntries(_ entries: [String: Data], store: TrustStore, nowMs: Int64, timeTrusted: Bool,
                                     activeVersion: String?, applyVersionPolicy: Bool) -> Result {
        guard let manifestBytes = entries[manifestName], let sigBytes = entries[signatureName] else {
            return .reject(TrustCodes.rejectMalformedManifest)
        }
        guard let manifest = try? Json.parseObject(manifestBytes), let sig = try? Json.parseObject(sigBytes),
              let algorithm = Json.string(sig["algorithm"]), let keyId = Json.string(sig["key_id"]),
              let sigText = Json.string(sig["signature"]) else {
            return .reject(TrustCodes.rejectMalformedManifest)
        }
        guard algorithm == "Ed25519", let signature = Hex.fromBase64Url(sigText), signature.count == 64 else {
            return .reject(TrustCodes.rejectMalformedManifest)
        }
        if !timeTrusted { return .reject(TrustCodes.rejectUntrustedTime) }
        guard let key = store.find(keyId) else { return .reject(TrustCodes.rejectUnknownKey) }
        if key.revoked { return .reject(TrustCodes.rejectRevokedKey) }
        if nowMs > key.validUntilMs { return .reject(TrustCodes.rejectExpiredKey) }
        if !Ed25519.verify(publicKey: key.publicKey, message: manifestBytes, signature: signature) {
            return .reject(TrustCodes.rejectBadSignature)
        }
        guard let schema = Json.number(manifest["schema_version"]), schema.doubleValue == 1.0 else {
            return .reject(TrustCodes.rejectSchema)
        }
        guard let versionText = Json.string(manifest["bundle_version"]) else { return .reject(TrustCodes.rejectMalformedManifest) }
        guard let version = parseVersion(versionText), version[0] <= 1 else { return .reject(TrustCodes.rejectUnsupportedVersion) }
        guard let files = manifest["files"] as? [Any] else { return .reject(TrustCodes.rejectMalformedManifest) }
        var listed = Set<String>()
        var payload: [String: Data] = [:]
        for item in files {
            guard let f = item as? [String: Any], let path = Json.string(f["path"]) else {
                return .reject(TrustCodes.rejectMalformedManifest)
            }
            let data = entries[path]
            if path == manifestName || path == signatureName || !listed.insert(path).inserted || data == nil {
                return .reject(TrustCodes.rejectHashMismatch)
            }
            guard let bytes = Json.number(f["bytes"]) else { return .reject(TrustCodes.rejectMalformedManifest) }
            if Double(data!.count) != bytes.doubleValue { return .reject(TrustCodes.rejectHashMismatch) }
            guard let sha = Json.string(f["sha256"]) else { return .reject(TrustCodes.rejectMalformedManifest) }
            if Hex.sha256(data!) != sha { return .reject(TrustCodes.rejectHashMismatch) }
            payload[path] = data!
        }
        for name in entries.keys where name != manifestName && name != signatureName && !listed.contains(name) {
            return .reject(TrustCodes.rejectHashMismatch)
        }
        guard let fromText = Json.string(manifest["valid_from"]), let untilText = Json.string(manifest["valid_until"]),
              let from = IsoTime.parseExtended(fromText), let until = IsoTime.parseExtended(untilText) else {
            return .reject(TrustCodes.rejectMalformedManifest)
        }
        if nowMs < from { return .reject(TrustCodes.rejectNotYetValid) }
        if nowMs > until { return .reject(TrustCodes.rejectExpired) }
        if applyVersionPolicy, let activeVersion, let active = parseVersion(activeVersion) {
            let c = compareVersions(version, active)
            if c < 0 { return .reject(TrustCodes.rejectDowngrade) }
            if c == 0 { return .reject(TrustCodes.rejectAlreadyActive) }
        }
        payload[manifestName] = manifestBytes
        payload[signatureName] = sigBytes
        return Result(code: TrustCodes.activated, version: versionText, validFromMs: from, validUntilMs: until,
                      manifestSha256: Hex.sha256(manifestBytes), files: payload)
    }
}
