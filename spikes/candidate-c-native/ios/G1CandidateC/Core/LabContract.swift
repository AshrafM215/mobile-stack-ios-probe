// Candidate C (native iOS) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// Lab hook contract pieces of G1-CIC-1.0 that need no platform API (checked against contract.json by the unit tests).
import Foundation

let labCommands: Set<String> = [
    "bench.search-route", "bench.bridge", "bench.ui-session", "bench.idle", "nav.home", "nav.details", "nav.route",
    "nav.open-route-ar", "lang.set", "bundle.import", "bundle.rollback", "bundle.update", "qr.inject", "ar.inject",
    "session.start", "session.end", "session.status", "crash", "fuzz", "bridge.attack",
]

/// One G1-UI-SCRIPT-1.0 keyframe.
struct Keyframe {
    let atMs: Int
    let action: String
    var centerMm: [Int64]? = nil
    var zoom: Double? = nil
    var durationMs: Int? = nil
    var floor: Int? = nil
}

let uiScript: [Keyframe] = [
    Keyframe(atMs: 0, action: "camera", centerMm: [72000, 33000], zoom: 17.0, durationMs: 2000),
    Keyframe(atMs: 3000, action: "floor", floor: 2),
    Keyframe(atMs: 4000, action: "camera", centerMm: [272000, 33000], zoom: 17.0, durationMs: 4000),
    Keyframe(atMs: 9000, action: "camera", centerMm: [272000, 33000], zoom: 18.5, durationMs: 2000),
    Keyframe(atMs: 12000, action: "floor", floor: 3),
    Keyframe(atMs: 13000, action: "camera", centerMm: [472000, 33000], zoom: 18.5, durationMs: 5000),
    Keyframe(atMs: 19000, action: "camera", centerMm: [472000, 33000], zoom: 16.5, durationMs: 3000),
    Keyframe(atMs: 23000, action: "floor", floor: 1),
    Keyframe(atMs: 24000, action: "camera", centerMm: [72000, 33000], zoom: 17.0, durationMs: 5000),
]
let uiCycleMs = 30_000

/// Runtime-side decoder of the lab command envelope {"method": name, "args": {...}} (fuzz target FUZ03).
func decodeEnvelope(_ text: String) -> String {
    if text.utf16.count > 16 * 1024 { return "REJECT_SIZE" }
    guard let v = try? JSON.decode(text) else { return "REJECT_JSON" }
    guard let o = v as? [String: Any] else { return "REJECT_SHAPE" }
    guard let m = o["method"] as? String, labCommands.contains(m) else { return "REJECT_METHOD" }
    guard o["args"] is [String: Any] else { return "REJECT_ARGS" }
    if o.count != 2 { return "REJECT_SHAPE" }
    return "ACCEPT"
}
