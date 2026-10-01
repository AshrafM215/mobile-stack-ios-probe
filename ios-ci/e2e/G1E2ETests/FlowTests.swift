// Shared end-to-end UI flow (G1-CIC-1.0 ids) for the three iOS candidates - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// Drives an installed candidate app by bundle identifier (TEST_RUNNER_G1_BUNDLE_ID); the same flow runs for A, B and C.
// iOS Simulator: there is no ARKit world tracking, so "Open AR" must lead to the accessible text fallback (S09).
import XCTest

final class FlowTests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }
    private var bundleId = ""

    override func setUpWithError() throws {
        continueAfterFailure = false
        bundleId = try XCTUnwrap(env["G1_BUNDLE_ID"], "candidate bundle identifier (TEST_RUNNER_G1_BUNDLE_ID)")
    }

    private func app(_ arguments: [String] = []) -> XCUIApplication {
        let a = XCUIApplication(bundleIdentifier: bundleId)
        a.launchArguments = arguments
        return a
    }

    private func el(_ a: XCUIApplication, _ id: String) -> XCUIElement { a.descendants(matching: .any)[id].firstMatch }

    private func attach(_ a: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: a.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func waitFor(_ e: XCUIElement, _ predicate: String, timeout: TimeInterval) -> Bool {
        let x = XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate), object: e)
        return XCTWaiter.wait(for: [x], timeout: timeout) == .completed
    }

    /// READY as seen from the UI: the trusted-data line names the bundle version and the search field is shown.
    private func launchReady(_ arguments: [String] = []) -> XCUIApplication {
        let a = app(arguments)
        a.launch()
        XCTAssertTrue(el(a, "home.title").waitForExistence(timeout: 120), "home.title")
        XCTAssertTrue(el(a, "home.search.field").waitForExistence(timeout: 60), "home.search.field")
        XCTAssertTrue(waitFor(el(a, "home.trust"), "label CONTAINS 'G1SYN-1.0.0'", timeout: 90), "trusted bundle")
        return a
    }

    private func scrollTo(_ a: XCUIApplication, _ id: String) -> XCUIElement {
        let e = el(a, id)
        var n = 0
        while (!e.exists || !e.isHittable) && n < 8 {
            a.swipeUp()
            n += 1
        }
        return e
    }

    func test1SearchDetailsRouteAndArFallback() throws {
        let a = launchReady()
        attach(a, "ready")
        let field = el(a, "home.search.field")
        field.tap()
        field.typeText("SB1-F1-R001")
        el(a, "home.search.submit").tap()
        XCTAssertTrue(el(a, "home.result.D001").waitForExistence(timeout: 30), "unique result D001")
        XCTAssertTrue(el(a, "home.results.status").exists, "results status")
        attach(a, "results")
        el(a, "home.result.D001").tap()
        XCTAssertTrue(el(a, "details.code").waitForExistence(timeout: 30), "details")
        XCTAssertTrue(waitFor(el(a, "details.code"), "label == 'SB1-F1-R001'", timeout: 10), "details.code value")
        XCTAssertTrue(scrollTo(a, "details.schedule.item.SYN-COURSE-001").exists, "schedule item")
        attach(a, "details")
        scrollTo(a, "details.route").tap()
        XCTAssertTrue(el(a, "route.compute").waitForExistence(timeout: 30), "route screen")
        el(a, "route.compute").tap()
        XCTAssertTrue(scrollTo(a, "route.summary").waitForExistence(timeout: 30), "route summary")
        XCTAssertTrue(scrollTo(a, "route.step.0").exists, "first step")
        attach(a, "route")
        scrollTo(a, "route.ar").tap()
        XCTAssertTrue(el(a, "fallback.title").waitForExistence(timeout: 30), "text fallback (no ARKit world tracking on the simulator)")
        XCTAssertTrue(el(a, "fallback.message").exists, "fallback message")
        attach(a, "fallback")
        scrollTo(a, "fallback.back").tap()
        XCTAssertTrue(el(a, "route.back").waitForExistence(timeout: 20), "back to route")
        el(a, "route.back").tap()
        XCTAssertTrue(el(a, "details.back").waitForExistence(timeout: 20), "back to details")
        el(a, "details.back").tap()
        XCTAssertTrue(el(a, "home.result.D001").waitForExistence(timeout: 20), "home keeps the results")
        // T14: the language switch keeps the state (results stay on screen)
        let before = el(a, "home.title").label
        el(a, "home.lang").tap()
        XCTAssertTrue(waitFor(el(a, "home.title"), "label != '\(before)'", timeout: 20), "title language changed")
        XCTAssertTrue(el(a, "home.result.D001").exists, "results kept after the language switch")
        attach(a, "language-switched")
        el(a, "home.lang").tap()
        XCTAssertTrue(waitFor(el(a, "home.title"), "label == '\(before)'", timeout: 20), "title language restored")
    }

    func test2LargestAccessibilityTextSize() throws {
        let a = launchReady(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        XCTAssertTrue(el(a, "home.search.submit").exists, "search button at the largest text size")
        attach(a, "largest-text")
    }

    func test3AccessibilityAuditIsRecorded() throws {
        let a = launchReady()
        var issues: [String] = []
        try a.performAccessibilityAudit { issue in
            issues.append("\(issue.auditType.rawValue) \(issue.compactDescription) [\(issue.element?.identifier ?? "-")]")
            return true // recorded, not failed: the audit result is evidence for the accessibility criteria
        }
        let report = XCTAttachment(string: "issues=\(issues.count)\n" + issues.joined(separator: "\n"))
        report.name = "accessibility-audit"
        report.lifetime = .keepAlways
        add(report)
        print("G1_E2E a11y_audit_issues=\(issues.count)")
    }

    func test4InjectedQrThroughTheLabUrl() throws {
        let scheme = try XCTUnwrap(env["G1_URL_SCHEME"], "lab URL scheme (TEST_RUNNER_G1_URL_SCHEME)")
        let a = launchReady()
        let args = #"{"file":"A01.png"}"#.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        a.open(URL(string: "\(scheme)://cmd?name=qr.inject&args=\(args)")!)
        XCTAssertTrue(el(a, "qr.result").waitForExistence(timeout: 30), "anchor-code result screen")
        XCTAssertFalse(el(a, "qr.result").label.contains("["), "result text resolved")
        attach(a, "qr-result")
        el(a, "qr.close").tap()
        XCTAssertTrue(el(a, "home.search.field").waitForExistence(timeout: 20), "back home")
    }
}
