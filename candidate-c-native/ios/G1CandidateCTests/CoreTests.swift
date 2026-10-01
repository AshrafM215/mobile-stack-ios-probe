// Candidate C (native iOS) unit tests - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// The Swift implementations of G1-SEARCH-1.0, G1-ROUTE-1.0, G1-ROUTE-STEPS-1.0 and G1-STYLE-1.0 against the generated
// oracle (spikes/synthetic-data/out), plus strings, lab-hook, envelope and format checks.
import Foundation
import XCTest
#if canImport(G1CCore)
@testable import G1CCore
#else
@testable import G1CandidateC
#endif

enum CoreData {
    /// <spikes>, from G1_SPIKES or relative to this source file.
    static let root: URL = {
        if let env = ProcessInfo.processInfo.environment["G1_SPIKES"], !env.isEmpty { return URL(fileURLWithPath: env, isDirectory: true) }
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
    }()
    static let out = root.appendingPathComponent("synthetic-data/out", isDirectory: true)

    static func text(_ url: URL) throws -> String { String(decoding: try Data(contentsOf: url), as: UTF8.self) }

    /// Entries of a stored (method 0) ZIP, enough for the synthetic bundle.
    static func storedZip(_ z: [UInt8]) -> [String: [UInt8]] {
        func u16(_ p: Int) -> Int { Int(z[p]) | Int(z[p + 1]) << 8 }
        func u32(_ p: Int) -> Int { u16(p) | u16(p + 2) << 16 }
        let eocd = z.count - 22
        let count = u16(eocd + 10)
        var p = u32(eocd + 16)
        var out: [String: [UInt8]] = [:]
        for _ in 0..<count {
            let size = u32(p + 24)
            let nameLen = u16(p + 28)
            let local = u32(p + 42)
            let name = String(decoding: z[(p + 46)..<(p + 46 + nameLen)], as: UTF8.self)
            let start = local + 30 + u16(local + 26)
            out[name] = Array(z[start..<(start + size)])
            p += 46 + nameLen
        }
        return out
    }

    static let bundle: [String: [UInt8]] = storedZip([UInt8](try! Data(contentsOf: out.appendingPathComponent("bundle/G1SYN-1.0.0.zip"))))

    static func file(_ name: String) -> String { String(decoding: bundle[name]!, as: UTF8.self) }
}

final class CoreTests: XCTestCase {
    private func load() throws -> ([Destination], GraphData, RouteGraph, [String: GraphNode]) {
        let destinations = try parseDestinations(CoreData.file("destinations.json"))
        let g = try parseGraph(CoreData.file("graph.json"))
        return (destinations, g, RouteGraph(g), Dictionary(g.nodes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }))
    }

    func testSearchAgreesWithTheOracleOnAll500Queries() throws {
        let (destinations, _, _, _) = try load()
        let index = SearchIndex(destinations)
        let queries = try parseQueries(CoreData.file("query_corpus.json"))
        let oracle = (try JSON.decode(CoreData.text(CoreData.out.appendingPathComponent("oracle/search_oracle.json"))) as! [String: Any])["results"] as! [[String: Any]]
        XCTAssertEqual(queries.count, 500)
        for (i, q) in queries.enumerated() {
            let r = index.search(q.text)
            XCTAssertEqual(r.outcome, oracle[i]["outcome"] as? String, q.id)
            XCTAssertEqual(r.ids, oracle[i]["ids"] as? [String], q.id)
        }
    }

    func testRouteAndStepsAgreeWithTheOracleOnAll30Cases() throws {
        let (destinations, _, graph, nodes) = try load()
        let byId = Dictionary(destinations.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let cases = try parseRouteCases(CoreData.file("route_cases.json"))
        let oracle = (try JSON.decode(CoreData.text(CoreData.out.appendingPathComponent("oracle/route_oracle.json"))) as! [String: Any])["results"] as! [[String: Any]]
        XCTAssertEqual(cases.count, 30)
        for (i, c) in cases.enumerated() {
            let d = byId[c.destination]!
            let r = graph.route(c.origin, d.node, stepFree: c.stepFree, blocked: c.blocked)
            XCTAssertEqual(r.outcome, oracle[i]["outcome"] as? String, c.id)
            if r.outcome == "PATH" {
                XCTAssertEqual(r.nodes, oracle[i]["nodes"] as? [String], c.id)
                XCTAssertEqual(r.lengthMm, JSON.integer(oracle[i]["length_mm"]), c.id)
                let (steps, summary) = try routeSteps(graph, nodes, r.nodes, d)
                XCTAssertEqual(JSON.encode(steps.map { $0.json }), JSON.encode(oracle[i]["steps"].map { reorder($0) }), c.id)
                XCTAssertEqual(JSON.encode(summary.json), JSON.encode(reorder(oracle[i]["summary"]!)), c.id)
            }
        }
    }

    /// The oracle's objects in the key order of the app's writer (kind, m, building, floor, code / length_m, steps, floors).
    private func reorder(_ v: Any) -> Any {
        let order = ["kind", "m", "building", "floor", "code", "length_m", "steps", "floors"]
        if let a = v as? [Any] { return a.map { reorder($0) } }
        if let m = v as? [String: Any] { return JSON.Object(order.compactMap { k in m[k].map { (k, $0) } }) }
        return v
    }

    func testParsersRejectMalformedInputWithFormatErrorOnly() {
        let inputs = ["", "{", "[]", #"{"nodes":{}}"#, #"{"nodes":[],"edges":[{"id":1}]}"#, #"{"nodes":[{"id":"N1"}],"edges":[]}"#,
                      #"{"nodes":[{"id":"N1","kind":"corridor","x_mm":0,"y_mm":0},{"id":"N1","kind":"corridor","x_mm":0,"y_mm":0}],"edges":[]}"#,
                      #"{"nodes":[{"id":"N1","kind":"corridor","x_mm":0.5,"y_mm":0}],"edges":[]}"#,
                      #"{"nodes":[{"id":"N1","kind":"corridor","x_mm":true,"y_mm":0}],"edges":[]}"#,
                      #"{"nodes":[{"id":"N1","kind":"corridor","x_mm":"0","y_mm":0}],"edges":[]}"#]
        for input in inputs {
            XCTAssertThrowsError(try parseGraph(input), input) { XCTAssertTrue($0 is FormatError, input) }
        }
        XCTAssertThrowsError(try parseDestinations(#"{"destinations":[{"id":"D1"}]}"#)) { XCTAssertTrue($0 is FormatError) }
    }

    func testStyleTransforms() throws {
        let styleJson = CoreData.file("style.json")
        let st = try buildStyleObject(styleJson, bundleDir: "/data/g1/v-1", floor: 2, lang: "en")
        XCTAssertEqual(st["glyphs"] as? String, "file:///data/g1/v-1/glyphs/{fontstack}/{range}.pbf")
        XCTAssertEqual(((st["sources"] as? [String: Any])?["synthetic"] as? [String: Any])?["data"] as? String, "file:///data/g1/v-1/geometry.geojson")
        let layers = Dictionary((st["layers"] as! [[String: Any]]).map { ($0["id"] as! String, $0) }, uniquingKeysWith: { a, _ in a })
        XCTAssertEqual(JSON.encode(layers["rooms"]!["filter"]), #"["all",["==",["get","kind"],"room"],["==",["get","floor"],2]]"#)
        XCTAssertEqual(JSON.encode(layers["route"]!["filter"]), #"["any",["!",["has","floor"]],["==",["get","floor"],2]]"#)
        XCTAssertEqual(JSON.encode((layers["room-labels"]!["layout"] as! [String: Any])["text-field"]), #"["get","name_en"]"#)
        XCTAssertEqual(try floorFilters(styleJson, 3).count, 7)
        let original = (try JSON.decode(styleJson) as! [String: Any])["layers"] as! [[String: Any]]
        XCTAssertEqual((st["layers"] as! [[String: Any]]).map { $0["id"] as! String }, original.map { $0["id"] as! String })
    }

    func testStringsAndPresentation() throws {
        let resources = CoreData.root.appendingPathComponent("candidate-c-native/ios/G1CandidateC/Resources/strings")
        let enText = try CoreData.text(resources.appendingPathComponent("en.json"))
        let arText = try CoreData.text(resources.appendingPathComponent("ar.json"))
        XCTAssertEqual(enText, try CoreData.text(CoreData.root.appendingPathComponent("contract/strings/en.json")))
        XCTAssertEqual(arText, try CoreData.text(CoreData.root.appendingPathComponent("contract/strings/ar.json")))
        let en = try Strings.parse("en", enText)
        let ar = try Strings.parse("ar", arText)
        XCTAssertEqual(en.keys, ar.keys)
        XCTAssertTrue(ar.rtl)
        XCTAssertFalse(en.rtl)
        // every key referenced as s.t("...") in the app sources exists in both languages
        let appDir = CoreData.root.appendingPathComponent("candidate-c-native/ios/G1CandidateC")
        var sources = ""
        for sub in ["App", "Core"] {
            let dir = appDir.appendingPathComponent(sub)
            for f in (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [] where f.hasSuffix(".swift") {
                sources += try CoreData.text(dir.appendingPathComponent(f)) + "\n"
            }
        }
        var referenced = Set<String>()
        let marker = "s.t(\""
        var rest = Substring(sources)
        while let r = rest.range(of: marker) {
            let after = rest[r.upperBound...]
            if let end = after.firstIndex(of: "\"") {
                let key = String(after[..<end])
                if key.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "_" }) && !key.contains("\\") { referenced.insert(key) }
                rest = after[end...]
            } else { break }
        }
        XCTAssertGreaterThan(referenced.count, 40)
        for k in referenced { XCTAssertTrue(en.has(k) && ar.has(k), k) }
        for s in [en, ar] {
            XCTAssertFalse(stepText(s, RouteStep(kind: "walk", m: 12)).hasPrefix("["))
            XCTAssertFalse(trustText(s, nil).hasPrefix("["))
            for code in ["IDENTITY_VALID", "REJECT_EXPIRED", "REJECT_NO_BUNDLE", "CAMERA_UNAVAILABLE", "PERMISSION_DENIED", "CANCELLED"] {
                XCTAssertFalse(qrText(s, ["outcome": code, "anchor": "A01", "building": "SB1", "floor": 1, "kind": "stairs"]).contains("["), code)
            }
            for d in 1...7 { XCTAssertTrue(s.has("day.\(d)")) }
        }
        let schedule = try parseSchedule(CoreData.file("schedule.json"))
        XCTAssertTrue(scheduleItem(en, schedule[0]).contains("Tuesday"))
        XCTAssertEqual(isoDate(1_822_348_800_000), "2027-10-01")
        XCTAssertEqual(isoDate(0), "1970-01-01")
        XCTAssertEqual(weekdayOf("2026-09-29T08:00:00+03:00"), 2)
        XCTAssertEqual(weekdayOf("2026-10-04T08:00:00+03:00"), 7)
    }

    func testLabHooksMatchTheContract() throws {
        let contract = try JSON.decode(CoreData.text(CoreData.root.appendingPathComponent("contract/contract.json"))) as! [String: Any]
        let commands = ((contract["lab_hooks"] as! [String: Any])["commands"] as! [String: Any]).keys
        XCTAssertEqual(Set(commands), labCommands)
        let keyframes = (contract["ui_session_script"] as! [String: Any])["keyframes"] as! [[String: Any]]
        XCTAssertEqual(keyframes.count, uiScript.count)
        for (k, ours) in zip(keyframes, uiScript) {
            XCTAssertEqual(JSON.integer(k["at_ms"]), Int64(ours.atMs))
            XCTAssertEqual(k["action"] as? String, ours.action)
            if ours.action == "floor" {
                XCTAssertEqual(JSON.integer(k["floor"]), ours.floor.map { Int64($0) })
            } else {
                XCTAssertEqual((k["center_mm"] as? [Any])?.compactMap { JSON.integer($0) }, ours.centerMm)
                XCTAssertEqual((k["zoom"] as? NSNumber)?.doubleValue, ours.zoom)
                XCTAssertEqual(JSON.integer(k["duration_ms"]), ours.durationMs.map { Int64($0) })
            }
        }
        XCTAssertEqual(decodeEnvelope(#"{"method":"nav.home","args":{}}"#), "ACCEPT")
        XCTAssertEqual(decodeEnvelope(#"{"method":"shell","args":{}}"#), "REJECT_METHOD")
        XCTAssertEqual(decodeEnvelope(#"{"method":"nav.home","args":[]}"#), "REJECT_ARGS")
        XCTAssertEqual(decodeEnvelope(#"{"method":"nav.home","args":{},"x":1}"#), "REJECT_SHAPE")
        XCTAssertEqual(decodeEnvelope("[]"), "REJECT_SHAPE")
        XCTAssertEqual(decodeEnvelope("{"), "REJECT_JSON")
        XCTAssertEqual(decodeEnvelope(String(repeating: "x", count: 20000)), "REJECT_SIZE")
    }

    func testRuntimeCrc32AndWriter() {
        XCTAssertEqual(Crc32.of(Data("123456789".utf8)), 0xCBF4_3926)
        XCTAssertEqual(JSON.encode(JSON.Object([("a", 1), ("b", ["x", nil] as [Any?]), ("c", true), ("d", Int64(5_000_000_000))])),
                       #"{"a":1,"b":["x",null],"c":true,"d":5000000000}"#)
    }
}
