// G1 common native module (iOS) - NON-PRODUCTION / SYNTHETIC DATA ONLY.

/// Trusted-time rule of G1-TRUST-1.0: a persisted high-water mark of the wall clock observed at successful trust decisions.
/// A clock more than 300 s behind the mark is untrusted: no validity-dependent decision is taken and no authoritative
/// guidance is given until the clock is back at or after the mark.
public final class TrustedClock {
    public static let toleranceMs: Int64 = 300_000

    public let read: () -> Int64
    public let write: (Int64) -> Void

    public init(read: @escaping () -> Int64, write: @escaping (Int64) -> Void) {
        self.read = read
        self.write = write
    }

    public func trusted(_ nowMs: Int64) -> Bool {
        let hw = read()
        return hw <= 0 || nowMs >= hw - TrustedClock.toleranceMs
    }

    public var highWater: Int64 { read() }

    /// Raise the mark after a successful decision at trusted time; never lowers it.
    public func observe(_ nowMs: Int64) {
        if trusted(nowMs) && nowMs > read() { write(nowMs) }
    }
}
