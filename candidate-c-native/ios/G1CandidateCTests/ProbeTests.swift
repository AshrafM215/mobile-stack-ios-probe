// G1 candidate C (native iOS reference) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
import XCTest
@testable import G1CandidateC

final class ProbeTests: XCTestCase {
    func testSyntheticStyleIsBundledAndValid() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "probe-style-v0", withExtension: "json"))
        let data = try Data(contentsOf: url)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["version"] as? Int, 8)
        let layers = try XCTUnwrap(json["layers"] as? [[String: Any]])
        XCTAssertEqual(layers.count, 4)
    }

    func testARCapabilityCheckAndFallback() {
        #if targetEnvironment(simulator)
        XCTAssertFalse(ARFeasibility.isSupported)
        XCTAssertTrue(ARFeasibility.describe().hasPrefix("unsupported"))
        #endif
        XCTAssertNotNil(ARFeasibility.makeSceneView())
    }
}
