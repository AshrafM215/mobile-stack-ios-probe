// G1 common native module tests (iOS) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// The facade as the runtimes see it: embedded resources, first-launch install through the trust check, QR validation,
// bundle file access, lab files and the bridge workload.
import Foundation
import XCTest
@testable import G1NativeCommon

final class FacadeTests: XCTestCase {
    func testFacadeInstallsEmbeddedBundleAndServesItsFiles() throws {
        let root = TestData.tempDir("g1facade")
        G1Native.initialize(appId: "T", storeRoot: root.appendingPathComponent("g1bundle"))
        G1Files.baseOverride = root.appendingPathComponent("files")
        let info = try Json.parseObject(Data(G1Native.ensureBundle().utf8))
        XCTAssertEqual(info["state"] as? String, "VALID")
        XCTAssertEqual(info["version"] as? String, "G1SYN-1.0.0")
        XCTAssertNotNil(G1Native.bundleDirectory())
        let style = try Json.parseObject(Data(try G1Native.readBundleFile("style.json").utf8))
        XCTAssertEqual((style["metadata"] as? [String: Any])?["style_contract"] as? String, "G1-STYLE-1.0")
        XCTAssertThrowsError(try G1Native.readBundleFile("../trust_store.json"))
        XCTAssertEqual(G1Native.rollback(), TrustCodes.rejectNoPrevious)

        let fx = try TestData.object("oracle/qr_fixtures.json")["fixtures"] as! [[String: Any]]
        for f in fx {
            let o = try Json.parseObject(Data(G1Native.validateQr(f["payload"] as? String).utf8))
            let expected = f["expected"] as! [String: Any]
            // live clock: the oracle's validity window covers the current lab period; expiry-dependent cases are skipped
            if (expected["outcome"] as? String) == TrustCodes.rejectExpired { continue }
            XCTAssertEqual(o["outcome"] as? String, expected["outcome"] as? String, f["id"] as? String ?? "?")
        }

        let sha = try G1Native.writeOut("result.json", "{\"ok\":true}")
        XCTAssertEqual(sha, Hex.sha256(Data("{\"ok\":true}".utf8)))
        try Data(contentsOf: TestData.out.appendingPathComponent("fixtures/U-G1SYN-1.0.1.zip"))
            .write(to: G1Files.importDir().appendingPathComponent("U-G1SYN-1.0.1.zip"))
        XCTAssertEqual(G1Native.importBundleFile("U-G1SYN-1.0.1.zip"), TrustCodes.activated)
        XCTAssertEqual(G1Native.importBundleFile("../escape.zip"), TrustCodes.rejectIO)
        XCTAssertEqual(G1Native.rollback(), TrustCodes.rollbackActivated)

        let done = expectation(description: "echo")
        let sent = G1Native.nowNanos()
        G1Native.echoAsync(Data("123456789".utf8)) { r, entry in
            XCTAssertEqual(r & 0xFFFF_FFFF, 0xCBF4_3926)
            XCTAssertGreaterThanOrEqual(entry, sent)
            done.fulfill()
        }
        let (syncResult, syncEntry) = G1Native.echoSync(Data("123456789".utf8))
        XCTAssertEqual(syncResult, (9 << 32) | 0xCBF4_3926)
        XCTAssertGreaterThanOrEqual(syncEntry, sent)
        let emitted = expectation(description: "n2r")
        var received = 0
        G1Native.startN2R(size: 64, count: 20, rateHz: 1000, onMessage: { _, _, p in
            XCTAssertEqual(p.count, 64)
            received += 1
        }, onDone: { sent, dropped in
            XCTAssertEqual(sent, 20)
            XCTAssertEqual(dropped, 0)
            emitted.fulfill()
        })
        wait(for: [done, emitted], timeout: 10)
        XCTAssertEqual(received, 20)
        G1Files.baseOverride = nil
    }
}
