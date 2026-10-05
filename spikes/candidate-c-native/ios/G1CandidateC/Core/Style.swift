// Candidate C (native iOS) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// G1-STYLE-1.0 in Swift: local bundle URLs, floor filters, label language and the route source.
import Foundation

private func isFloorTest(_ e: Any) -> Bool {
    guard let a = e as? [Any], a.count == 3, a[0] as? String == "==", let g = a[1] as? [Any], g.count == 2,
          g[0] as? String == "get", g[1] as? String == "floor", JSON.integer(a[2]) != nil else { return false }
    return true
}

/// Replaces ["==", ["get", "floor"], n] by the selected floor anywhere in a filter expression.
func withFloor(_ expr: Any, _ floor: Int) -> Any {
    if isFloorTest(expr) { return ["==", ["get", "floor"], floor] as [Any] }
    if let a = expr as? [Any] { return a.map { withFloor($0, floor) } }
    return expr
}

private func replaceUrls(_ v: Any, _ baseUrl: String) -> Any {
    if let s = v as? String { return s.hasPrefix("g1bundle://") ? baseUrl + s.dropFirst("g1bundle://".count) : s }
    if let a = v as? [Any] { return a.map { replaceUrls($0, baseUrl) } }
    if let m = v as? [String: Any] { return m.mapValues { replaceUrls($0, baseUrl) } }
    return v
}

func textField(_ lang: String) -> [Any] { ["get", lang == "ar" ? "name_ar" : "name_en"] }

private func names(_ meta: [String: Any], _ key: String) -> Set<String> { Set((meta[key] as? [String]) ?? []) }

/// The style (as a JSON object) for the bundle directory, floor and language (initial load).
func buildStyleObject(_ styleJson: String, bundleDir: String, floor: Int, lang: String) throws -> [String: Any] {
    let base = "file://" + (bundleDir.hasSuffix("/") ? bundleDir : bundleDir + "/")
    guard var style = replaceUrls(try JSON.decode(styleJson), base) as? [String: Any], let meta = style["metadata"] as? [String: Any],
          let layers = style["layers"] as? [[String: Any]] else { throw FormatError("style") }
    let floorLayers = names(meta, "runtime_floor_layers")
    let langLayers = names(meta, "runtime_language_layers")
    style["layers"] = layers.map { l -> [String: Any] in
        var m = l
        let id = (l["id"] as? String) ?? ""
        if floorLayers.contains(id), let f = l["filter"] { m["filter"] = withFloor(f, floor) }
        if langLayers.contains(id) {
            var layout = (l["layout"] as? [String: Any]) ?? [:]
            layout["text-field"] = textField(lang)
            m["layout"] = layout
        }
        return m
    }
    return style
}

func buildStyle(_ styleJson: String, bundleDir: String, floor: Int, lang: String) throws -> String {
    JSON.encode(try buildStyleObject(styleJson, bundleDir: bundleDir, floor: floor, lang: lang))
}

/// Floor filter per runtime floor layer of the original style (for the layer predicates on floor changes).
func floorFilters(_ styleJson: String, _ floor: Int) throws -> [(String, Any)] {
    guard let style = try JSON.decode(styleJson) as? [String: Any], let meta = style["metadata"] as? [String: Any],
          let layers = style["layers"] as? [[String: Any]] else { throw FormatError("style") }
    let floorLayers = names(meta, "runtime_floor_layers")
    return layers.compactMap { l in
        guard let id = l["id"] as? String, floorLayers.contains(id), let f = l["filter"] else { return nil }
        return (id, withFloor(f, floor))
    }
}

/// FeatureCollection with copies of the path edge geometries (vertical edges have none).
func routeFeatures(_ data: BundleData, _ graph: RouteGraph, _ path: [String]) -> String {
    var features: [Any] = []
    var i = 0
    while i + 1 < path.count {
        if let e = graph.edge(path[i], path[i + 1]), let f = data.edgeFeatures[e.edge] { features.append(f) }
        i += 1
    }
    return JSON.encode(["type": "FeatureCollection", "features": features] as [String: Any])
}

let emptyFeatures = #"{"features":[],"type":"FeatureCollection"}"#
