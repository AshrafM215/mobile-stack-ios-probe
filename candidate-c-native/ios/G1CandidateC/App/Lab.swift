// Candidate C (native iOS) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// Lab hooks of G1-CIC-1.0 (present in every benchmark lab build). Commands arrive from the common module (launch
// arguments or the g1bench-c:// URL) and drive the same handlers as the UI. Candidate C has no runtime boundary: the app
// calls the common module directly (Swift -> Swift), including the hop to the native worker and back to the main thread.
import Foundation
import G1NativeCommon
import QuartzCore

private let twoTo32: Int64 = 4_294_967_296
private let sizes = ["64B": 64, "4KiB": 4096, "64KiB": 65536]
private func offsetOf(_ seq: Int, _ size: Int) -> Int { (seq * 64) % (65536 - size + 1) }

/// Mutable cell shared with callbacks that hop back to the main thread (no captured `var` in escaping closures).
private final class Box<T> {
    var value: T
    init(_ value: T) { self.value = value }
}

private func sleepNs(_ ns: Int64) async {
    if ns > 0 { try? await Task.sleep(nanoseconds: UInt64(ns)) }
}

final class LabController {
    private let state: AppState
    private var queue: [(String, String)] = []
    private var busy = false
    private(set) var canary: String?
    private var echoBuffer = [UInt8](repeating: 0, count: 64 * 1024)

    init(state: AppState) {
        self.state = state
    }

    private func now() -> Int64 { Int64(G1Native.nowNanos()) }

    private func mark(_ name: String, _ kv: [String] = []) { G1Native.mark(name, runtimeNanos: now(), kv: kv) }

    /// Waits for READY (or an untrusted bundle) before the launch command, as the other candidates do.
    @MainActor
    func start(_ launch: LabCommand?) async {
        let deadline = now() + 60_000_000_000
        while !state.ready && now() < deadline && (state.bundleInfo == nil || state.trusted) { await sleepNs(50_000_000) }
        if let launch { enqueue(launch.name, launch.argsJson) }
    }

    func enqueue(_ name: String, _ args: String) {
        queue.append((name, args))
        if !busy { Task { @MainActor in await self.drain() } }
    }

    @MainActor
    private func drain() async {
        busy = true
        while !queue.isEmpty {
            let (name, argsText) = queue.removeFirst()
            guard let args = (try? JSON.decode(argsText)) as? [String: Any],
                  decodeEnvelope(JSON.encode(JSON.Object([("method", name), ("args", args)]))) == "ACCEPT" else {
                mark("command.rejected", ["reason", "runtime_envelope"])
                continue
            }
            do {
                try await exec(name, args)
            } catch {
                mark("command.failed", ["cmd", name, "error", String(describing: type(of: error))])
            }
        }
        busy = false
    }

    private func str(_ a: [String: Any], _ k: String) throws -> String {
        guard let v = a[k] as? String else { throw FormatError("arg \(k)") }
        return v
    }

    private func int(_ a: [String: Any], _ k: String, _ fallback: Int) -> Int { JSON.integer(a[k]).map { Int($0) } ?? fallback }

    @MainActor
    private func exec(_ name: String, _ a: [String: Any]) async throws {
        let s = state
        switch name {
        case "nav.home": s.goHome()
        case "nav.details":
            s.goHome()
            s.openDetails(try str(a, "destination"))
        case "nav.route": try await openCaseRoute(a)
        case "nav.open-route-ar":
            try await openCaseRoute(a)
            s.openAr()
        case "ar.inject":
            try await openCaseRoute(a)
            s.openAr(script: JSON.encode(a["script"]))
        case "lang.set": s.setLang(try str(a, "lang"))
        case "bundle.import": _ = await s.importBundleFile(try str(a, "file"))
        case "bundle.rollback": _ = await s.rollback()
        case "bundle.update": _ = await s.update(try str(a, "url"))
        case "qr.inject": s.injectQr(try str(a, "file"))
        case "session.start": _ = G1Native.sessionStart(try str(a, "marker"))
        case "session.end": G1Native.sessionEnd()
        case "session.status": _ = G1Native.sessionActive()
        case "crash": try await crash(try str(a, "case"), a["canary"] as? String)
        case "bench.search-route": try await benchSearchRoute(try str(a, "run_id"), try str(a, "kind"))
        case "bench.bridge":
            try await benchBridge(try str(a, "run_id"), try str(a, "workload"), (a["order"] as? String) ?? "control-first",
                                  int(a, "messages", 1000), int(a, "rate_hz", 200))
        case "bench.ui-session": try await window(try str(a, "session_id"), int(a, "warmup_s", 60), int(a, "measure_s", 300), script: true)
        case "bench.idle": try await window(try str(a, "session_id"), int(a, "warmup_s", 60), int(a, "measure_s", 300), script: false)
        case "fuzz": try await fuzz(try str(a, "run_id"), try str(a, "target"), try str(a, "corpus"))
        case "bridge.attack": try await attack(try str(a, "run_id"), try str(a, "case"))
        default: break
        }
    }

    private func routeCase(_ id: Any?) -> RouteCase? {
        guard let cid = id as? String else { return nil }
        return state.data?.routeCases.first { $0.id == cid }
    }

    @MainActor
    private func openCaseRoute(_ a: [String: Any]) async throws {
        let s = state
        let c = routeCase(a["case"])
        s.goHome()
        if let c {
            s.openRoute(c.destination, origin: c.origin, stepFree: c.stepFree, blocked: c.blocked)
        } else {
            s.openRoute(try str(a, "destination"), origin: a["origin"] as? String, stepFree: JSON.bool(a["step_free"]) ?? false, blocked: [])
        }
        _ = await s.nextFrame()
        s.computeRoute()
        _ = await s.nextFrame()
    }

    private func writeOut(_ name: String, _ value: Any?) throws {
        _ = try G1Native.writeOut(name, JSON.encode(value))
    }

    // ---------------------------------------------------------------- B07-SEARCH / B03-ROUTING-GRAPH

    @MainActor
    private func benchSearchRoute(_ runId: String, _ kind: String) async throws {
        let s = state
        guard let data = s.data else { return }
        mark("run.start", ["run", runId, "bench", "search-route"])
        let start = now()
        s.goHome()
        _ = await s.nextFrame()
        var search: [Any] = []
        for q in data.queries {
            s.query = q.text
            let t0 = now()
            let compute = s.submitSearch()
            let t1 = Int64(await s.nextFrame())
            let r = s.results!
            search.append(JSON.Object([("id", q.id), ("outcome", r.outcome), ("ids", r.ids), ("compute_ns", compute), ("e2e_ns", t1 - t0)]))
        }
        s.clearSearch()
        var route: [Any] = []
        for c in data.routeCases {
            s.openRoute(c.destination, origin: c.origin, stepFree: c.stepFree, blocked: c.blocked)
            _ = await s.nextFrame()
            let t0 = now()
            let compute = s.computeRoute()
            let t1 = Int64(await s.nextFrame())
            let r = s.route!
            var row: [(String, Any?)] = [("id", c.id), ("outcome", r.outcome)]
            if r.outcome == "PATH" {
                row.append(("nodes", r.nodes))
                row.append(("length_mm", r.lengthMm))
                row.append(("steps", s.steps.map { $0.json }))
                row.append(("summary", s.summary!.json))
            }
            row.append(("compute_ns", compute))
            row.append(("e2e_ns", t1 - t0))
            route.append(JSON.Object(row))
            s.back()
        }
        s.goHome()
        let end = now()
        try writeOut("\(runId).json", JSON.Object([("contract", "G1-BENCH-SR-1.0"), ("run_id", runId), ("kind", kind), ("app", "C"),
                                                   ("bundle_version", data.version), ("start_ns", start), ("end_ns", end), ("search", search),
                                                   ("route", route)]))
        mark("run.done", ["run", runId, "bench", "search-route"])
    }

    // ---------------------------------------------------------------- B11-BRIDGE-OVERHEAD

    private func localEcho(_ payload: Data) -> (Int64, Int64) {
        let entry = now()
        let n = min(payload.count, echoBuffer.count)
        let crc: UInt32 = echoBuffer.withUnsafeMutableBytes { buf in
            payload.withUnsafeBytes { src in buf.copyMemory(from: UnsafeRawBufferPointer(rebasing: src[0..<n])) }
            return Crc32.of(UnsafeRawBufferPointer(rebasing: buf[0..<n]))
        }
        return (Int64(n) * twoTo32 + Int64(crc), entry)
    }

    private final class Series {
        var latencies: [Int64]
        var offsets: [Int64]
        var completed = 0
        var crcFailures = 0
        var t0: Int64 = 0
        let kind: String

        init(_ n: Int, _ kind: String) {
            latencies = Array(repeating: -1, count: n)
            offsets = Array(repeating: -1, count: n)
            self.kind = kind
        }

        var json: JSON.Object {
            JSON.Object([("kind", kind), ("t0_ns", t0), ("send_offsets_ns", offsets), ("latencies_ns", latencies), ("completed", completed),
                         ("crc_failures", crcFailures)])
        }
    }

    /// Candidate C's boundary check before the direct call (mirrors the A and B adapters): payloads above 64 KiB are refused.
    private func echoAsyncChecked(_ payload: Data, _ onReply: @escaping (Int64, UInt64) -> Void) -> String? {
        if payload.count > 64 * 1024 { return "PAYLOAD_TOO_LARGE" }
        // the callback runs on the native worker; the reply hops back to the main thread
        G1Native.echoAsync(payload) { r, entry in DispatchQueue.main.async { onReply(r, entry) } }
        return nil
    }

    @MainActor
    private func r2n(_ block: Data, _ size: Int, _ n: Int, _ rate: Int, control: Bool, sync: Bool) async -> Series {
        let sr = Series(n, control ? "control" : "measured")
        let lastProgress = Box(now())
        let t0 = now() + 20_000_000
        sr.t0 = t0
        for i in 0..<n {
            await sleepNs(t0 + Int64((Double(i) * 1e9 / Double(rate)).rounded()) - now())
            let off = offsetOf(i, size)
            let payload = block.subdata(in: off..<(off + size))
            let expected = Int64(size) * twoTo32 + Int64(Crc32.of(payload))
            let tSend = now()
            sr.offsets[i] = tSend - t0
            if control {
                let (r, entry) = localEcho(payload)
                sr.latencies[i] = entry - tSend
                if r != expected { sr.crcFailures += 1 }
                sr.completed += 1
            } else if sync {
                let (r, entry) = G1Native.echoSync(payload)
                sr.latencies[i] = Int64(entry) - tSend
                if r != expected { sr.crcFailures += 1 }
                sr.completed += 1
            } else {
                _ = echoAsyncChecked(payload) { r, entry in
                    sr.latencies[i] = Int64(entry) - tSend
                    if r != expected { sr.crcFailures += 1 }
                    sr.completed += 1
                    lastProgress.value = Int64(G1Native.nowNanos())
                }
            }
        }
        if !control && !sync {
            while sr.completed < n && now() - lastProgress.value < 10_000_000_000 { await sleepNs(10_000_000) }
        }
        return sr
    }

    @MainActor
    private func n2r(_ block: Data, _ size: Int, _ n: Int, _ rate: Int, control: Bool) async -> Series {
        let sr = Series(n, control ? "control" : "measured")
        let expected: [UInt32] = (0..<n).map { i in Crc32.of(block.subdata(in: offsetOf(i, size)..<(offsetOf(i, size) + size))) }
        let firstSent = Box<Int64?>(nil)
        let handler: (Int, Int64, Data) -> Void = { seq, sent, payload in
            let recv = Int64(G1Native.nowNanos())
            if firstSent.value == nil { firstSent.value = sent }
            if seq < 0 || seq >= n { return }
            sr.latencies[seq] = recv - sent
            sr.offsets[seq] = sent - firstSent.value!
            if payload.count != size || Crc32.of(payload) != expected[seq] { sr.crcFailures += 1 }
            sr.completed += 1
        }
        let t0 = now() + 20_000_000
        if control {
            for i in 0..<n {
                await sleepNs(t0 + Int64((Double(i) * 1e9 / Double(rate)).rounded()) - now())
                let off = offsetOf(i, size)
                handler(i, now(), block.subdata(in: off..<(off + size)))
            }
        } else {
            let done = Box(false)
            let lastProgress = Box(now())
            G1Native.startN2R(size: size, count: n, rateHz: rate, onMessage: { seq, sent, payload in
                DispatchQueue.main.async {
                    handler(seq, Int64(sent), payload)
                    lastProgress.value = Int64(G1Native.nowNanos())
                }
            }, onDone: { _, _ in DispatchQueue.main.async { done.value = true } })
            while !done.value && now() - lastProgress.value < 10_000_000_000 { await sleepNs(10_000_000) }
            await sleepNs(50_000_000)
        }
        sr.t0 = firstSent.value ?? t0
        return sr
    }

    @MainActor
    private func benchBridge(_ runId: String, _ workload: String, _ order: String, _ n: Int, _ rate: Int) async throws {
        mark("run.start", ["run", runId, "bench", "bridge", "workload", workload])
        var result: [(String, Any?)] = [("contract", "G1-BENCH-BRIDGE-1.0"), ("run_id", runId), ("app", "C"), ("workload", workload),
                                        ("order", order), ("messages", n), ("rate_hz", rate)]
        let parts = workload.split(separator: ".").map(String.init)
        var outcome = "FAILED"
        if parts.count == 3, ["R2N", "N2R"].contains(parts[0]), let size = sizes[parts[1]], ["async", "sync"].contains(parts[2]),
           !(parts[2] == "sync" && parts[0] != "R2N") {
            let block = state.ensurePayloadBlock()
            var series: [Series] = []
            for control in order == "measured-first" ? [false, true] : [true, false] {
                if parts[0] == "R2N" {
                    series.append(await r2n(block, size, n, rate, control: control, sync: parts[2] == "sync"))
                } else {
                    series.append(await n2r(block, size, n, rate, control: control))
                }
            }
            result.append(("series", series.map { $0.json }))
            outcome = series.allSatisfy { $0.completed == n } ? "OK" : "FAILED"
        }
        result.append(("outcome", outcome))
        try writeOut("\(runId).json", JSON.Object(result))
        mark("run.done", ["run", runId, "bench", "bridge", "outcome", outcome])
    }

    // ---------------------------------------------------------------- B07/B08 windows (G1-UI-SCRIPT-1.0)

    @MainActor
    private func window(_ id: String, _ warmupS: Int, _ measureS: Int, script: Bool) async throws {
        let s = state
        s.goHome()
        _ = await s.nextFrame()
        let totalMs = (warmupS + measureS) * 1000
        var events: [(Int, Keyframe?, String?)] = [(0, nil, "warmup.start"), (warmupS * 1000, nil, "measure.start")]
        if script {
            var cycle = 0
            while cycle < totalMs {
                for k in uiScript where cycle + k.atMs < totalMs { events.append((cycle + k.atMs, k, nil)) }
                cycle += uiCycleMs
            }
        }
        // stable sort: phases stay before keyframes at the same time
        events = events.enumerated().sorted { ($0.element.0, $0.offset) < ($1.element.0, $1.offset) }.map { $0.element }
        let start = now()
        for (at, k, phase) in events {
            await sleepNs(start + Int64(at) * 1_000_000 - now())
            if let phase {
                mark("session.window", ["session", id, "phase", phase])
            } else if let k, k.action == "floor", let f = k.floor {
                s.setFloor(f)
            } else if let k, let c = k.centerMm, let z = k.zoom, let d = k.durationMs {
                s.map?.easeTo(lon: lonOf(c[0]), lat: latOf(c[1]), zoom: z, durationMs: d)
            }
        }
        await sleepNs(start + Int64(totalMs) * 1_000_000 - now())
        mark("session.window", ["session", id, "phase", "end"])
    }

    // ---------------------------------------------------------------- B16 crash fixtures

    private struct SyntheticFailure: Error {}

    @MainActor
    private func crash(_ caseId: String, _ canaryValue: String?) async throws {
        canary = canaryValue // held in app state; must never reach a trace
        mark("crash.trigger", ["case", caseId])
        switch caseId {
        case "CR1":
            do {
                throw SyntheticFailure()
            } catch {
                try writeOut("crash-CR1.json", JSON.Object([("case", "CR1"), ("handled", true), ("type", String(describing: type(of: error)))]))
            }
        case "CR2":
            // unhandled failure on the UI path: Swift traps (the runtime's default behaviour for a failed precondition)
            NextFrame.run { _ in
                let values: [Int] = []
                _ = values[1]
            }
        case "CR3", "CR4":
            G1Native.crash(caseId)
        case "CR6":
            var hog: [Data] = []
            while true {
                hog.append(Data(repeating: 1, count: 16 * 1024 * 1024))
                await Task.yield()
            }
        default:
            break
        }
    }

    // ---------------------------------------------------------------- B16 fuzz targets

    private func fuzzOne(_ target: String, _ input: Data) -> String {
        let text = String(decoding: input, as: UTF8.self) // malformed sequences become U+FFFD
        switch target {
        case "FUZ01":
            return (qrOutcome(G1Native.validateQr(text))["outcome"] as? String) ?? "UNEXPECTED_OUTCOME"
        case "FUZ02":
            do {
                _ = try parseGraph(text)
                return "OK"
            } catch is FormatError {
                return "REJECT_FORMAT"
            } catch {
                return "UNEXPECTED_\(type(of: error))"
            }
        default:
            return decodeEnvelope(text)
        }
    }

    @MainActor
    private func fuzz(_ runId: String, _ target: String, _ corpus: String) async throws {
        mark("run.start", ["run", runId, "fuzz", target])
        guard let doc = try JSON.decode(G1Native.readImportText(corpus)) as? [String: Any], let inputs = doc["inputs"] as? [Any] else {
            throw FormatError("corpus")
        }
        var outcomes: [String: Any] = [:]
        var perInput: [Any] = []
        for e in inputs {
            let code: String
            if let b64 = e as? String, let bytes = Data(base64Encoded: b64) { code = fuzzOne(target, bytes) } else { code = "REJECT_CORPUS" }
            outcomes[code] = ((outcomes[code] as? Int) ?? 0) + 1
            perInput.append(code)
        }
        let unexpected = perInput.filter { ($0 as? String)?.hasPrefix("UNEXPECTED_") == true }.count
        try writeOut("\(runId).json", JSON.Object([("contract", "G1-FUZZ-1.0"), ("run_id", runId), ("app", "C"), ("target", target),
                                                   ("count", inputs.count), ("outcomes", outcomes), ("unexpected", unexpected), ("per_input", perInput)]))
        mark("run.done", ["run", runId, "fuzz", target])
    }

    // ---------------------------------------------------------------- B16 bridge attacks

    @MainActor
    private func attack(_ runId: String, _ caseId: String) async throws {
        mark("run.start", ["run", runId, "attack", caseId])
        let s = state
        let before = G1Native.bundleInfo()
        var r: [(String, Any?)] = []
        var outcome = "FAIL"
        switch caseId {
        case "BRG01":
            let payloads = ["G1SYN:", "G1SYN:1:A01", "G1SYN:9:A01:G1SYN-1.0.0:20271001T000000Z:" + String(repeating: "A", count: 86), "G1SYN:1:A1:x:y:z",
                            "javascript:alert(1)", "G1SYN:1:A01:G1SYN-1.0.0:20271001T000000Z:" + String(repeating: "!", count: 86)]
            let codes = payloads.map { (qrOutcome(G1Native.validateQr($0))["outcome"] as? String) ?? "-" }
            outcome = codes.allSatisfy { $0.hasPrefix("REJECT_") } ? "PASS" : "FAIL"
            r.append(("codes", codes))
        case "BRG02":
            let inputs = ["{", "[]", #"{"nodes":{}}"#, #"{"nodes":[],"edges":[{"id":1}]}"#, #"{"nodes":[{"id":"N1"}],"edges":[]}"#]
            let codes = inputs.map { i -> String in
                do {
                    _ = try parseGraph(i)
                    return "ACCEPTED"
                } catch is FormatError {
                    return "REJECT_FORMAT"
                } catch {
                    return "UNEXPECTED"
                }
            }
            outcome = codes.allSatisfy { $0 == "REJECT_FORMAT" } ? "PASS" : "FAIL"
            r.append(("codes", codes))
        case "BRG03", "BRG05":
            // Direct, statically typed calls: there is no name-based method dispatch and no runtime argument conversion
            // between the app and the common module, so these crafted calls cannot be expressed (compile-time errors).
            outcome = "NOT_APPLICABLE"
            r.append(("reason", "direct statically typed calls: no runtime method dispatch or argument conversion at the boundary"))
        case "BRG04":
            let q = (qrOutcome(G1Native.validateQr("G1SYN:" + String(repeating: "A", count: 3000)))["outcome"] as? String) ?? "-"
            let echo = echoAsyncChecked(Data(count: 64 * 1024 + 1)) { _, _ in }
            outcome = q == "REJECT_MALFORMED" && echo == "PAYLOAD_TOO_LARGE" ? "PASS" : "FAIL"
            r.append(("qr", q))
            r.append(("echo", echo ?? "accepted"))
        case "BRG06":
            // the receiving screen is dropped right after the request; the native events that follow must be ignored
            let ignoredBefore = s.ignoredArEvents
            s.openAr(script: #"[["TRACKING",100],["LOST",300]]"#)
            let id = s.activeAr
            s.dropAr()
            await sleepNs(1_500_000_000)
            if let id { G1Native.closeAr(requestId: id) }
            await sleepNs(500_000_000)
            outcome = s.activeAr == nil && s.ignoredArEvents > ignoredBefore ? "PASS" : "FAIL"
            r.append(("ignored", s.ignoredArEvents - ignoredBefore))
        case "BRG07":
            let second = Box<String??>(nil)
            G1Native.startQrScanner(from: nil, requestId: "dup-1") { _, _ in }
            G1Native.startQrScanner(from: nil, requestId: "dup-1") { _, error in DispatchQueue.main.async { second.value = .some(error) } }
            let deadline = now() + 5_000_000_000
            while second.value == nil && now() < deadline { await sleepNs(20_000_000) }
            let err = second.value ?? nil
            outcome = err == G1Native.duplicateRequest ? "PASS" : "FAIL"
            r.append(("second", err))
        default:
            r.append(("detail", "unknown case"))
        }
        let after = G1Native.bundleInfo()
        if before != after { outcome = "FAIL" }
        var doc: [(String, Any?)] = [("contract", "G1-ATTACK-1.0"), ("run_id", runId), ("app", "C"), ("case", caseId), ("outcome", outcome)]
        doc.append(contentsOf: r)
        doc.append(("state_unchanged", before == after))
        try writeOut("\(runId).json", JSON.Object(doc))
        mark("run.done", ["run", runId, "attack", caseId, "outcome", outcome])
    }
}
