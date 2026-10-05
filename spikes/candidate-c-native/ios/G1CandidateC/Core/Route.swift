// Candidate C (native iOS) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// G1-ROUTE-1.0 in Swift: Dijkstra on integer millimetres; ties take the smallest predecessor id.
import Foundation

/// outcome: PATH | REJECT_STEP_FREE_UNAVAILABLE | REJECT_BLOCKED | REJECT_UNREACHABLE | REJECT_UNKNOWN | REJECT_UNTRUSTED
struct RouteResult {
    let outcome: String
    let nodes: [String]
    let lengthMm: Int64
}

final class RouteGraph {
    private let ids: [String]
    private let index: [String: Int]
    private let edges: [GraphEdge]
    private let adj: [[Int]]
    private let byPair: [String: GraphEdge]

    init(_ g: GraphData) {
        ids = g.nodes.map { $0.id }.sorted()
        var idx: [String: Int] = [:]
        for (i, id) in ids.enumerated() { idx[id] = i }
        index = idx
        edges = g.edges
        var lists = Array(repeating: [Int](), count: ids.count)
        for (k, e) in g.edges.enumerated() { lists[idx[e.from]!].append(k) }
        adj = lists
        var pairs: [String: GraphEdge] = [:]
        for e in g.edges { pairs["\(e.from)>\(e.to)"] = e }
        byPair = pairs
    }

    func edge(_ from: String, _ to: String) -> GraphEdge? { byPair["\(from)>\(to)"] }

    private func dijkstra(_ origin: Int, _ stepFree: Bool, _ blocked: Set<String>) -> (dist: [Int64], prev: [Int]) {
        let n = ids.count
        var dist = Array(repeating: Int64(-1), count: n)
        var prev = Array(repeating: -1, count: n)
        var done = Array(repeating: false, count: n)
        var heap = Heap()
        dist[origin] = 0
        heap.push(0, origin)
        while heap.count > 0 {
            let d = heap.topDist
            let u = heap.pop()
            if done[u] { continue }
            done[u] = true
            for k in adj[u] {
                let e = edges[k]
                if blocked.contains(e.edge) || (stepFree && !e.stepFree) { continue }
                let v = index[e.to]!
                let nd = d + e.lengthMm
                let old = dist[v]
                if old < 0 || nd < old {
                    dist[v] = nd
                    prev[v] = u
                    heap.push(nd, v)
                } else if nd == old && u < prev[v] {
                    prev[v] = u
                }
            }
        }
        return (dist, prev)
    }

    func route(_ origin: String, _ targetNode: String, stepFree: Bool = false, blocked: [String] = []) -> RouteResult {
        guard let o = index[origin], let t = index[targetNode] else { return RouteResult(outcome: "REJECT_UNKNOWN", nodes: [], lengthMm: 0) }
        let blockedSet = Set(blocked)
        let (dist, prev) = dijkstra(o, stepFree, blockedSet)
        if dist[t] >= 0 {
            var path: [String] = []
            var v = t
            while true {
                path.append(ids[v])
                if v == o { break }
                v = prev[v]
            }
            return RouteResult(outcome: "PATH", nodes: path.reversed(), lengthMm: dist[t])
        }
        if stepFree && dijkstra(o, false, blockedSet).dist[t] >= 0 { return RouteResult(outcome: "REJECT_STEP_FREE_UNAVAILABLE", nodes: [], lengthMm: 0) }
        if !blockedSet.isEmpty && dijkstra(o, stepFree, []).dist[t] >= 0 { return RouteResult(outcome: "REJECT_BLOCKED", nodes: [], lengthMm: 0) }
        return RouteResult(outcome: "REJECT_UNREACHABLE", nodes: [], lengthMm: 0)
    }
}

/// Binary min-heap of (distance, node index); ties by node index.
private struct Heap {
    private var d: [Int64] = []
    private var v: [Int] = []
    var count: Int { d.count }
    var topDist: Int64 { d[0] }

    private func less(_ i: Int, _ j: Int) -> Bool { d[i] < d[j] || (d[i] == d[j] && v[i] < v[j]) }

    private mutating func swap(_ i: Int, _ j: Int) {
        d.swapAt(i, j)
        v.swapAt(i, j)
    }

    mutating func push(_ dist: Int64, _ node: Int) {
        d.append(dist)
        v.append(node)
        var i = d.count - 1
        while i > 0 {
            let p = (i - 1) >> 1
            if !less(i, p) { break }
            swap(i, p)
            i = p
        }
    }

    mutating func pop() -> Int {
        let top = v[0]
        let lastD = d.removeLast()
        let lastV = v.removeLast()
        if !d.isEmpty {
            d[0] = lastD
            v[0] = lastV
            var i = 0
            while true {
                let l = 2 * i + 1
                let r = l + 1
                var m = i
                if l < d.count && less(l, m) { m = l }
                if r < d.count && less(r, m) { m = r }
                if m == i { break }
                swap(i, m)
                i = m
            }
        }
        return top
    }
}
