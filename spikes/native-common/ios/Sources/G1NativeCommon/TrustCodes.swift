// G1 common native module (iOS) - NON-PRODUCTION / SYNTHETIC DATA ONLY.

/// Exact outcome codes of G1-TRUST-1.0 and G1-QR-1.0 (shared by every candidate and by the oracle; same as TrustCodes.java).
public enum TrustCodes {
    public static let activated = "ACTIVATED"
    public static let rollbackActivated = "ROLLBACK_ACTIVATED"
    public static let rejectMalformedContainer = "REJECT_MALFORMED_CONTAINER"
    public static let rejectMalformedManifest = "REJECT_MALFORMED_MANIFEST"
    public static let rejectUntrustedTime = "REJECT_UNTRUSTED_TIME"
    public static let rejectUnknownKey = "REJECT_UNKNOWN_KEY"
    public static let rejectRevokedKey = "REJECT_REVOKED_KEY"
    public static let rejectExpiredKey = "REJECT_EXPIRED_KEY"
    public static let rejectBadSignature = "REJECT_BAD_SIGNATURE"
    public static let rejectSchema = "REJECT_SCHEMA"
    public static let rejectUnsupportedVersion = "REJECT_UNSUPPORTED_VERSION"
    public static let rejectHashMismatch = "REJECT_HASH_MISMATCH"
    public static let rejectNotYetValid = "REJECT_NOT_YET_VALID"
    public static let rejectExpired = "REJECT_EXPIRED"
    public static let rejectDowngrade = "REJECT_DOWNGRADE"
    public static let rejectAlreadyActive = "REJECT_ALREADY_ACTIVE"
    public static let rejectNoPrevious = "REJECT_NO_PREVIOUS"
    public static let rejectIO = "REJECT_IO"

    public static let identityValid = "IDENTITY_VALID"
    public static let rejectForeignPayload = "REJECT_FOREIGN_PAYLOAD"
    public static let rejectMalformed = "REJECT_MALFORMED"
    public static let rejectUnknownAnchor = "REJECT_UNKNOWN_ANCHOR"
    public static let rejectBundleMismatch = "REJECT_BUNDLE_MISMATCH"
    public static let rejectNoBundle = "REJECT_NO_BUNDLE"
}
