// G1 common native module tests (iOS) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// The common Core Image decoder reads every synthetic QR image back to the exact generated payload (injected path).
#if canImport(CoreImage) && canImport(ImageIO)
import Foundation
import XCTest
@testable import G1NativeCommon

final class QrDecodeTests: XCTestCase {
    func testEverySyntheticQrImageDecodesToItsPayload() throws {
        let fx = try TestData.object("oracle/qr_fixtures.json")["fixtures"] as! [[String: Any]]
        XCTAssertEqual(fx.count, 25)
        for f in fx {
            let png = try TestData.bytes(f["png"] as! String)
            XCTAssertEqual(QrDecode.decodePng(png), f["payload"] as? String, f["id"] as? String ?? "?")
        }
        XCTAssertNil(QrDecode.decodePng(Data("not a png".utf8)))
    }
}
#endif
