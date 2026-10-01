// G1 common native module tests (iOS) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// Same cases as TrustContractTest.java on Android, against the generated synthetic dataset (spikes/synthetic-data/out).
import Foundation
import XCTest
@testable import G1NativeCommon

enum TestData {
    /// <spikes>/synthetic-data/out, from G1_DATA or relative to this source file.
    static let out: URL = {
        if let env = ProcessInfo.processInfo.environment["G1_DATA"], !env.isEmpty { return URL(fileURLWithPath: env, isDirectory: true) }
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("synthetic-data/out", isDirectory: true)
    }()
    static let wStart = IsoTime.parseExtended("2026-10-01T00:00:00Z")!
    static let now = wStart + 86_400_000

    static func bytes(_ rel: String) throws -> Data { try Data(contentsOf: out.appendingPathComponent(rel)) }
    static func object(_ rel: String) throws -> [String: Any] { try Json.parseObject(bytes(rel)) }
    static func trust() throws -> TrustStore { try TrustStore.parse(bytes("app/trust_store.json")) }

    static func tempDir(_ name: String) -> URL {
        let u = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
}

final class TrustContractTests: XCTestCase {
    func testEmbeddedBundleVerifiesAndEveryFixtureGetsItsExactCode() throws {
        let store = try TestData.trust()
        let r = BundleVerifier.verifyZip(try TestData.bytes("bundle/G1SYN-1.0.0.zip"), store: store, nowMs: TestData.now, timeTrusted: true, activeVersion: nil)
        XCTAssertEqual(r.code, TrustCodes.activated)
        XCTAssertEqual(r.version, "G1SYN-1.0.0")
        let fixtures = try TestData.object("fixtures/FIXTURES.json")["fixtures"] as! [[String: Any]]
        var checked = 0
        for f in fixtures {
            guard let file = f["file"] as? String else { continue }
            let fr = BundleVerifier.verifyZip(try TestData.bytes(file), store: store, nowMs: TestData.now, timeTrusted: true, activeVersion: "G1SYN-1.0.0")
            XCTAssertEqual(fr.code, f["expected"] as? String, f["id"] as? String ?? "?")
            checked += 1
        }
        XCTAssertEqual(checked, 11)
    }

    func testUntrustedTimeRejectsBeforeAnyValidityDecision() throws {
        let r = BundleVerifier.verifyZip(try TestData.bytes("fixtures/F-EXPIRED.zip"), store: try TestData.trust(),
                                         nowMs: TestData.wStart - 30 * 86_400_000, timeTrusted: false, activeVersion: "G1SYN-1.0.0")
        XCTAssertEqual(r.code, TrustCodes.rejectUntrustedTime)
    }

    func testContainerRejectsTraversalCompressionCommentsAndTruncation() throws {
        let good = try TestData.bytes("bundle/G1SYN-1.0.0.zip")
        assertMalformed(good.prefix(good.count - 5))
        var withComment = good + Data([0, 0, 0])
        withComment[good.count - 2] = 3
        assertMalformed(withComment)
        assertMalformed(Self.zip("../evil.txt", Data("x".utf8), method: 0))
        assertMalformed(Self.zip("a//b.txt", Data("x".utf8), method: 0))
        assertMalformed(Self.zip("ok.txt", Data("x".utf8), method: 8))
        let ok = try StoredZip.read(Self.zip("dir/ok.txt", Data("hello".utf8), method: 0))
        XCTAssertEqual(String(decoding: ok["dir/ok.txt"]!, as: UTF8.self), "hello")
        // invalid UTF-8 in a name is a malformed container
        assertMalformed(Self.zipRawName(Data([0x61, 0xFF, 0x62]), Data("x".utf8), method: 0))
    }

    private func assertMalformed(_ zip: Data, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try StoredZip.read(zip), file: file, line: line)
    }

    static func zip(_ name: String, _ data: Data, method: Int) -> Data { zipRawName(Data(name.utf8), data, method: method) }

    /// One-entry ZIP; method 8 is declared to prove that compressed entries are refused.
    static func zipRawName(_ n: Data, _ data: Data, method: Int) -> Data {
        let crc = Int(Crc32.checksum(data))
        var b = Data()
        func le16(_ v: Int) { b.append(UInt8(v & 0xFF)); b.append(UInt8((v >> 8) & 0xFF)) }
        func le32(_ v: Int) { le16(v & 0xFFFF); le16((v >> 16) & 0xFFFF) }
        le32(0x0403_4B50); le16(10); le16(0x0800); le16(method); le16(0); le16(0x21)
        le32(crc); le32(data.count); le32(data.count); le16(n.count); le16(0)
        b.append(n); b.append(data)
        let cdOffset = b.count
        le32(0x0201_4B50); le16(20); le16(10); le16(0x0800); le16(method); le16(0); le16(0x21)
        le32(crc); le32(data.count); le32(data.count); le16(n.count); le16(0); le16(0)
        le16(0); le16(0); le32(0); le32(0)
        b.append(n)
        let cdSize = b.count - cdOffset
        le32(0x0605_4B50); le16(0); le16(0); le16(1); le16(1); le32(cdSize); le32(cdOffset); le16(0)
        return b
    }

    func testStoreActivatesAtomicallyKeepsLastValidBundleAndRollsBack() throws {
        let dir = TestData.tempDir("g1store")
        var now = TestData.now
        let s = BundleStore(root: dir, store: try TestData.trust(), clock: { now })
        XCTAssertEqual(s.load().state, BundleStore.stateNone)
        XCTAssertEqual(s.importBundle(try TestData.bytes("bundle/G1SYN-1.0.0.zip")), TrustCodes.activated)
        XCTAssertEqual(s.load().version, "G1SYN-1.0.0")
        for bad in ["F-TAMPERED", "F-MIXED", "F-REVOKED", "F-DOWNGRADE", "F-WRONG-VERSION"] {
            _ = s.importBundle(try TestData.bytes("fixtures/\(bad).zip"))
            XCTAssertEqual(s.load().version, "G1SYN-1.0.0", bad)
        }
        XCTAssertEqual(s.importBundle(try TestData.bytes("fixtures/U-G1SYN-1.0.1.zip")), TrustCodes.activated)
        let info = s.load()
        XCTAssertEqual(info.version, "G1SYN-1.0.1")
        XCTAssertEqual(info.previousVersion, "G1SYN-1.0.0")
        XCTAssertEqual(s.rollbackToPrevious(), TrustCodes.rollbackActivated)
        XCTAssertEqual(s.load().version, "G1SYN-1.0.0")
        // tamper with the active directory: the store falls back to the verified previous bundle
        let active = s.load().dir!
        try Data("{}".utf8).write(to: active.appendingPathComponent("graph.json"))
        let after = s.load()
        XCTAssertTrue(after.usable)
        XCTAssertEqual(after.version, "G1SYN-1.0.1")
        // an interrupted activation leaves only a staging directory, which the next start removes
        let staging = dir.appendingPathComponent("staging-999")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        _ = BundleStore(root: dir, store: try TestData.trust(), clock: { now })
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path))
        now += 1
    }

    func testClockRollbackIsUntrustedTimeAndExpiryIsNeverRenewed() throws {
        let dir = TestData.tempDir("g1clock")
        var now = TestData.now
        let s = BundleStore(root: dir, store: try TestData.trust(), clock: { now })
        XCTAssertEqual(s.importBundle(try TestData.bytes("bundle/G1SYN-1.0.0.zip")), TrustCodes.activated)
        XCTAssertEqual(s.importBundle(try TestData.bytes("fixtures/F-EXPIRED.zip")), TrustCodes.rejectExpired)
        now = TestData.wStart - 30 * 86_400_000 // inside the validity window of F-EXPIRED
        XCTAssertEqual(s.importBundle(try TestData.bytes("fixtures/F-EXPIRED.zip")), TrustCodes.rejectUntrustedTime)
        XCTAssertEqual(s.load().state, BundleStore.stateTimeUntrusted)
        now = TestData.now
        XCTAssertEqual(s.load().state, BundleStore.stateValid)
        XCTAssertEqual(s.importBundle(try TestData.bytes("fixtures/F-NOT-YET-VALID.zip")), TrustCodes.rejectNotYetValid)
    }

    func testQrFixturesGetTheirExactOutcomeAndNeverAPose() throws {
        let store = try TestData.trust()
        let bundle = try StoredZip.read(try TestData.bytes("bundle/G1SYN-1.0.0.zip"))
        let anchors = try QrValidator.parseAnchors(bundle["qr_identities.json"]!)
        let fx = try TestData.object("oracle/qr_fixtures.json")["fixtures"] as! [[String: Any]]
        XCTAssertFalse(fx.isEmpty)
        for f in fx {
            let o = QrValidator.validate(f["payload"] as? String, store: store, anchors: anchors, activeVersion: "G1SYN-1.0.0", nowMs: TestData.now, timeTrusted: true)
            let expected = f["expected"] as! [String: Any]
            XCTAssertEqual(o.code, expected["outcome"] as? String, f["id"] as? String ?? "?")
            if let anchor = expected["anchor"] as? String { XCTAssertEqual(o.anchor?.id, anchor) }
            let json = try Json.parseObject(Data(o.toJson().utf8))
            XCTAssertEqual(json["pose_established"] as? Bool, false)
        }
        let first = fx[0]["payload"] as? String
        XCTAssertEqual(QrValidator.validate(first, store: store, anchors: anchors, activeVersion: "G1SYN-1.0.0", nowMs: TestData.now, timeTrusted: false).code, TrustCodes.rejectUntrustedTime)
        XCTAssertEqual(QrValidator.validate(first, store: store, anchors: anchors, activeVersion: "G1SYN-1.0.1", nowMs: TestData.now, timeTrusted: true).code, TrustCodes.rejectBundleMismatch)
        let big = "G1SYN:" + String(repeating: "A", count: QrValidator.maxPayloadBytes)
        XCTAssertEqual(QrValidator.validate(big, store: store, anchors: anchors, activeVersion: "G1SYN-1.0.0", nowMs: TestData.now, timeTrusted: true).code, TrustCodes.rejectMalformed)
    }

    func testStrictEncodings() {
        XCTAssertNil(Hex.fromBase64Url("abc="))
        XCTAssertNil(Hex.fromBase64Url("ab+c"))
        XCTAssertNil(Hex.fromBase64Url("A"))
        XCTAssertEqual(Hex.fromBase64Url("AQID")?.count, 3)
        XCTAssertNil(IsoTime.parseExtended("2026-02-30T00:00:00Z"))
        XCTAssertNil(IsoTime.parseBasic("20261301T000000Z"))
        XCTAssertEqual(IsoTime.parseBasic("20261001T000000Z"), TestData.wStart)
        XCTAssertEqual(G1Trace.encode("a b/\u{0628}~*"), "a+b%2F%D8%A8%7E*")
    }

    func testEchoWorkloadReturnsLengthAndCrc() {
        // CRC-32 of "123456789" is cbf43926 (check value of the standard polynomial)
        let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: Echo.maxPayload, alignment: 16)
        defer { buffer.deallocate() }
        let r = Echo.into(buffer, Data("123456789".utf8))
        XCTAssertEqual(r >> 32, 9)
        XCTAssertEqual(r & 0xFFFF_FFFF, 0xCBF4_3926)
        XCTAssertEqual(BridgeWorker.payloadBlock().count, 65_536)
        XCTAssertEqual(Hex.sha256(BridgeWorker.payloadBlock().prefix(32)), Hex.sha256(Data(Hex.sha256Bytes(Data("G1-SYNTH|2026091401|bridge-payload|0".utf8)))))
    }

    func testLabCommandsAreRegisteredBoundedJsonObjects() {
        XCTAssertNotNil(LabCommand.make("bundle.rollback", nil))
        XCTAssertNil(LabCommand.make("shell.exec", "{}"))
        XCTAssertNil(LabCommand.make("lang.set", "[1]"))
        XCTAssertNil(LabCommand.make("lang.set", "{\"lang\":\"" + String(repeating: "x", count: LabCommand.maxArgsChars) + "\"}"))
        XCTAssertEqual(LabCommand.fromLaunchArguments(["app", "-g1.cmd", "lang.set", "-g1.args", "{\"lang\":\"en\"}"])?.name, "lang.set")
        XCTAssertNil(LabCommand.fromLaunchArguments(["app", "-g1.cmd", "lang.set"]), "launch arguments are consumed once per process")
        XCTAssertEqual(LabCommand.fromURL(URL(string: "g1bench-c://cmd?name=nav.home&args=%7B%7D")!)?.name, "nav.home")
        XCTAssertFalse(G1Files.safeName("../x"))
        XCTAssertTrue(G1Files.safeName("A01.png"))
    }
}
