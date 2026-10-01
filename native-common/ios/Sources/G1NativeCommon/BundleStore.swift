// G1 common native module (iOS) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Persistent bundle state of G1-TRUST-1.0 under one private directory (same layout and rules as BundleStore.java):
///   active.json            {"active": {dir, version, manifest_sha256}, "previous": {...} | null}  (replaced atomically)
///   v-<version>-<n>/       one directory per activated bundle (files written and synced before the pointer moves)
///   staging-<n>/           in-progress activation; removed at the next start (an interrupted activation leaves no state)
///   time.json              trusted-time high-water mark
/// The active bundle is fully re-verified (signature, hashes, validity, trusted time) on every load; a tampered active
/// directory falls back to the previous bundle when that one verifies, otherwise the state is reported as INVALID.
public final class BundleStore {
    public static let stateValid = "VALID"
    public static let stateNone = "NONE"
    public static let stateExpired = "EXPIRED"
    public static let stateNotYetValid = "NOT_YET_VALID"
    public static let stateTimeUntrusted = "TIME_UNTRUSTED"
    public static let stateInvalid = "INVALID"

    public struct Info {
        public let state: String
        public let version: String?
        public let dir: URL?
        public let validFromMs: Int64
        public let validUntilMs: Int64
        public let timeTrusted: Bool
        public let previousVersion: String?
        public let detail: String?

        public var usable: Bool { state == BundleStore.stateValid }
    }

    public struct IOFailure: Error { public let reason: String }

    private let root: URL
    private let store: TrustStore
    private let clock: () -> Int64
    public private(set) var trustedClock: TrustedClock!
    private var counter: Int64
    private let lock = NSLock()

    public init(root: URL, store: TrustStore, clock: @escaping () -> Int64) {
        self.root = root
        self.store = store
        self.clock = clock
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        BundleStore.excludeFromBackup(root)
        let timeFile = root.appendingPathComponent("time.json")
        self.counter = clock()
        self.trustedClock = TrustedClock(read: {
            guard let data = try? BundleStore.readBytes(timeFile), let o = try? Json.parseObject(data),
                  let n = Json.number(o["high_water_ms"]) else { return 0 }
            return n.int64Value
        }, write: { value in
            // The mark only ever tightens; a failed write keeps the previous, older mark.
            try? BundleStore.writeAtomically(timeFile, Data("{\"high_water_ms\":\(value)}\n".utf8))
        })
        cleanupStaging()
    }

    static func excludeFromBackup(_ url: URL) {
        #if os(iOS) || os(macOS)
        var u = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? u.setResourceValues(values)
        #endif
    }

    private func names() -> [String] { (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? [] }

    private static func isDirectory(_ url: URL) -> Bool {
        var dir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &dir) && dir.boolValue
    }

    private func cleanupStaging() {
        for n in names() where n.hasPrefix("staging-") && BundleStore.isDirectory(root.appendingPathComponent(n)) {
            try? FileManager.default.removeItem(at: root.appendingPathComponent(n))
        }
    }

    /// Offer a container (bytes). Returns the exact G1-TRUST-1.0 code; activates atomically on success.
    public func importBundle(_ zip: Data) -> String {
        lock.lock(); defer { lock.unlock() }
        let now = clock()
        let p = readPointer()
        let r = BundleVerifier.verifyZip(zip, store: store, nowMs: now, timeTrusted: trustedClock.trusted(now), activeVersion: p.activeVersion)
        if !r.ok { return r.code }
        do {
            try activate(r, p)
        } catch {
            return TrustCodes.rejectIO
        }
        trustedClock.observe(now)
        return TrustCodes.activated
    }

    /// Explicit rollback to the retained previous bundle, re-verified now (OFF09/OFF10).
    public func rollbackToPrevious() -> String {
        lock.lock(); defer { lock.unlock() }
        let now = clock()
        let p = readPointer()
        guard let previousDir = p.previousDir else { return TrustCodes.rejectNoPrevious }
        let files: [String: Data]
        do {
            files = try BundleStore.readDir(root.appendingPathComponent(previousDir))
        } catch {
            return TrustCodes.rejectIO
        }
        let r = BundleVerifier.verifyEntries(files, store: store, nowMs: now, timeTrusted: trustedClock.trusted(now), activeVersion: nil, applyVersionPolicy: false)
        if !r.ok { return r.code }
        do {
            try writePointer(activeDir: previousDir, version: r.version!, sha: r.manifestSha256, prevDir: p.activeDir, prevVersion: p.activeVersion, prevSha: p.activeSha)
        } catch {
            return TrustCodes.rejectIO
        }
        trustedClock.observe(now)
        return TrustCodes.rollbackActivated
    }

    /// Load and re-verify the active bundle; falls back to the previous one if the active one no longer verifies.
    public func load() -> Info {
        lock.lock(); defer { lock.unlock() }
        let now = clock()
        let timeTrusted = trustedClock.trusted(now)
        let p = readPointer()
        guard let activeDir = p.activeDir else {
            return Info(state: BundleStore.stateNone, version: nil, dir: nil, validFromMs: 0, validUntilMs: 0, timeTrusted: timeTrusted, previousVersion: nil, detail: "no active bundle")
        }
        let active = check(activeDir, now: now, timeTrusted: timeTrusted, previousVersion: p.previousVersion)
        if active.usable || active.state == BundleStore.stateTimeUntrusted || active.state == BundleStore.stateExpired
            || active.state == BundleStore.stateNotYetValid || p.previousDir == nil {
            if active.usable { trustedClock.observe(now) }
            return active
        }
        let previous = check(p.previousDir!, now: now, timeTrusted: timeTrusted, previousVersion: nil)
        if previous.usable {
            // keep serving the verified previous bundle for this process even if the pointer cannot be rewritten
            try? writePointer(activeDir: p.previousDir!, version: previous.version!, sha: nil, prevDir: nil, prevVersion: nil, prevSha: nil)
            return previous
        }
        return active
    }

    private func check(_ dirName: String, now: Int64, timeTrusted: Bool, previousVersion: String?) -> Info {
        let dir = root.appendingPathComponent(dirName)
        let files: [String: Data]
        do {
            files = try BundleStore.readDir(dir)
        } catch {
            return Info(state: BundleStore.stateInvalid, version: nil, dir: dir, validFromMs: 0, validUntilMs: 0, timeTrusted: timeTrusted, previousVersion: previousVersion, detail: TrustCodes.rejectIO)
        }
        let r = BundleVerifier.verifyEntries(files, store: store, nowMs: now, timeTrusted: timeTrusted, activeVersion: nil, applyVersionPolicy: false)
        if r.ok {
            return Info(state: BundleStore.stateValid, version: r.version, dir: dir, validFromMs: r.validFromMs, validUntilMs: r.validUntilMs, timeTrusted: true, previousVersion: previousVersion, detail: TrustCodes.activated)
        }
        let state: String
        switch r.code {
        case TrustCodes.rejectUntrustedTime: state = BundleStore.stateTimeUntrusted
        case TrustCodes.rejectExpired: state = BundleStore.stateExpired
        case TrustCodes.rejectNotYetValid: state = BundleStore.stateNotYetValid
        default: state = BundleStore.stateInvalid
        }
        return Info(state: state, version: nil, dir: dir, validFromMs: 0, validUntilMs: 0, timeTrusted: timeTrusted, previousVersion: previousVersion, detail: r.code)
    }

    private func activate(_ r: BundleVerifier.Result, _ p: Pointer) throws {
        counter += 1
        let n = counter
        let staging = root.appendingPathComponent("staging-\(n)")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        for (name, data) in r.files!.sorted(by: { $0.key < $1.key }) {
            let f = staging.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: f.deletingLastPathComponent(), withIntermediateDirectories: true)
            try BundleStore.writeSynced(f, data)
        }
        let targetName = "v-\(r.version!)-\(n)"
        let target = root.appendingPathComponent(targetName)
        if rename(staging.path, target.path) != 0 { throw IOFailure(reason: "rename") }
        try writePointer(activeDir: targetName, version: r.version!, sha: r.manifestSha256, prevDir: p.activeDir, prevVersion: p.activeVersion, prevSha: p.activeSha)
        // retain only the active and the previous directories
        for name in names() where name.hasPrefix("v-") && name != targetName && name != p.activeDir {
            let u = root.appendingPathComponent(name)
            if BundleStore.isDirectory(u) { try? FileManager.default.removeItem(at: u) }
        }
    }

    private struct Pointer {
        var activeDir: String?
        var activeVersion: String?
        var activeSha: String?
        var previousDir: String?
        var previousVersion: String?
    }

    private func readPointer() -> Pointer {
        guard let data = try? BundleStore.readBytes(root.appendingPathComponent("active.json")),
              let o = try? Json.parseObject(data) else { return Pointer() }
        var p = Pointer()
        if let a = o["active"] as? [String: Any] {
            guard let dir = BundleStore.safeDirName(Json.string(a["dir"])), let version = Json.string(a["version"]) else { return Pointer() }
            p.activeDir = dir
            p.activeVersion = version
            p.activeSha = Json.string(a["manifest_sha256"])
        }
        if let b = o["previous"] as? [String: Any] {
            guard let dir = BundleStore.safeDirName(Json.string(b["dir"])), let version = Json.string(b["version"]) else { return Pointer() }
            p.previousDir = dir
            p.previousVersion = version
        }
        return p
    }

    private static func safeDirName(_ name: String?) -> String? {
        guard let name, name.hasPrefix("v-"), !name.contains("/"), !name.contains("\\"), !name.contains("..") else { return nil }
        return name
    }

    private func writePointer(activeDir: String, version: String, sha: String?, prevDir: String?, prevVersion: String?, prevSha: String?) throws {
        let active = Json.object([("dir", activeDir), ("version", version), ("manifest_sha256", sha)])
        let previous: Any? = prevDir == nil ? nil : Json.Raw(Json.object([("dir", prevDir), ("version", prevVersion), ("manifest_sha256", prevSha)]))
        let text = Json.object([("active", Json.Raw(active)), ("previous", previous)]) + "\n"
        try BundleStore.writeAtomically(root.appendingPathComponent("active.json"), Data(text.utf8))
    }

    // ---------------- file helpers (POSIX, synced) ----------------

    public static func readDir(_ dir: URL) throws -> [String: Data] {
        guard isDirectory(dir) else { throw IOFailure(reason: "missing bundle directory") }
        var out: [String: Data] = [:]
        try walk(dir, "", &out)
        return out
    }

    private static func walk(_ dir: URL, _ prefix: String, _ out: inout [String: Data]) throws {
        guard let list = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { throw IOFailure(reason: "list") }
        for name in list.sorted() {
            let f = dir.appendingPathComponent(name)
            let rel = prefix.isEmpty ? name : prefix + "/" + name
            if isDirectory(f) {
                try walk(f, rel, &out)
            } else {
                let attrs = try? FileManager.default.attributesOfItem(atPath: f.path)
                let size = (attrs?[.size] as? NSNumber)?.intValue ?? 0
                if out.count >= StoredZip.maxEntries || size > StoredZip.maxEntryBytes { throw IOFailure(reason: "limits") }
                out[rel] = try readBytes(f)
            }
        }
    }

    public static func readBytes(_ url: URL) throws -> Data {
        let data = try Data(contentsOf: url)
        if data.count > StoredZip.maxTotalBytes + 1024 * 1024 { throw IOFailure(reason: "too large") }
        return data
    }

    public static func writeSynced(_ url: URL, _ data: Data) throws {
        let fd = open(url.path, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        if fd < 0 { throw IOFailure(reason: "open") }
        defer { close(fd) }
        try data.withUnsafeBytes { (b: UnsafeRawBufferPointer) in
            var off = 0
            while off < b.count {
                let n = write(fd, b.baseAddress!.advanced(by: off), b.count - off)
                if n <= 0 { throw IOFailure(reason: "write") }
                off += n
            }
        }
        if fsync(fd) != 0 { throw IOFailure(reason: "fsync") }
    }

    public static func writeAtomically(_ target: URL, _ data: Data) throws {
        let tmp = target.deletingLastPathComponent().appendingPathComponent(target.lastPathComponent + ".tmp")
        try writeSynced(tmp, data)
        if rename(tmp.path, target.path) != 0 { throw IOFailure(reason: "rename \(target.lastPathComponent)") }
    }
}
