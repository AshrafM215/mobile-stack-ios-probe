// Candidate C (native iOS) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// Application state and the handlers shared by the UI and the lab hooks (the lab hooks call the same handlers).
// Everything runs on the main thread; SwiftUI observes the published state.
import Foundation
import G1NativeCommon
import QuartzCore
import Security
import SwiftUI

enum ScreenKind { case home, details, route, fallback, qr, settings }

struct ScreenEntry: Equatable {
    let kind: ScreenKind
    var destination: String? = nil
}

let labUpdateOrigin = "https://localhost:8443/"
let defaultUpdateUrl = "https://localhost:8443/update/G1SYN-update.zip"

func lonOf(_ xMm: Int64) -> Double { Double(xMm) * 100 / 11_131_949_079 }
func latOf(_ yMm: Int64) -> Double { Double(yMm) * 10 / 1_105_742_727 }

/// Imperative commands to the map binding (MapLibre Native iOS is driven through its own API).
protocol MapPort: AnyObject {
    func setFloor(_ floor: Int)
    func setLanguage(_ lang: String)
    func setRoute(_ featureCollection: String)
    func easeTo(lon: Double, lat: Double, zoom: Double, durationMs: Int)
    func reload()
}

/// One-shot CADisplayLink: runs the block (with nowNanos read first) at the next display frame.
final class NextFrame: NSObject {
    private var link: CADisplayLink?
    private var block: ((UInt64) -> Void)?
    private static var live = Set<NextFrame>()

    static func run(_ block: @escaping (UInt64) -> Void) {
        let f = NextFrame()
        f.block = block
        live.insert(f)
        f.link = CADisplayLink(target: f, selector: #selector(tick))
        f.link?.add(to: .main, forMode: .common)
    }

    @objc private func tick() {
        let t = G1Native.nowNanos()
        link?.invalidate()
        link = nil
        let b = block
        block = nil
        NextFrame.live.remove(self)
        b?(t)
    }
}

final class AppState: ObservableObject {
    private let strings: [String: Strings]
    weak var map: MapPort?

    @Published private(set) var lang = "ar"
    var s: Strings { strings[lang]! }
    func stringsFor(_ l: String) -> Strings { strings[l]! }

    @Published private(set) var bundleInfo: BundleInfo?
    @Published private(set) var data: BundleData?
    @Published private(set) var index: SearchIndex?
    private(set) var graph: RouteGraph?
    private(set) var nodes: [String: GraphNode] = [:]
    private(set) var arAvailability = "UNKNOWN"

    @Published private(set) var stack: [ScreenEntry] = [ScreenEntry(kind: .home)]
    var top: ScreenEntry { stack.last! }
    @Published private(set) var floor = 1
    @Published var query = ""
    @Published private(set) var results: SearchResult?

    @Published private(set) var origin = "N0001"
    @Published var stepFree = false
    private var blocked: [String] = []
    @Published private(set) var route: RouteResult?
    @Published private(set) var steps: [RouteStep] = []
    @Published private(set) var summary: RouteSummary?
    private(set) var routeFc = emptyFeatures

    @Published private(set) var qrResult: [String: Any]?
    @Published private(set) var lastResult: String?
    @Published private(set) var updateStatus: String?
    @Published private(set) var updatePercent = 0

    private(set) var styleLoaded = false
    private var homeShownFlag = false
    private(set) var ready = false
    private var arCounter = 0
    private(set) var activeAr: String?
    private(set) var ignoredArEvents = 0
    var payloadBlock: Data?

    var trusted: Bool { bundleInfo?.state == "VALID" && data != nil }

    init(strings: [String: Strings]) {
        self.strings = strings
    }

    private func mark(_ name: String, _ kv: [String] = []) {
        G1Native.mark(name, runtimeNanos: Int64(G1Native.nowNanos()), kv: kv)
    }

    // ---------------- frame waiters (bench e2e: the first frame after the SwiftUI update that applied the state) ----------------

    @Published private(set) var revision = 0
    private var commitWaiters: [(UInt64) -> Void] = []

    /// Called from the root view's CommitProbe during the SwiftUI update that renders `revision`.
    func onCommit() {
        if commitWaiters.isEmpty { return }
        let waiters = commitWaiters
        commitWaiters = []
        NextFrame.run { t in waiters.forEach { $0(t) } }
    }

    /// Idle point (G1-CIC-1.0): a timed handler never starts inside a frame callback (a block queued on the main queue).
    @MainActor
    func idle() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in DispatchQueue.main.async { c.resume() } }
    }

    /// Resolves with nowNanos() at the first CADisplayLink frame after the SwiftUI update that applied the current state.
    @MainActor
    func nextFrame() async -> UInt64 {
        await withCheckedContinuation { (c: CheckedContinuation<UInt64, Never>) in
            commitWaiters.append { t in c.resume(returning: t) }
            revision += 1
        }
    }

    // ---------------- start ----------------

    /// Immutable once built off the main thread, then handed to the main thread (hence @unchecked Sendable).
    private struct Loaded: @unchecked Sendable {
        let data: BundleData
        let graph: RouteGraph
        let nodes: [String: GraphNode]
        let index: SearchIndex
    }

    /// Parses the active bundle and builds the search index and graph (any thread; no state is touched).
    private static func load(_ info: BundleInfo) -> Loaded? {
        guard info.state == "VALID", let dir = info.dir, let version = info.version else { return nil }
        do {
            let d = try BundleData.load(version: version, dir: dir) { try G1Native.readBundleFile($0) }
            return Loaded(data: d, graph: RouteGraph(d.graph), nodes: Dictionary(d.graph.nodes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }),
                          index: SearchIndex(d.destinations))
        } catch {
            G1Native.mark("bundle.loaded", runtimeNanos: Int64(G1Native.nowNanos()), kv: ["state", "PARSE_ERROR"])
            return nil
        }
    }

    private func apply(_ info: BundleInfo, _ loaded: Loaded?) {
        bundleInfo = info
        graph = loaded?.graph
        nodes = loaded?.nodes ?? [:]
        index = loaded?.index
        if let d = loaded?.data, !d.entrances.contains(origin), let first = d.entrances.first { origin = first }
        data = loaded?.data
    }

    private static func infoAndData(_ json: String) -> (BundleInfo, Loaded?) {
        let info = (try? BundleInfo.parse(json)) ?? BundleInfo(state: "NONE", version: nil, dir: nil, validFromMs: 0, validUntilMs: 0,
                                                                timeTrusted: false, previousVersion: nil, detail: nil)
        return (info, load(info))
    }

    /// Embedded bundle install/verification and parsing off the main thread; the state is applied on the main thread.
    @MainActor
    func boot() async {
        let (info, loaded) = await Task.detached { AppState.infoAndData(G1Native.ensureBundle()) }.value
        apply(info, loaded)
        arAvailability = G1Native.arAvailability()
        map?.reload()
    }

    func homeShown() {
        if homeShownFlag { return }
        homeShownFlag = true
        checkReady()
    }

    func onStyleLoaded() {
        styleLoaded = true
        mark("map.style.loaded", ["floor", String(floor)])
        checkReady()
    }

    private func checkReady() {
        if ready || !homeShownFlag || !styleLoaded || !trusted || index == nil { return }
        ready = true
        let rt = Int64(G1Native.nowNanos())
        NextFrame.run { _ in G1Native.reportReady(runtimeNanos: rt) }
    }

    func onResumed() {
        let rt = Int64(G1Native.nowNanos())
        NextFrame.run { _ in G1Native.reportResumeReady(runtimeNanos: rt) }
    }

    // ---------------- navigation ----------------

    private func push(_ e: ScreenEntry, _ screenId: String) {
        stack.append(e)
        mark("screen.shown", ["screen", screenId])
    }

    func back() {
        if stack.count > 1 { stack.removeLast() }
        if top.kind == .home { mark("screen.shown", ["screen", "S01"]) }
    }

    func goHome() {
        stack = [ScreenEntry(kind: .home)]
        mark("screen.shown", ["screen", "S01"])
    }

    func setLang(_ l: String) {
        if (l != "ar" && l != "en") || l == lang { return }
        lang = l
        map?.setLanguage(l)
        mark("lang.changed", ["lang", l])
    }

    func toggleLang() { setLang(lang == "ar" ? "en" : "ar") }

    func setFloor(_ f: Int) {
        if f < 1 || f > 3 || f == floor { return }
        floor = f
        map?.setFloor(f)
        mark("floor.changed", ["floor", String(f)])
    }

    // ---------------- search ----------------

    /// Submit handler of home.search.submit; returns the compute-only duration (ns).
    @discardableResult
    func submitSearch() -> Int64 {
        guard let idx = index, trusted else {
            results = SearchResult(outcome: "NO_MATCH", ids: [])
            return 0
        }
        let t0 = G1Native.nowNanos()
        let r = idx.search(query)
        let compute = Int64(G1Native.nowNanos() - t0)
        results = r
        mark("search.result", ["outcome", r.outcome, "count", String(r.ids.count)])
        return compute
    }

    func clearSearch() {
        query = ""
        results = nil
    }

    // ---------------- destination and route ----------------

    func openDetails(_ id: String) {
        guard data?.byId[id] != nil else { return }
        push(ScreenEntry(kind: .details, destination: id), "S04")
    }

    func showOnMap(_ id: String) {
        let d = data?.byId[id]
        let n = d.flatMap { nodes[$0.node] }
        goHome()
        guard let d, let n else { return }
        setFloor(d.floor)
        map?.easeTo(lon: lonOf(n.xMm), lat: latOf(n.yMm), zoom: 19, durationMs: 600)
    }

    func openRoute(_ destinationId: String, origin fromOrigin: String? = nil, stepFree stepFreeOnly: Bool? = nil, blocked blockedEdges: [String] = []) {
        if let fromOrigin { origin = fromOrigin }
        if let stepFreeOnly { stepFree = stepFreeOnly }
        blocked = blockedEdges
        route = nil
        steps = []
        summary = nil
        routeFc = emptyFeatures
        map?.setRoute(routeFc)
        push(ScreenEntry(kind: .route, destination: destinationId), "S07")
    }

    func setOrigin(_ id: String) { origin = id }

    var routeDestination: String? { top.kind == .route ? top.destination : nil }

    /// Handler of route.compute; returns the compute-only duration (ns).
    @discardableResult
    func computeRoute() -> Int64 {
        let d = routeDestination.flatMap { data?.byId[$0] }
        guard trusted, let g = graph else {
            route = RouteResult(outcome: "REJECT_UNTRUSTED", nodes: [], lengthMm: 0)
            steps = []
            summary = nil
            mark("route.result", ["outcome", "REJECT_UNTRUSTED"])
            return 0
        }
        let t0 = G1Native.nowNanos()
        var st: [RouteStep] = []
        var sum: RouteSummary?
        let r = d.map { g.route(origin, $0.node, stepFree: stepFree, blocked: blocked) } ?? RouteResult(outcome: "REJECT_UNKNOWN", nodes: [], lengthMm: 0)
        if r.outcome == "PATH", let d, let out = try? routeSteps(g, nodes, r.nodes, d) {
            st = out.0
            sum = out.1
        }
        let compute = Int64(G1Native.nowNanos() - t0)
        route = r
        steps = st
        summary = sum
        routeFc = r.outcome == "PATH" && data != nil ? routeFeatures(data!, g, r.nodes) : emptyFeatures
        map?.setRoute(routeFc)
        mark("route.result", ["outcome", r.outcome, "steps", String(st.count)])
        return compute
    }

    var guidanceAllowed: Bool { trusted && route?.outcome == "PATH" }

    private func arTexts() -> String {
        let t = s
        return JSON.encode(JSON.Object([("arrow", t.t("ar.arrow")), ("close", t.t("ar.close")), ("tracking", t.t("ar.tracking.ok")),
                                        ("no_pose", t.t("ar.no_pose")), ("limited", t.t("ar.tracking.limited")), ("lost", t.t("ar.tracking.lost")),
                                        ("paused", t.t("ar.paused")), ("initializing", t.t("ar.initializing"))]))
    }

    /// Handler of route.ar: the native AR screen when supported (or injected in lab), otherwise the text fallback.
    func openAr(script: String? = nil) {
        if script == nil && arAvailability != "SUPPORTED" {
            push(ScreenEntry(kind: .fallback), "S09")
            mark("fallback.shown", ["reason", arAvailability])
            return
        }
        arCounter += 1
        let id = "ar-\(arCounter)"
        activeAr = id
        G1Native.startAr(from: nil, requestId: id, scriptJson: script, textsJson: arTexts()) { [weak self] requestId, json in
            DispatchQueue.main.async { self?.onArEvent(requestId, json) }
        }
        if guidanceAllowed { G1Native.setArGuidance(requestId: id, allowed: true) }
    }

    func onArEvent(_ requestId: String, _ json: String) {
        if requestId != activeAr {
            ignoredArEvents += 1 // late events for a request whose receiving screen is gone are ignored (BRG06)
            return
        }
        if ((try? JSON.decode(json)) as? [String: Any])?["type"] as? String == "closed" { activeAr = nil }
    }

    func dropAr() { activeAr = nil }

    // ---------------- QR ----------------

    func scanQr() {
        G1Native.startQrScanner(from: nil, requestId: "qr-\(G1Native.nowNanos())") { [weak self] payload, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let payload { self.showQr(qrOutcome(G1Native.validateQr(payload))) } else { self.showQr(["outcome": error ?? "CANCELLED"]) }
            }
        }
    }

    func injectQr(_ file: String) {
        if let payload = G1Native.decodeQrImport(file) { showQr(qrOutcome(G1Native.validateQr(payload))) } else { showQr(["outcome": "NO_CODE"]) }
    }

    private func showQr(_ outcome: [String: Any]) {
        qrResult = outcome
        mark("qr.result", ["outcome", (outcome["outcome"] as? String) ?? "-"])
        if top.kind != .qr { push(ScreenEntry(kind: .qr), "QR") }
    }

    // ---------------- data and trust ----------------

    func openSettings() {
        if top.kind != .settings { push(ScreenEntry(kind: .settings), "SETTINGS") }
    }

    @MainActor
    private func afterBundleChange(_ code: String) async {
        lastResult = code
        let before = data?.version
        let (info, loaded) = await Task.detached { AppState.infoAndData(G1Native.bundleInfo()) }.value
        apply(info, loaded)
        if data?.version != before {
            results = nil
            route = nil
            steps = []
            summary = nil
            routeFc = emptyFeatures
            styleLoaded = false
            map?.reload()
        }
        openSettings()
    }

    @MainActor
    func importBundleFile(_ name: String) async -> String {
        let code = await Task.detached { G1Native.importBundleFile(name) }.value
        await afterBundleChange(code)
        return code
    }

    @MainActor
    func rollback() async -> String {
        let code = await Task.detached { G1Native.rollback() }.value
        await afterBundleChange(code)
        return code
    }

    /// Lab update with the platform's standard HTTP client (URLSession; the lab CA is trusted for localhost only).
    @MainActor
    func update(_ url: String = defaultUpdateUrl) async -> String {
        openSettings()
        guard url.hasPrefix(labUpdateOrigin), let u = URL(string: url) else {
            updateStatus = "failed"
            return "REJECT_URL"
        }
        updateStatus = "pending"
        updatePercent = 0
        mark("update.state", ["state", "pending"])
        let slow = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            if !Task.isCancelled, updateStatus == "pending" {
                updateStatus = "slow"
                mark("update.state", ["state", "slow"])
            }
        }
        defer { slow.cancel() }
        do {
            let (bytes, response) = try await LabTls.session.data(from: u)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 404 {
                updateStatus = "none"
                mark("update.state", ["state", "none"])
                return "NONE"
            }
            guard status == 200, bytes.count <= 64 * 1024 * 1024 else { throw FormatError("status") }
            updatePercent = 100
            updateStatus = "done"
            mark("update.state", ["state", "downloaded"])
            let code = await Task.detached { G1Native.importBundleBytes(bytes, source: "update") }.value
            await afterBundleChange(code)
            return code
        } catch {
            updateStatus = "failed"
            mark("update.state", ["state", "failed"])
            return "FAILED"
        }
    }

    func ensurePayloadBlock() -> Data {
        if let b = payloadBlock { return b }
        let b = G1Native.payloadBlock()
        payloadBlock = b
        return b
    }
}

/// URLSession whose only trust anchor for the lab endpoint (localhost) is the synthetic lab CA of the common module.
enum LabTls {
    static let session: URLSession = URLSession(configuration: .ephemeral, delegate: Delegate(), delegateQueue: nil)

    final class Delegate: NSObject, URLSessionDelegate {
        private lazy var anchor: SecCertificate? = {
            guard let pem = G1Native.labCa() else { return nil }
            let body = pem.split(separator: "\n").filter { !$0.hasPrefix("-----") }.joined()
            guard let der = Data(base64Encoded: body) else { return nil }
            return SecCertificateCreateWithData(nil, der as CFData)
        }()

        func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
                  challenge.protectionSpace.host == "localhost", let trust = challenge.protectionSpace.serverTrust, let anchor else {
                completionHandler(.performDefaultHandling, nil)
                return
            }
            SecTrustSetAnchorCertificates(trust, [anchor] as CFArray)
            SecTrustSetAnchorCertificatesOnly(trust, true)
            var error: CFError?
            if SecTrustEvaluateWithError(trust, &error) {
                completionHandler(.useCredential, URLCredential(trust: trust))
            } else {
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
        }
    }
}
