// Candidate C (native iOS) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// Deterministic presentation helpers (no device time zone or locale involved).
import Foundation

/// The common module's bundle info (G1-TRUST-1.0 state of the active bundle).
struct BundleInfo: Equatable {
    let state: String, version: String?, dir: String?, validFromMs: Int64, validUntilMs: Int64, timeTrusted: Bool
    let previousVersion: String?, detail: String?

    static func parse(_ json: String) throws -> BundleInfo {
        guard let o = try JSON.decode(json) as? [String: Any] else { throw FormatError("bundle info") }
        return BundleInfo(state: (o["state"] as? String) ?? "NONE", version: o["version"] as? String, dir: o["dir"] as? String,
                          validFromMs: JSON.integer(o["valid_from_ms"]) ?? 0, validUntilMs: JSON.integer(o["valid_until_ms"]) ?? 0,
                          timeTrusted: JSON.bool(o["time_trusted"]) ?? false, previousVersion: o["previous_version"] as? String,
                          detail: o["detail"] as? String)
    }
}

private func floorDiv(_ a: Int64, _ b: Int64) -> Int64 { a >= 0 ? a / b : -((-a + b - 1) / b) }

private func civilFromDays(_ days: Int64) -> (Int64, Int, Int) {
    let z = days + 719_468
    let era = floorDiv(z, 146_097)
    let doe = z - era * 146_097
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
    let mp = (5 * doy + 2) / 153
    let d = Int(doy - (153 * mp + 2) / 5 + 1)
    let m = Int(mp < 10 ? mp + 3 : mp - 9)
    let y = yoe + era * 400
    return (m <= 2 ? y + 1 : y, m, d)
}

private func daysFromCivil(_ year: Int64, _ m: Int, _ d: Int) -> Int64 {
    let y = m <= 2 ? year - 1 : year
    let era = floorDiv(y, 400)
    let yoe = y - era * 400
    let doy = Int64((153 * (m > 2 ? m - 3 : m + 9) + 2) / 5 + d - 1)
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
    return era * 146_097 + doe - 719_468
}

/// UTC calendar date "YYYY-MM-DD" of epoch milliseconds.
func isoDate(_ epochMs: Int64) -> String {
    let (y, m, d) = civilFromDays(floorDiv(epochMs, 86_400_000))
    return String(format: "%04lld-%02ld-%02ld", y, m, d)
}

/// ISO weekday (1 = Monday) of the date part of "YYYY-MM-DDTHH:MM:SS+03:00" (the schedule's own fixed offset).
func weekdayOf(_ iso: String) -> Int {
    let c = Array(iso.utf8)
    func num(_ a: Int, _ b: Int) -> Int { Int(String(decoding: c[a..<b], as: UTF8.self)) ?? 0 }
    let days = daysFromCivil(Int64(num(0, 4)), num(5, 7), num(8, 10))
    let w = (days + 3) % 7
    return Int((w + 7) % 7 + 1) // 1970-01-01 was a Thursday (4)
}

func hhmm(_ iso: String) -> String { String(Array(iso)[11..<16]) }

func scheduleItem(_ s: Strings, _ e: ScheduleEntry) -> String {
    s.t("details.schedule.item", ["label": s.lang == "ar" ? e.labelAr : e.labelEn, "day": s.t("day.\(weekdayOf(e.start))"),
                                  "start": hhmm(e.start), "end": hhmm(e.end)])
}

func stepText(_ s: Strings, _ st: RouteStep) -> String {
    switch st.kind {
    case "walk": return s.t("route.step.walk", ["length": st.m])
    case "stairs": return s.t("route.step.stairs", ["floor": st.floor])
    case "elevator": return s.t("route.step.elevator", ["floor": st.floor])
    case "exit": return s.t("route.step.exit", ["building": st.building])
    case "enter": return s.t("route.step.enter", ["building": st.building])
    default: return s.t("route.step.arrive", ["code": st.code])
    }
}

func summaryText(_ s: Strings, _ m: RouteSummary) -> String {
    s.t("route.summary", ["length": m.lengthM, "steps": m.steps, "floors": m.floors])
}

func rejectText(_ s: Strings, _ outcome: String) -> String {
    switch outcome {
    case "REJECT_STEP_FREE_UNAVAILABLE": return s.t("route.reject.stepfree")
    case "REJECT_BLOCKED": return s.t("route.reject.blocked")
    case "REJECT_UNREACHABLE": return s.t("route.reject.unreachable")
    case "REJECT_UNTRUSTED": return s.t("route.reject.untrusted")
    default: return s.t("route.reject.unknown")
    }
}

func trustText(_ s: Strings, _ info: BundleInfo?) -> String {
    switch info?.state {
    case "VALID": return s.t("trust.status.valid", ["version": info?.version, "until": isoDate(info?.validUntilMs ?? 0)])
    case "EXPIRED": return s.t("trust.status.expired")
    case "TIME_UNTRUSTED": return s.t("trust.status.time_untrusted")
    case "NOT_YET_VALID": return s.t("trust.status.not_yet_valid")
    case "INVALID": return s.t("trust.status.invalid")
    default: return s.t("trust.status.none")
    }
}

/// Anchor-code result text for the common validator's outcome (or a scanner error code).
func qrText(_ s: Strings, _ o: [String: Any]) -> String {
    switch o["outcome"] as? String {
    case "IDENTITY_VALID":
        return s.t("qr.identity", ["anchor": o["anchor"], "building": o["building"], "floor": o["floor"],
                                   "kind": s.t("kind.\((o["kind"] as? String) ?? "")")])
    case "REJECT_BAD_SIGNATURE": return s.t("qr.reject.signature")
    case "REJECT_EXPIRED": return s.t("qr.reject.expired")
    case "REJECT_FOREIGN_PAYLOAD": return s.t("qr.reject.foreign")
    case "REJECT_UNKNOWN_ANCHOR": return s.t("qr.reject.unknown")
    case "REJECT_BUNDLE_MISMATCH": return s.t("qr.reject.bundle")
    case "REJECT_UNTRUSTED_TIME": return s.t("qr.reject.time")
    case "REJECT_NO_BUNDLE": return s.t("qr.reject.nobundle")
    case "CAMERA_UNAVAILABLE": return s.t("qr.camera.unavailable")
    case "PERMISSION_DENIED": return s.t("qr.camera.denied")
    case "CANCELLED": return s.t("qr.cancelled")
    default: return s.t("qr.reject.malformed")
    }
}

/// The validator's outcome JSON as a flat dictionary.
func qrOutcome(_ json: String) -> [String: Any] {
    ((try? JSON.decode(json)) as? [String: Any]) ?? ["outcome": "REJECT_MALFORMED"]
}
