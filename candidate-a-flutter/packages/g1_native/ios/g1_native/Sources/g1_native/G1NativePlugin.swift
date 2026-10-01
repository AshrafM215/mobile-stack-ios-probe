// Candidate A adapter to the G1 common native module (iOS) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
import Flutter
import G1NativeCommon
import UIKit

/// Platform-channel adapter (MethodChannel "g1/native", EventChannels "g1/events" and "g1/n2r"); same surface and argument
/// checks as the Android adapter: wrong argument types -> BAD_ARGUMENT, any string or byte field above 64 KiB ->
/// PAYLOAD_TOO_LARGE, unknown method -> FlutterMethodNotImplemented. Results are delivered on the main thread.
public final class G1NativePlugin: NSObject, FlutterPlugin {
    static let maxField = 64 * 1024
    static let maxBundle = 64 * 1024 * 1024
    private static var shared: G1NativePlugin?

    private var eventSink: FlutterEventSink?
    private var n2rSink: FlutterEventSink?
    private var pendingEvents: [[String: Any?]] = []
    private var launchCommand: [String: Any]?

    public static func register(with registrar: FlutterPluginRegistrar) {
        G1Native.initialize(appId: "A")
        let instance = G1NativePlugin()
        shared = instance
        if let cmd = LabCommand.fromLaunchArguments() { instance.launchCommand = ["name": cmd.name, "args": cmd.argsJson] }
        let channel = FlutterMethodChannel(name: "g1/native", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(instance, channel: channel)
        FlutterEventChannel(name: "g1/events", binaryMessenger: registrar.messenger()).setStreamHandler(Sink { sink in
            instance.eventSink = sink
            if let sink {
                for e in instance.pendingEvents { sink(e) }
                instance.pendingEvents.removeAll()
            }
        })
        FlutterEventChannel(name: "g1/n2r", binaryMessenger: registrar.messenger()).setStreamHandler(Sink { sink in
            instance.n2rSink = sink
        })
    }

    /// Lab command URL "g1bench-a://cmd?name=...&args=..." forwarded by the app's scene delegate.
    @discardableResult
    public static func handle(url: URL) -> Bool {
        guard let cmd = LabCommand.fromURL(url) else { return false }
        shared?.emit(["type": "command", "name": cmd.name, "args": cmd.argsJson])
        return true
    }

    private final class Sink: NSObject, FlutterStreamHandler {
        let onChange: (FlutterEventSink?) -> Void
        init(_ onChange: @escaping (FlutterEventSink?) -> Void) { self.onChange = onChange }

        func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
            onChange(events)
            return nil
        }

        func onCancel(withArguments arguments: Any?) -> FlutterError? {
            onChange(nil)
            return nil
        }
    }

    private func emit(_ event: [String: Any?]) {
        DispatchQueue.main.async {
            if let sink = self.eventSink { sink(event) } else { self.pendingEvents.append(event) }
        }
    }

    // ---------------- argument checks ----------------

    private struct BadArgument: Error {
        let code: String
        let message: String
    }

    private func args(_ call: FlutterMethodCall) -> [String: Any] { call.arguments as? [String: Any] ?? [:] }

    private func str(_ call: FlutterMethodCall, _ key: String, optional: Bool = false) throws -> String? {
        let v = args(call)[key]
        if v == nil || v is NSNull {
            if optional { return nil }
            throw BadArgument(code: "BAD_ARGUMENT", message: "\(key) missing")
        }
        guard let s = v as? String else { throw BadArgument(code: "BAD_ARGUMENT", message: "\(key) must be a string") }
        if s.utf16.count > Self.maxField { throw BadArgument(code: "PAYLOAD_TOO_LARGE", message: "\(key) too large") }
        return s
    }

    private func bytes(_ call: FlutterMethodCall, _ key: String, limit: Int = maxField) throws -> Data {
        guard let v = args(call)[key] as? FlutterStandardTypedData else { throw BadArgument(code: "BAD_ARGUMENT", message: "\(key) must be bytes") }
        if v.data.count > limit { throw BadArgument(code: "PAYLOAD_TOO_LARGE", message: "\(key) too large") }
        return v.data
    }

    private func int(_ call: FlutterMethodCall, _ key: String) throws -> Int {
        guard let n = args(call)[key] as? NSNumber, !Json.isBool(n) else { throw BadArgument(code: "BAD_ARGUMENT", message: "\(key) must be a number") }
        return n.intValue
    }

    private func bool(_ call: FlutterMethodCall, _ key: String) throws -> Bool {
        guard let n = args(call)[key] as? NSNumber, Json.isBool(n) else { throw BadArgument(code: "BAD_ARGUMENT", message: "\(key) must be a boolean") }
        return n.boolValue
    }

    // ---------------- dispatch ----------------

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        do {
            try dispatch(call, result)
        } catch let e as BadArgument {
            result(FlutterError(code: e.code, message: e.message, details: nil))
        } catch {
            result(FlutterError(code: "IO", message: String(describing: type(of: error)), details: nil))
        }
    }

    private func dispatch(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) throws {
        switch call.method {
        case "nowNanos": result(NSNumber(value: Int64(G1Native.nowNanos())))
        case "mark":
            let kvAny = args(call)["kv"] as? [Any] ?? []
            let kv = try kvAny.map { v -> String in
                guard let s = v as? String else { throw BadArgument(code: "BAD_ARGUMENT", message: "kv") }
                return s
            }
            G1Native.mark(try str(call, "name")!, runtimeNanos: Int64(try int(call, "rt")), kv: kv)
            result(nil)
        case "reportReady":
            G1Native.reportReady(runtimeNanos: Int64(try int(call, "rt")))
            result(nil)
        case "reportResumeReady":
            G1Native.reportResumeReady(runtimeNanos: Int64(try int(call, "rt")))
            result(nil)
        case "ensureBundle": result(G1Native.ensureBundle())
        case "bundleInfo": result(G1Native.bundleInfo())
        case "importBundleFile": result(G1Native.importBundleFile(try str(call, "name")!))
        case "importBundleBytes":
            result(G1Native.importBundleBytes(try bytes(call, "bytes", limit: Self.maxBundle), source: try str(call, "source")!))
        case "rollback": result(G1Native.rollback())
        case "readBundleFile": result(try G1Native.readBundleFile(try str(call, "path")!))
        case "validateQr": result(G1Native.validateQr(try str(call, "payload", optional: true)))
        case "decodeQrImport": result(G1Native.decodeQrImport(try str(call, "name")!))
        case "scanQr":
            G1Native.startQrScanner(from: nil, requestId: try str(call, "requestId")!) { payload, error in
                DispatchQueue.main.async { result(["payload": payload as Any, "error": error as Any]) }
            }
        case "arAvailability": result(G1Native.arAvailability())
        case "startAr":
            let requestId = try str(call, "requestId")!
            G1Native.startAr(from: nil, requestId: requestId, scriptJson: try str(call, "script", optional: true),
                             textsJson: try str(call, "texts", optional: true)) { [weak self] id, json in
                self?.emit(["type": "ar", "requestId": id, "event": json])
            }
            result(nil)
        case "closeAr":
            G1Native.closeAr(requestId: try str(call, "requestId")!)
            result(nil)
        case "setArGuidance":
            G1Native.setArGuidance(requestId: try str(call, "requestId")!, allowed: try bool(call, "allowed"))
            result(nil)
        case "payloadBlock": result(FlutterStandardTypedData(bytes: G1Native.payloadBlock()))
        case "echoAsync":
            let payload = try bytes(call, "payload")
            G1Native.echoAsync(payload) { r, entry in
                DispatchQueue.main.async { result(FlutterStandardTypedData(int64: Self.int64Data([r, Int64(entry)]))) }
            }
        case "startN2R":
            let size = try int(call, "size"), count = try int(call, "count"), rate = try int(call, "rateHz")
            G1Native.startN2R(size: size, count: count, rateHz: rate, onMessage: { [weak self] seq, sent, payload in
                DispatchQueue.main.async {
                    self?.n2rSink?(["seq": seq, "sent": NSNumber(value: Int64(sent)), "payload": FlutterStandardTypedData(bytes: payload)])
                }
            }, onDone: { [weak self] sent, dropped in
                DispatchQueue.main.async { self?.n2rSink?(["done": true, "sent": sent, "dropped": dropped]) }
            })
            result(nil)
        case "sessionStart": result(G1Native.sessionStart(try str(call, "marker")!))
        case "sessionActive": result(G1Native.sessionActive())
        case "sessionEnd":
            G1Native.sessionEnd()
            result(nil)
        case "crash":
            G1Native.crash(try str(call, "case")!)
            result(nil)
        case "writeOut": result(try G1Native.writeOut(try str(call, "name")!, try str(call, "text")!))
        case "readImportText": result(try G1Native.readImportText(try str(call, "name")!))
        case "labCa": result(G1Native.labCa())
        case "readImportBytes": result(FlutterStandardTypedData(bytes: try G1Native.readImportBytes(try str(call, "name")!)))
        case "launchCommand":
            let c = launchCommand
            launchCommand = nil
            result(c)
        default: result(FlutterMethodNotImplemented)
        }
    }

    private static func int64Data(_ values: [Int64]) -> Data {
        var data = Data(capacity: values.count * 8)
        for var v in values { withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
        return data
    }
}
