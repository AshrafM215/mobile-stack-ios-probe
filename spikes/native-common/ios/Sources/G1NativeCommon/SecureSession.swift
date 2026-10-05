// G1 common native module (iOS) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
#if canImport(Security) && canImport(CryptoKit)
import CryptoKit
import Foundation
import Security

/// Synthetic session marker storage for the STO cases (same behaviour as SecureSession.java): AES-256-GCM with a key held
/// only in the Keychain (this device only, after first unlock); only the ciphertext is written (Application Support,
/// excluded from backup, complete file protection). Logout deletes the ciphertext and the key; a missing key means
/// "inactive" and never silently restores a session. The marker value is never logged.
public enum SecureSession {
    private static let service = "com.example.g1bench.session"
    private static let account = "g1_session_key"
    private static let fileName = "g1session.bin"

    private static func file() -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(fileName)
    }

    private static func baseQuery() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    private static func loadKey() -> SymmetricKey? {
        var q = baseQuery()
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data, data.count == 32 else { return nil }
        return SymmetricKey(data: data)
    }

    private static func createKey() -> SymmetricKey? {
        SecItemDelete(baseQuery() as CFDictionary)
        let key = SymmetricKey(size: .bits256)
        var q = baseQuery()
        q[kSecValueData as String] = key.withUnsafeBytes { Data($0) }
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess ? key : nil
    }

    public static func start(_ marker: String) -> Bool {
        guard let key = loadKey() ?? createKey(), let sealed = try? AES.GCM.seal(Data(marker.utf8), using: key),
              let combined = sealed.combined else { return false }
        do {
            let url = file()
            try BundleStore.writeAtomically(url, combined)
            try (url as NSURL).setResourceValue(true, forKey: .isExcludedFromBackupKey)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
            return true
        } catch {
            return false
        }
    }

    /// True when a marker decrypts with the current key; a stale ciphertext without its key is removed.
    public static func active() -> Bool {
        let url = file()
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        if let key = loadKey(), let data = try? Data(contentsOf: url), let box = try? AES.GCM.SealedBox(combined: data),
           (try? AES.GCM.open(box, using: key)) != nil {
            return true
        }
        try? FileManager.default.removeItem(at: url)
        return false
    }

    public static func end() {
        try? FileManager.default.removeItem(at: file())
        SecItemDelete(baseQuery() as CFDictionary)
    }
}
#endif
