// G1 common native module (iOS) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
import Foundation

/// Synthetic failure triggers of the common module (B16 CR3/CR4); runtime-side cases are implemented by each candidate.
public enum CrashHooks {
    /// CR3: native crash in the shared module (iOS: fatal trap; captured locally by the platform crash reporter).
    public static func nativeCrash() {
        guard BuildFlags.lab else { return }
        G1Trace.mark("crash.trigger", [("case", "CR3")])
        trap()
    }

    @inline(never)
    static func trap() -> Never { fatalError("G1 synthetic CR3") }

    /// CR4: block the main thread for 10 s.
    public static func hangMainThread() {
        guard BuildFlags.lab else { return }
        G1Trace.mark("crash.trigger", [("case", "CR4")])
        DispatchQueue.main.async { Thread.sleep(forTimeInterval: 10) }
    }
}
