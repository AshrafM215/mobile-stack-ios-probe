// G1 common native module (iOS) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
import Foundation
#if canImport(UIKit)
import UIKit
#endif

private final class G1BundleToken {}

/// Facade of the common native module on iOS (same surface as G1Native.java). Candidate A calls it from its Flutter plugin,
/// candidate B from its TurboModule (through G1NativeBridge), candidate C directly. Methods return plain values or JSON
/// strings so that the three runtime boundaries carry the same typed, bounded messages.
public enum G1Native {
    public static let embeddedBundle = "G1SYN-1.0.0"
    public static let trustStoreName = "trust_store"
    public static let duplicateRequest = "DUPLICATE_REQUEST"

    private static let lock = NSRecursiveLock()
    private static var initialized = false
    private static var trust: TrustStore!
    private static var bundles: BundleStore!
    private static var anchors: [String: QrValidator.Anchor]?
    private static var anchorsVersion: String?
    private static var readyReported = false
    private static var qrPending = Set<String>()
    private static var arListeners: [String: (String, String) -> Void] = [:]
    #if canImport(UIKit) && canImport(ARKit)
    private static var arScreens: [String: ArViewController] = [:]
    #endif

    // ---------------- resources and start ----------------

    static func resourceURL(_ name: String, _ ext: String) -> URL? {
        var candidates: [Bundle] = []
        #if SWIFT_PACKAGE
        candidates.append(Bundle.module)
        #endif
        let host = Bundle(for: G1BundleToken.self)
        for b in [host, Bundle.main] {
            if let u = b.url(forResource: "G1NativeCommonResources", withExtension: "bundle"), let rb = Bundle(url: u) { candidates.append(rb) }
        }
        candidates.append(host)
        candidates.append(Bundle.main)
        for b in candidates {
            if let u = b.url(forResource: name, withExtension: ext, subdirectory: "g1") ?? b.url(forResource: name, withExtension: ext) {
                return u
            }
        }
        return nil
    }

    static func processStartUptimeNanos() -> Int64 {
        #if canImport(Darwin)
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return -1 }
        let start = info.kp_proc.p_starttime
        var now = timeval()
        gettimeofday(&now, nil)
        let startNs = Int64(start.tv_sec) * 1_000_000_000 + Int64(start.tv_usec) * 1000
        let nowNs = Int64(now.tv_sec) * 1_000_000_000 + Int64(now.tv_usec) * 1000
        return Int64(G1Trace.nowNanos()) - (nowNs - startNs)
        #else
        return -1
        #endif
    }

    /// Idempotent; loads the compiled-in trust store and opens the private bundle store (Library/G1/g1bundle).
    public static func initialize(appId: String, storeRoot: URL? = nil) {
        lock.lock(); defer { lock.unlock() }
        if initialized { return }
        G1Trace.setApp(appId)
        guard let url = resourceURL(trustStoreName, "json"), let data = try? Data(contentsOf: url), let store = try? TrustStore.parse(data) else {
            fatalError("G1 trust store missing")
        }
        trust = store
        // Library/G1/g1bundle: app-private, excluded from backup, and free of spaces so that the map style can address
        // the verified bundle files with plain file:// URLs (Application Support contains a space).
        let root = storeRoot ?? FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("G1", isDirectory: true).appendingPathComponent("g1bundle", isDirectory: true)
        bundles = BundleStore(root: root, store: store, clock: { IsoTime.nowMs() })
        initialized = true
        G1Trace.mark("app.start", [("process_start_ns", String(processStartUptimeNanos()))])
    }

    public static func nowNanos() -> UInt64 { G1Trace.nowNanos() }

    /// kv: alternating keys and values (identifiers, codes and numbers only).
    public static func mark(_ name: String, runtimeNanos: Int64, kv: [String]) {
        var fields: [(String, String)] = []
        var i = 0
        while i + 1 < kv.count {
            fields.append((kv[i], kv[i + 1]))
            i += 2
        }
        G1Trace.mark(name, runtimeNanos: runtimeNanos, fields)
    }

    /// READY predicate reached (G1-CIC-1.0): the app.ready marker once per process.
    public static func reportReady(runtimeNanos: Int64) {
        lock.lock()
        let first = !readyReported
        readyReported = true
        lock.unlock()
        if first { G1Trace.mark("app.ready", runtimeNanos: runtimeNanos) }
    }

    public static func reportResumeReady(runtimeNanos: Int64) { G1Trace.mark("app.resume.ready", runtimeNanos: runtimeNanos) }

    // ---------------- bundle ----------------

    /// Installs the embedded bundle on first launch (through the full trust check) and returns the bundle info JSON.
    public static func ensureBundle() -> String {
        lock.lock(); defer { lock.unlock() }
        var info = bundles.load()
        if info.state == BundleStore.stateNone {
            if let url = resourceURL(embeddedBundle, "zip"), let zip = try? Data(contentsOf: url) {
                let code = bundles.importBundle(zip)
                G1Trace.mark("bundle.result", [("code", code), ("source", "embedded")])
            } else {
                G1Trace.mark("bundle.result", [("code", TrustCodes.rejectIO), ("source", "embedded")])
            }
            info = bundles.load()
        }
        G1Trace.mark("bundle.loaded", [("state", info.state), ("version", info.version ?? "-")])
        return infoJson(info)
    }

    public static func bundleInfo() -> String { infoJson(bundles.load()) }

    /// The verified active bundle directory (for the map style's g1bundle:// prefix), or nil.
    public static func bundleDirectory() -> URL? {
        let info = bundles.load()
        return info.usable ? info.dir : nil
    }

    static func infoJson(_ info: BundleStore.Info) -> String {
        Json.object([
            ("state", info.state),
            ("version", info.version),
            ("dir", info.usable ? info.dir?.path : nil),
            ("valid_from_ms", info.validFromMs),
            ("valid_until_ms", info.validUntilMs),
            ("time_trusted", info.timeTrusted),
            ("previous_version", info.previousVersion),
            ("detail", info.detail),
        ])
    }

    public static func importBundleBytes(_ zip: Data, source: String) -> String {
        lock.lock()
        let code = bundles.importBundle(zip)
        anchorsVersion = nil
        lock.unlock()
        G1Trace.mark("bundle.result", [("code", code), ("source", source)])
        return code
    }

    /// Lab hook bundle.import: a file the harness placed in the import directory.
    public static func importBundleFile(_ name: String) -> String {
        guard let data = try? G1Files.readImport(name) else {
            G1Trace.mark("bundle.result", [("code", TrustCodes.rejectIO), ("source", "import")])
            return TrustCodes.rejectIO
        }
        return importBundleBytes(data, source: "import")
    }

    public static func rollback() -> String {
        lock.lock()
        let code = bundles.rollbackToPrevious()
        anchorsVersion = nil
        lock.unlock()
        G1Trace.mark("bundle.result", [("code", code), ("source", "rollback")])
        return code
    }

    public struct NotAvailable: Error {}

    /// UTF-8 text of one file of the active, verified bundle (used by runtimes without direct file access).
    public static func readBundleFile(_ relPath: String) throws -> String {
        let info = bundles.load()
        guard info.usable, let dir = info.dir else { throw NotAvailable() }
        try StoredZip.checkName(relPath)
        return String(decoding: try BundleStore.readBytes(dir.appendingPathComponent(relPath)), as: UTF8.self)
    }

    // ---------------- QR ----------------

    private static func anchorsFor(_ info: BundleStore.Info) -> [String: QrValidator.Anchor]? {
        guard info.usable, let version = info.version, let dir = info.dir else { return nil }
        lock.lock(); defer { lock.unlock() }
        if anchorsVersion == version, let anchors { return anchors }
        guard let data = try? BundleStore.readBytes(dir.appendingPathComponent("qr_identities.json")),
              let parsed = try? QrValidator.parseAnchors(data) else { return nil }
        anchors = parsed
        anchorsVersion = version
        return parsed
    }

    public static func validateQr(_ payload: String?) -> String {
        let info = bundles.load()
        let now = IsoTime.nowMs()
        let o = QrValidator.validate(payload, store: trust, anchors: anchorsFor(info), activeVersion: info.usable ? info.version : nil,
                                     nowMs: now, timeTrusted: bundles.trustedClock.trusted(now))
        G1Trace.mark("qr.validated", [("outcome", o.code), ("anchor", o.anchor?.id ?? "-")])
        return o.toJson()
    }

    /// Lab hook qr.inject: decode a synthetic PNG through the common decoder (SIMULATED provenance).
    public static func decodeQrImport(_ name: String) -> String? {
        #if canImport(CoreImage) && canImport(ImageIO)
        guard let data = try? G1Files.readImport(name) else { return nil }
        return QrDecode.decodePng(data)
        #else
        return nil
        #endif
    }

    // ---------------- presentation helpers ----------------

    #if canImport(UIKit)
    /// The top-most presented view controller of the key window (presentation anchor for the native screens).
    public static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap { $0.windows }.first { $0.isKeyWindow } ?? scenes.first?.windows.first
        var top = window?.rootViewController
        while let next = top?.presentedViewController { top = next }
        return top
    }

    private static func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }
    #endif

    #if canImport(UIKit) && canImport(AVFoundation) && canImport(CoreImage)
    /// Opens the common camera scanner; callback(payload, error) exactly once. A request id already in flight is refused.
    public static func startQrScanner(from presenter: UIViewController?, requestId: String, callback: @escaping (String?, String?) -> Void) {
        lock.lock()
        let duplicate = qrPending.contains(requestId)
        if !duplicate { qrPending.insert(requestId) }
        lock.unlock()
        if duplicate { callback(nil, duplicateRequest); return }
        let deliver: (String?, String?) -> Void = { payload, error in
            lock.lock()
            qrPending.remove(requestId)
            lock.unlock()
            callback(payload, error)
        }
        onMain {
            guard let anchor = presenter ?? topViewController() else { deliver(nil, "CAMERA_UNAVAILABLE"); return }
            anchor.present(QrScannerViewController(requestId: requestId, completion: deliver), animated: false)
        }
    }
    #endif

    // ---------------- AR ----------------

    public static func arAvailability() -> String {
        #if canImport(UIKit) && canImport(ARKit)
        return ArSupport.availability()
        #else
        return "UNSUPPORTED"
        #endif
    }

    #if canImport(UIKit) && canImport(ARKit)
    /// Opens the common AR screen (scriptJson != nil: injected SIMULATED mode, lab builds only); listener(requestId, eventJson).
    public static func startAr(from presenter: UIViewController?, requestId: String, scriptJson: String?, textsJson: String?,
                               listener: @escaping (String, String) -> Void) {
        lock.lock()
        let duplicate = arListeners[requestId] != nil
        if !duplicate { arListeners[requestId] = listener }
        lock.unlock()
        if duplicate {
            listener(requestId, Json.object([("type", "error"), ("reason", duplicateRequest)]))
            return
        }
        onMain {
            let screen = ArViewController(requestId: requestId, scriptJson: scriptJson, textsJson: textsJson) { json in
                emitAr(requestId, json)
            }
            lock.lock()
            arScreens[requestId] = screen
            lock.unlock()
            guard let anchor = presenter ?? topViewController() else {
                emitAr(requestId, Json.object([("type", "closed"), ("reason", "unavailable")]))
                unregisterArScreen(requestId)
                return
            }
            anchor.present(screen, animated: false)
        }
    }

    /// Closes the common AR screen of a request from the runtime (navigation away or lab automation).
    public static func closeAr(requestId: String) {
        lock.lock()
        let screen = arScreens[requestId]
        lock.unlock()
        screen?.closeFromRuntime()
    }

    public static func setArGuidance(requestId: String, allowed: Bool) {
        lock.lock()
        let screen = arScreens[requestId]
        lock.unlock()
        screen?.setGuidance(allowed)
    }
    #endif

    static func unregisterArScreen(_ requestId: String) {
        #if canImport(UIKit) && canImport(ARKit)
        lock.lock()
        arScreens.removeValue(forKey: requestId)
        lock.unlock()
        #endif
    }

    static func emitAr(_ requestId: String, _ json: String) {
        lock.lock()
        let listener = arListeners[requestId]
        if json.contains("\"type\":\"closed\"") { arListeners.removeValue(forKey: requestId) }
        lock.unlock()
        listener?(requestId, json)
    }

    // ---------------- bridge workload ----------------

    public static func payloadBlock() -> Data { BridgeWorker.payloadBlock() }

    /// (length << 32 | crc, native entry nanos) on the caller's thread.
    public static func echoSync(_ payload: Data) -> (Int64, UInt64) { BridgeWorker.echoSync(payload) }

    /// callback(length << 32 | crc, native entry nanos) on the native worker.
    public static func echoAsync(_ payload: Data, _ callback: @escaping (Int64, UInt64) -> Void) { BridgeWorker.echoAsync(payload, callback) }

    public static func startN2R(size: Int, count: Int, rateHz: Int, onMessage: @escaping (Int, UInt64, Data) -> Void,
                                onDone: @escaping (Int, Int) -> Void) {
        BridgeWorker.startN2R(size: size, count: count, rateHz: rateHz, onMessage: onMessage, onDone: onDone)
    }

    // ---------------- session, crash, files ----------------

    public static func sessionStart(_ marker: String) -> Bool {
        #if canImport(Security) && canImport(CryptoKit)
        let ok = marker.utf16.count <= 256 && SecureSession.start(marker)
        #else
        let ok = false
        #endif
        G1Trace.mark("session.state", [("state", ok ? "active" : "error")])
        return ok
    }

    public static func sessionActive() -> Bool {
        #if canImport(Security) && canImport(CryptoKit)
        let a = SecureSession.active()
        #else
        let a = false
        #endif
        G1Trace.mark("session.state", [("state", a ? "active" : "inactive")])
        return a
    }

    public static func sessionEnd() {
        #if canImport(Security) && canImport(CryptoKit)
        SecureSession.end()
        #endif
        G1Trace.mark("session.state", [("state", "inactive")])
    }

    public static func crash(_ caseId: String) {
        if caseId == "CR3" { CrashHooks.nativeCrash() } else if caseId == "CR4" { CrashHooks.hangMainThread() }
    }

    @discardableResult
    public static func writeOut(_ name: String, _ text: String) throws -> String { try G1Files.writeOut(name, Data(text.utf8)) }

    /// PEM of the synthetic lab CA (the only trust anchor of the lab update endpoint), for runtimes with their own TLS stack.
    public static func labCa() -> String? {
        guard let url = resourceURL("g1_lab_ca", "pem"), let data = try? Data(contentsOf: url) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    public static func readImportText(_ name: String) throws -> String { String(decoding: try G1Files.readImport(name), as: UTF8.self) }

    public static func readImportBytes(_ name: String) throws -> Data { try G1Files.readImport(name) }
}
