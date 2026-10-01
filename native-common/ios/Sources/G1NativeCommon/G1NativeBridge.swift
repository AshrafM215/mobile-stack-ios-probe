// G1 common native module (iOS) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
#if canImport(ObjectiveC)
import Foundation

/// Objective-C surface of the facade for runtimes whose native boundary is Objective-C(++) (candidate B's TurboModule).
/// Numbers that cross into JavaScript are doubles: nanosecond clock values stay exact below 2^53 ns (about 104 days of
/// uptime) and (length << 32 | crc) values below 2^49. Binary payloads cross as base64 strings (the TurboModule boundary of
/// React Native has no binary type); the decode/encode cost is part of B's measured boundary.
@objc(G1NativeBridge)
public final class G1NativeBridge: NSObject {
    @objc public static func initialize(withAppId appId: String) { G1Native.initialize(appId: appId) }

    @objc public static func nowNanos() -> Double { Double(G1Native.nowNanos()) }

    @objc public static func mark(_ name: String, runtimeNanos: Double, kv: [String]) {
        G1Native.mark(name, runtimeNanos: runtimeNanos < 0 ? -1 : Int64(runtimeNanos), kv: kv)
    }

    @objc public static func reportReady(_ runtimeNanos: Double) { G1Native.reportReady(runtimeNanos: Int64(runtimeNanos)) }

    @objc public static func reportResumeReady(_ runtimeNanos: Double) { G1Native.reportResumeReady(runtimeNanos: Int64(runtimeNanos)) }

    @objc public static func ensureBundle() -> String { G1Native.ensureBundle() }

    @objc public static func bundleInfo() -> String { G1Native.bundleInfo() }

    /// file:// URL of the verified active bundle directory (with a trailing slash), or nil.
    @objc public static func bundleDirectoryUrl() -> String? { G1Native.bundleDirectory().map { $0.absoluteURL.absoluteString.hasSuffix("/") ? $0.absoluteURL.absoluteString : $0.absoluteURL.absoluteString + "/" } }

    @objc public static func importBundleFile(_ name: String) -> String { G1Native.importBundleFile(name) }

    /// Lab update: the runtime downloaded the container with its standard HTTP client (bytes as base64).
    @objc public static func importBundleBase64(_ base64: String, source: String) -> String {
        guard let data = Data(base64Encoded: base64) else { return TrustCodes.rejectMalformedContainer }
        return G1Native.importBundleBytes(data, source: source)
    }

    @objc public static func rollback() -> String { G1Native.rollback() }

    @objc public static func readBundleFile(_ relPath: String) -> String? { try? G1Native.readBundleFile(relPath) }

    @objc public static func validateQr(_ payload: String?) -> String { G1Native.validateQr(payload) }

    @objc public static func decodeQrImport(_ name: String) -> String? { G1Native.decodeQrImport(name) }

    #if canImport(UIKit) && canImport(AVFoundation) && canImport(CoreImage)
    @objc public static func startQrScanner(_ requestId: String, callback: @escaping (String?, String?) -> Void) {
        G1Native.startQrScanner(from: nil, requestId: requestId, callback: callback)
    }
    #endif

    @objc public static func arAvailability() -> String { G1Native.arAvailability() }

    #if canImport(UIKit) && canImport(ARKit)
    @objc public static func startAr(_ requestId: String, script: String?, texts: String?, listener: @escaping (String, String) -> Void) {
        G1Native.startAr(from: nil, requestId: requestId, scriptJson: script, textsJson: texts, listener: listener)
    }

    @objc public static func setArGuidance(_ requestId: String, allowed: Bool) { G1Native.setArGuidance(requestId: requestId, allowed: allowed) }

    @objc public static func closeAr(_ requestId: String) { G1Native.closeAr(requestId: requestId) }
    #endif

    /// [length << 32 | crc, native entry nanos]
    @objc public static func echoSyncBase64(_ base64: String) -> [NSNumber] {
        let (r, entry) = G1Native.echoSync(Data(base64Encoded: base64) ?? Data())
        return [NSNumber(value: Double(r)), NSNumber(value: Double(entry))]
    }

    @objc public static func echoAsyncBase64(_ base64: String, callback: @escaping (Double, Double) -> Void) {
        G1Native.echoAsync(Data(base64Encoded: base64) ?? Data()) { r, entry in callback(Double(r), Double(entry)) }
    }

    @objc public static func payloadBlockBase64() -> String { G1Native.payloadBlock().base64EncodedString() }

    @objc public static func startN2R(size: Int, count: Int, rateHz: Int,
                                      onMessage: @escaping (Int, Double, String) -> Void, onDone: @escaping (Int, Int) -> Void) {
        G1Native.startN2R(size: size, count: count, rateHz: rateHz, onMessage: { seq, sent, payload in
            onMessage(seq, Double(sent), payload.base64EncodedString())
        }, onDone: onDone)
    }

    @objc public static func sessionStart(_ marker: String) -> Bool { G1Native.sessionStart(marker) }

    @objc public static func sessionActive() -> Bool { G1Native.sessionActive() }

    @objc public static func sessionEnd() { G1Native.sessionEnd() }

    @objc public static func crash(_ caseId: String) { G1Native.crash(caseId) }

    /// SHA-256 of the written file, or nil when the name is refused or the write failed.
    @objc public static func writeOut(_ name: String, text: String) -> String? { try? G1Native.writeOut(name, text) }

    @objc public static func readImportText(_ name: String) -> String? { try? G1Native.readImportText(name) }

    @objc public static func labCa() -> String? { G1Native.labCa() }

    @objc public static func readImportBase64(_ name: String) -> String? { (try? G1Native.readImportBytes(name))?.base64EncodedString() }

    /// [name, argsJson] of the launch-argument lab command (once per process), or nil.
    @objc public static func launchCommand() -> [String]? { LabCommand.fromLaunchArguments().map { [$0.name, $0.argsJson] } }

    /// [name, argsJson] of a "<scheme>://cmd?..." URL, or nil.
    @objc public static func urlCommand(_ url: URL) -> [String]? { LabCommand.fromURL(url).map { [$0.name, $0.argsJson] } }
}
#endif
