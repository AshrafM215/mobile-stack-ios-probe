// G1 common native module (iOS) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
import Foundation

/// Lab file locations (same rules as G1Files.java). import/: files placed by the harness (bundles, fixtures, QR images, fuzz
/// corpora); out/: run results written by the app. Both live under Documents/g1/ of the app container.
/// Names are single path segments drawn from [A-Za-z0-9._-] only, at most 128 characters, not starting with '.'.
public enum G1Files {
    public struct BadName: Error {}

    /// Overridable base for tests (defaults to <Documents>/g1).
    public static var baseOverride: URL?

    static func base() -> URL {
        if let baseOverride { return baseOverride }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return docs.appendingPathComponent("g1", isDirectory: true)
    }

    public static func importDir() -> URL {
        let d = base().appendingPathComponent("import", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    public static func outDir() -> URL {
        let d = base().appendingPathComponent("out", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    public static func safeName(_ name: String?) -> Bool {
        guard let name, !name.isEmpty, name.utf8.count <= 128, !name.hasPrefix(".") else { return false }
        return name.utf8.allSatisfy { c in
            (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 48 && c <= 57) || c == 46 || c == 95 || c == 45
        }
    }

    public static func readImport(_ name: String) throws -> Data {
        guard safeName(name) else { throw BadName() }
        return try BundleStore.readBytes(importDir().appendingPathComponent(name))
    }

    /// Writes out/<name> atomically and returns its SHA-256.
    @discardableResult
    public static func writeOut(_ name: String, _ data: Data) throws -> String {
        guard safeName(name) else { throw BadName() }
        try BundleStore.writeAtomically(outDir().appendingPathComponent(name), data)
        return Hex.sha256(data)
    }
}

/// Lab hooks are present in every G1 benchmark lab build (identical surface for A, B and C; see G1-CIC-1.0).
public enum BuildFlags {
    public static let lab = true
}
