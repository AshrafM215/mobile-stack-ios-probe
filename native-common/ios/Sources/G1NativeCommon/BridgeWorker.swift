// G1 common native module (iOS) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
import Foundation

/// The fixed native echo workload (same as Echo.java): copy into a preallocated buffer, CRC-32, return (length << 32) | crc.
public enum Echo {
    public static let maxPayload = 64 * 1024

    public static func into(_ buffer: UnsafeMutableRawBufferPointer, _ payload: Data) -> Int64 {
        let n = min(payload.count, buffer.count, maxPayload)
        if n > 0 {
            payload.withUnsafeBytes { src in buffer.baseAddress!.copyMemory(from: src.baseAddress!, byteCount: n) }
        }
        let crc = Crc32.update(0, UnsafeRawBufferPointer(start: buffer.baseAddress, count: n))
        return (Int64(n) << 32) | Int64(crc)
    }
}

/// BRIDGE-WORKLOAD-v0.1 native side, identical for A, B and C (same as BridgeWorker.java): one dedicated serial worker runs
/// the fixed echo (no steady-state allocation) and the native-to-runtime emitter (fixed open-loop rate). Payload bytes come
/// from the DRBG domain "bridge-payload".
public enum BridgeWorker {
    public static let maxPayload = Echo.maxPayload
    static let queue = DispatchQueue(label: "g1-bridge-worker", qos: .userInitiated)
    static let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: Echo.maxPayload, alignment: 16)
    static let bufferSync = UnsafeMutableRawBufferPointer.allocate(byteCount: Echo.maxPayload, alignment: 16)
    static let syncLock = NSLock()
    static let blockLock = NSLock()
    static var block: Data?

    /// 64 KiB deterministic payload block: SHA-256("G1-SYNTH|2026091401|bridge-payload|<counter>") concatenated.
    public static func payloadBlock() -> Data {
        blockLock.lock(); defer { blockLock.unlock() }
        if let block { return block }
        var out = Data(capacity: maxPayload)
        for i in 0..<(maxPayload / 32) {
            out.append(Hex.sha256Bytes(Data("G1-SYNTH|2026091401|bridge-payload|\(i)".utf8)))
        }
        block = out
        return out
    }

    /// Synchronous path on the caller's thread (B: JSI sync method; C: direct call). A has no synchronous path.
    /// Returns (length << 32 | crc, native entry time in nowNanos).
    public static func echoSync(_ payload: Data) -> (Int64, UInt64) {
        let entry = G1Trace.nowNanos()
        syncLock.lock(); defer { syncLock.unlock() }
        return (Echo.into(bufferSync, payload), entry)
    }

    /// Asynchronous path: hop to the dedicated worker queue; the callback runs on the worker queue with
    /// (length << 32 | crc, native entry time on the worker in nowNanos).
    public static func echoAsync(_ payload: Data, _ callback: @escaping (Int64, UInt64) -> Void) {
        queue.async {
            let entry = G1Trace.nowNanos()
            callback(Echo.into(buffer, payload), entry)
        }
    }

    /// Emits count messages of size bytes at rateHz from the worker queue (open loop; late ticks are counted, not skipped).
    public static func startN2R(size: Int, count: Int, rateHz: Int,
                                onMessage: @escaping (_ seq: Int, _ sentNanos: UInt64, _ payload: Data) -> Void,
                                onDone: @escaping (_ sent: Int, _ dropped: Int) -> Void) {
        if size <= 0 || size > maxPayload || count <= 0 || count > 100_000 || rateHz <= 0 || rateHz > 10_000 {
            queue.async { onDone(0, 0) }
            return
        }
        let block = payloadBlock()
        let start = DispatchTime.now() + .milliseconds(20)
        let periodNs = 1_000_000_000.0 / Double(rateHz)
        for seq in 0..<count {
            let offset = (seq * 64) % (maxPayload - size + 1)
            queue.asyncAfter(deadline: start + .nanoseconds(Int((Double(seq) * periodNs).rounded()))) {
                let p = block.subdata(in: offset..<(offset + size))
                onMessage(seq, G1Trace.nowNanos(), p)
                if seq == count - 1 { onDone(count, 0) }
            }
        }
    }
}

extension Hex {
    static func sha256Bytes(_ data: Data) -> Data {
        var out = Data(capacity: 32)
        let text = sha256(data)
        var it = text.utf8.makeIterator()
        func nibble(_ c: UInt8) -> UInt8 { c <= 57 ? c - 48 : c - 87 }
        while let h = it.next(), let l = it.next() { out.append((nibble(h) << 4) | nibble(l)) }
        return out
    }
}
