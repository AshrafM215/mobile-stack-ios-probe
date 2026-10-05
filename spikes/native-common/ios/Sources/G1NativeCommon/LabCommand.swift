// G1 common native module (iOS) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
import Foundation

/// Lab hook transport (G1-CIC-1.0 lab_hooks) on iOS: launch arguments "-g1.cmd <cmd> -g1.args <json>" (read once per process)
/// or the URL "<scheme>://cmd?name=<cmd>&args=<url-encoded json>" for a running app. Only the registered command names are
/// accepted; args must be a JSON object of at most 16 KiB. Hooks exist only in lab builds. Same rules as LabCommand.java.
public struct LabCommand {
    public static let maxArgsChars = 16 * 1024
    public static let commands: Set<String> = [
        "bench.search-route", "bench.bridge", "bench.ui-session", "bench.idle", "nav.home", "nav.details", "nav.route",
        "nav.open-route-ar", "lang.set", "bundle.import", "bundle.rollback", "bundle.update", "qr.inject", "ar.inject",
        "session.start", "session.end", "session.status", "crash", "fuzz", "bridge.attack",
    ]

    public let name: String
    public let argsJson: String

    private static let lock = NSLock()
    private static var launchConsumed = false

    /// Validates one command; a rejected command is marked and returns nil.
    public static func make(_ name: String?, _ args: String?) -> LabCommand? {
        guard BuildFlags.lab, let name else { return nil }
        let argsText = args ?? "{}"
        if !commands.contains(name) || argsText.utf16.count > maxArgsChars {
            G1Trace.mark("command.rejected", [("reason", commands.contains(name) ? "args_size" : "unknown_command")])
            return nil
        }
        guard (try? Json.parseObject(Data(argsText.utf8))) != nil else {
            G1Trace.mark("command.rejected", [("reason", "args_json"), ("cmd", name)])
            return nil
        }
        G1Trace.mark("command.received", [("cmd", name)])
        return LabCommand(name: name, argsJson: argsText)
    }

    /// The launch-argument command, returned once per process (nil afterwards or when absent).
    public static func fromLaunchArguments(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> LabCommand? {
        lock.lock()
        if launchConsumed { lock.unlock(); return nil }
        launchConsumed = true
        lock.unlock()
        var name: String?
        var args: String?
        var i = 0
        while i < arguments.count {
            if arguments[i] == "-g1.cmd", i + 1 < arguments.count { name = arguments[i + 1]; i += 1 }
            else if arguments[i] == "-g1.args", i + 1 < arguments.count { args = arguments[i + 1]; i += 1 }
            i += 1
        }
        if name == nil { return nil }
        return make(name, args)
    }

    /// "<scheme>://cmd?name=<cmd>&args=<url-encoded json>"; nil when the URL is not a lab command.
    public static func fromURL(_ url: URL) -> LabCommand? {
        guard url.host == "cmd", let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        let name = items.first { $0.name == "name" }?.value
        let args = items.first { $0.name == "args" }?.value
        if name == nil { return nil }
        return make(name, args)
    }
}
