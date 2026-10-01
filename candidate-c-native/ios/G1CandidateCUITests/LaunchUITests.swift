// G1 candidate C (native iOS reference) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
import XCTest

final class LaunchUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testLaunchShowsMapAndARFallback() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["title"].waitForExistence(timeout: 60))
        let status = app.staticTexts["mapStatus"]
        let loaded = expectation(for: NSPredicate(format: "label CONTAINS 'style loaded'"), evaluatedWith: status)
        wait(for: [loaded], timeout: 90)
        app.buttons["checkAR"].tap()
        XCTAssertTrue(app.staticTexts["arStatus"].label.contains("unsupported"))
    }

    @available(iOS 17.0, *)
    func testAccessibilityAuditIsRecorded() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["title"].waitForExistence(timeout: 60))
        var issues: [String] = []
        try app.performAccessibilityAudit { issue in
            issues.append(issue.compactDescription)
            return true
        }
        print("G1_PROBE a11y_audit_issues=\(issues.count)")
        for issue in issues {
            print("G1_PROBE a11y_issue \(issue)")
        }
    }
}
