// Candidate C (native iOS) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// The verified bundle as the app sees it. Parsers are strict: any structural problem is a FormatError (fuzz target FUZ02
// and bridge attack BRG02 rely on that), never a crash or a partially loaded state.
import Foundation

struct Destination {
    let id: String, code: String, building: String, floor: Int, node: String, roomNumber: String, nameEn: String, nameAr: String
    let reachable: Bool
    func name(_ lang: String) -> String { lang == "ar" ? nameAr : nameEn }
}

struct GraphNode {
    let id: String, kind: String, building: String?, floor: Int?, xMm: Int64, yMm: Int64, entrance: Bool
}

struct GraphEdge {
    let id: String, from: String, to: String, edge: String, kind: String, lengthMm: Int64, stepFree: Bool
}

struct GraphData {
    let nodes: [GraphNode]
    let edges: [GraphEdge]
}

struct ScheduleEntry {
    let code: String, labelEn: String, labelAr: String, destination: String, start: String, end: String
}

struct RouteCase {
    let id: String, origin: String, destination: String, stepFree: Bool, blocked: [String]
}

struct Query {
    let id: String, text: String
}

private func obj(_ v: Any?, _ what: String) throws -> [String: Any] {
    guard let o = v as? [String: Any] else { throw FormatError("\(what): object expected") }
    return o
}

private func list(_ m: [String: Any], _ k: String) throws -> [Any] {
    guard let a = m[k] as? [Any] else { throw FormatError("\(k): array expected") }
    return a
}

private func str(_ m: [String: Any], _ k: String) throws -> String {
    guard let s = m[k] as? String else { throw FormatError("\(k): string expected") }
    return s
}

private func optStr(_ m: [String: Any], _ k: String) throws -> String? {
    guard let v = m[k], !(v is NSNull) else { return nil }
    guard let s = v as? String else { throw FormatError("\(k): string or null expected") }
    return s
}

private func long(_ m: [String: Any], _ k: String) throws -> Int64 {
    guard let i = JSON.integer(m[k]) else { throw FormatError("\(k): integer expected") }
    return i
}

private func int(_ m: [String: Any], _ k: String) throws -> Int {
    let v = try long(m, k)
    guard v >= Int64(Int32.min), v <= Int64(Int32.max) else { throw FormatError("\(k): integer out of range") }
    return Int(v)
}

private func optInt(_ m: [String: Any], _ k: String) throws -> Int? {
    guard let v = m[k], !(v is NSNull) else { return nil }
    return try int(m, k)
}

private func bool(_ m: [String: Any], _ k: String, _ fallback: Bool? = nil) throws -> Bool {
    if let b = JSON.bool(m[k]) { return b }
    if m[k] == nil, let fallback { return fallback }
    throw FormatError("\(k): boolean expected")
}

/// graph.json (G1-ROUTE-1.0 input).
func parseGraph(_ json: String) throws -> GraphData {
    let root = try obj(JSON.decode(json), "graph")
    var nodes: [GraphNode] = []
    var ids = Set<String>()
    for n in try list(root, "nodes") {
        let m = try obj(n, "node")
        let node = GraphNode(id: try str(m, "id"), kind: try str(m, "kind"), building: try optStr(m, "building"), floor: try optInt(m, "floor"),
                             xMm: try long(m, "x_mm"), yMm: try long(m, "y_mm"), entrance: try bool(m, "entrance", false))
        if !ids.insert(node.id).inserted { throw FormatError("duplicate node \(node.id)") }
        nodes.append(node)
    }
    var edges: [GraphEdge] = []
    for e in try list(root, "edges") {
        let m = try obj(e, "edge")
        let edge = GraphEdge(id: try str(m, "id"), from: try str(m, "from"), to: try str(m, "to"), edge: try str(m, "edge"),
                             kind: try str(m, "kind"), lengthMm: try long(m, "length_mm"), stepFree: try bool(m, "step_free"))
        if !ids.contains(edge.from) || !ids.contains(edge.to) { throw FormatError("edge \(edge.id): unknown node") }
        if edge.lengthMm < 0 { throw FormatError("edge \(edge.id): negative length") }
        edges.append(edge)
    }
    return GraphData(nodes: nodes, edges: edges)
}

func parseDestinations(_ json: String) throws -> [Destination] {
    let root = try obj(JSON.decode(json), "destinations")
    var out: [Destination] = []
    var ids = Set<String>()
    for d in try list(root, "destinations") {
        let m = try obj(d, "destination")
        let dest = Destination(id: try str(m, "id"), code: try str(m, "code"), building: try str(m, "building"), floor: try int(m, "floor"),
                               node: try str(m, "node"), roomNumber: try str(m, "room_number"), nameEn: try str(m, "name_en"),
                               nameAr: try str(m, "name_ar"), reachable: try bool(m, "reachable_from_entrances"))
        if !ids.insert(dest.id).inserted { throw FormatError("duplicate destination \(dest.id)") }
        out.append(dest)
    }
    return out
}

func parseSchedule(_ json: String) throws -> [ScheduleEntry] {
    try list(try obj(JSON.decode(json), "schedule"), "entries").map { e in
        let m = try obj(e, "entry")
        return ScheduleEntry(code: try str(m, "code"), labelEn: try str(m, "label_en"), labelAr: try str(m, "label_ar"),
                             destination: try str(m, "destination"), start: try str(m, "start"), end: try str(m, "end"))
    }
}

func parseRouteCases(_ json: String) throws -> [RouteCase] {
    try list(try obj(JSON.decode(json), "route cases"), "cases").map { c in
        let m = try obj(c, "case")
        let blocked = try list(m, "blocked").map { b -> String in
            guard let s = b as? String else { throw FormatError("blocked: string expected") }
            return s
        }
        return RouteCase(id: try str(m, "id"), origin: try str(m, "origin"), destination: try str(m, "destination"),
                         stepFree: try bool(m, "step_free"), blocked: blocked)
    }
}

func parseQueries(_ json: String) throws -> [Query] {
    try list(try obj(JSON.decode(json), "query corpus"), "queries").map { q in
        let m = try obj(q, "query")
        return Query(id: try str(m, "id"), text: try str(m, "text"))
    }
}

/// geometry.geojson LineString features of the non-vertical edges, by undirected edge id (route display).
func parseEdgeFeatures(_ json: String) throws -> [String: [String: Any]] {
    let root = try obj(JSON.decode(json), "geometry")
    var out: [String: [String: Any]] = [:]
    for f in try list(root, "features") {
        let m = try obj(f, "feature")
        let props = try obj(m["properties"], "properties")
        let geom = try obj(m["geometry"], "geometry")
        if let id = props["id"] as? String, id.hasPrefix("E"), geom["type"] as? String == "LineString" { out[id] = m }
    }
    return out
}

final class BundleData {
    let version: String
    let dir: String
    let destinations: [Destination]
    let graph: GraphData
    let schedule: [ScheduleEntry]
    let routeCases: [RouteCase]
    let queries: [Query]
    let styleJson: String
    let edgeFeatures: [String: [String: Any]]
    let byId: [String: Destination]
    let entrances: [String]

    init(version: String, dir: String, destinations: [Destination], graph: GraphData, schedule: [ScheduleEntry], routeCases: [RouteCase],
         queries: [Query], styleJson: String, edgeFeatures: [String: [String: Any]]) {
        self.version = version
        self.dir = dir
        self.destinations = destinations
        self.graph = graph
        self.schedule = schedule
        self.routeCases = routeCases
        self.queries = queries
        self.styleJson = styleJson
        self.edgeFeatures = edgeFeatures
        byId = Dictionary(destinations.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        entrances = graph.nodes.filter { $0.entrance && $0.building != nil }.map { $0.id }.sorted()
    }

    func scheduleFor(_ destinationId: String) -> [ScheduleEntry] {
        schedule.filter { $0.destination == destinationId }.sorted { $0.start < $1.start }
    }

    /// read: UTF-8 text of a bundle file (the common module's verified store on device, disk in tests).
    static func load(version: String, dir: String, read: (String) throws -> String) throws -> BundleData {
        BundleData(version: version, dir: dir, destinations: try parseDestinations(read("destinations.json")), graph: try parseGraph(read("graph.json")),
                   schedule: try parseSchedule(read("schedule.json")), routeCases: try parseRouteCases(read("route_cases.json")),
                   queries: try parseQueries(read("query_corpus.json")), styleJson: try read("style.json"),
                   edgeFeatures: try parseEdgeFeatures(read("geometry.geojson")))
    }
}
