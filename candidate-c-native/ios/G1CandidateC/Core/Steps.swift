// Candidate C (native iOS) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// G1-ROUTE-STEPS-1.0 in Swift.
import Foundation

/// kind: walk (m) | exit/enter (building) | stairs/elevator (floor) | arrive (code).
struct RouteStep: Equatable {
    let kind: String
    var m: Int64? = nil
    var building: String? = nil
    var floor: Int? = nil
    var code: String? = nil

    var json: JSON.Object {
        var pairs: [(String, Any?)] = [("kind", kind)]
        if let m { pairs.append(("m", m)) }
        if let building { pairs.append(("building", building)) }
        if let floor { pairs.append(("floor", floor)) }
        if let code { pairs.append(("code", code)) }
        return JSON.Object(pairs)
    }
}

struct RouteSummary: Equatable {
    let lengthM: Int64
    let steps: Int
    let floors: String

    var json: JSON.Object { JSON.Object([("length_m", lengthM), ("steps", steps), ("floors", floors)]) }
}

func metres(_ mm: Int64) -> Int64 {
    let x = mm + 500
    return x >= 0 ? x / 1000 : -((-x + 999) / 1000)
}

func routeSteps(_ graph: RouteGraph, _ nodes: [String: GraphNode], _ path: [String], _ dest: Destination) throws -> ([RouteStep], RouteSummary) {
    var steps: [RouteStep] = []
    var walk: Int64 = 0
    var total: Int64 = 0
    func flush() {
        if walk > 0 { steps.append(RouteStep(kind: "walk", m: metres(walk))) }
        walk = 0
    }
    var i = 0
    while i + 1 < path.count {
        let u = nodes[path[i]]!
        let v = nodes[path[i + 1]]!
        guard let e = graph.edge(path[i], path[i + 1]) else { throw FormatError("no edge \(path[i]) -> \(path[i + 1])") }
        total += e.lengthMm
        switch e.kind {
        case "corridor", "spur", "outdoor":
            walk += e.lengthMm
        case "entrance":
            walk += e.lengthMm
            flush()
            if let b = u.building, v.building == nil { steps.append(RouteStep(kind: "exit", building: b)) }
            else { steps.append(RouteStep(kind: "enter", building: v.building)) }
        case "stairs", "elevator":
            flush()
            steps.append(RouteStep(kind: e.kind, floor: v.floor))
        default:
            throw FormatError("unknown edge kind \(e.kind)")
        }
        i += 1
    }
    flush()
    steps.append(RouteStep(kind: "arrive", code: dest.code))
    var floors: [Int] = []
    for id in path {
        if let f = nodes[id]?.floor, !floors.contains(f) { floors.append(f) }
    }
    return (steps, RouteSummary(lengthM: metres(total), steps: steps.count, floors: floors.map(String.init).joined(separator: "-")))
}
