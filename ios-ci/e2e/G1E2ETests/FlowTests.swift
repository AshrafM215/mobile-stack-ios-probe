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

    /// Records that a flow state was reached (the element tree of the state is in the log). No screenshot on the
    /// passing path: a hosted simulator under load can time out a screenshot request, which XCTest records as a test
    /// failure unrelated to the candidate (probe v1-h, candidate A); the simctl READY screenshot is the visual record.
    private func record(_ a: XCUIApplication, _ name: String) {
        print("G1_E2E state=\(name)")
    }

    /// Failure diagnostics only: a screenshot attachment (its own timeout cannot hide the recorded failure).
    private func attach(_ a: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: a.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Fails the test with the element tree printed and a screenshot attached (diagnostics on the hosted runner).
    private func check(_ a: XCUIApplication, _ ok: Bool, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        if !ok {
            print("G1_E2E failure: \(message)\n\(a.debugDescription)")
            attach(a, "failure-\(message)")
        }
        XCTAssertTrue(ok, message, file: file, line: line)
    }

    private func waitFor(_ e: XCUIElement, _ predicate: String, timeout: TimeInterval) -> Bool {
        let x = XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate), object: e)
        return XCTWaiter.wait(for: [x], timeout: timeout) == .completed
    }

    /// READY as seen from the UI: the trusted-data line names the bundle version and the search field is shown.
    private func launchReady(_ arguments: [String] = []) -> XCUIApplication {
        let a = app(arguments)
        a.launch()
        check(a, el(a, "home.title").waitForExistence(timeout: 120), "home.title")
        check(a, el(a, "home.search.field").waitForExistence(timeout: 60), "home.search.field")
        check(a, waitFor(el(a, "home.trust"), "label CONTAINS 'G1SYN-1.0.0'", timeout: 90), "trusted bundle")
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

    /// Types one character per typeText call: XCUITest waits for the app to idle between calls, so the pace is that of
    /// a person typing and does not depend on how fast the runner can synthesize a burst of key events.
    private func typePaced(_ field: XCUIElement, _ text: String) {
        for character in text { field.typeText(String(character)) }
    }

    /// Recorded, not asserted (like the accessibility audit): the whole query typed as one burst of synthesized key
    /// events, first in the suite and therefore the first keyboard use on the simulator. A candidate whose text field
    /// loses characters under such a burst shows it here (value and match are in the log and in an attachment); the
    /// flow test types at a person's pace.
    func test0BurstTypingIsRecorded() throws {
        let a = launchReady()
        let field = el(a, "home.search.field")
        field.tap()
        field.typeText("SB1-F1-R001")
        sleep(2)
        let value = field.value as? String ?? ""
        let line = "burst_typing value=\(value) expected=SB1-F1-R001 match=\(value == "SB1-F1-R001")"
        let report = XCTAttachment(string: line)
        report.name = "burst-typing"
        report.lifetime = .keepAlways
        add(report)
        print("G1_E2E \(line)")
    }

    func test1SearchDetailsRouteAndArFallback() throws {
        let a = launchReady()
        record(a, "ready")
        let field = el(a, "home.search.field")
        field.tap()
        typePaced(field, "SB1-F1-R001")
        el(a, "home.search.submit").tap()
        check(a, el(a, "home.result.D001").waitForExistence(timeout: 30), "unique result D001")
        check(a, el(a, "home.results.status").exists, "results status")
        record(a, "results")
        el(a, "home.result.D001").tap()
        check(a, el(a, "details.code").waitForExistence(timeout: 30), "details")
        check(a, waitFor(el(a, "details.code"), "label == 'SB1-F1-R001'", timeout: 10), "details.code value")
        check(a, scrollTo(a, "details.schedule.item.SYN-COURSE-001").exists, "schedule item")
        record(a, "details")
        scrollTo(a, "details.route").tap()
        check(a, el(a, "route.compute").waitForExistence(timeout: 30), "route screen")
        el(a, "route.compute").tap()
        check(a, scrollTo(a, "route.summary").waitForExistence(timeout: 30), "route summary")
        check(a, scrollTo(a, "route.step.0").exists, "first step")
        record(a, "route")
        scrollTo(a, "route.ar").tap()
        check(a, el(a, "fallback.title").waitForExistence(timeout: 30), "text fallback (no ARKit world tracking on the simulator)")
        check(a, el(a, "fallback.message").exists, "fallback message")
        record(a, "fallback")
        scrollTo(a, "fallback.back").tap()
        check(a, el(a, "route.back").waitForExistence(timeout: 20), "back to route")
        el(a, "route.back").tap()
        check(a, el(a, "details.back").waitForExistence(timeout: 20), "back to details")
        el(a, "details.back").tap()
        check(a, el(a, "home.result.D001").waitForExistence(timeout: 20), "home keeps the results")
        // T14: the language switch keeps the state (results stay on screen)
        let before = el(a, "home.title").label
        el(a, "home.lang").tap()
        check(a, waitFor(el(a, "home.title"), "label != '\(before)'", timeout: 20), "title language changed")
        check(a, el(a, "home.result.D001").exists, "results kept after the language switch")
        record(a, "language-switched")
        el(a, "home.lang").tap()
        check(a, waitFor(el(a, "home.title"), "label == '\(before)'", timeout: 20), "title language restored")
    }

    func test2LargestAccessibilityTextSize() throws {
        let a = launchReady(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        check(a, el(a, "home.search.submit").exists, "search button at the largest text size")
        record(a, "largest-text")
    }

    /// Recorded, not asserted: every issue of the platform's accessibility audit of the home screen with what identifies
    /// its element (audit type, descriptions, identifier, element type, label, frame), and the element tree of the
    /// audited screen in the log.
    func test3AccessibilityAuditIsRecorded() throws {
        let a = launchReady()
        print("G1_E2E audit_tree_begin\n\(a.debugDescription)\nG1_E2E audit_tree_end")
        var issues: [String] = []
        try a.performAccessibilityAudit { issue in
            var element = "element=none"
            if let e = issue.element, e.exists {
                let f = e.frame
                element = "id=\(e.identifier) kind=\(e.elementType.rawValue) label=\(e.label) " +
                    "frame=\(Int(f.minX)),\(Int(f.minY)),\(Int(f.width))x\(Int(f.height))"
            }
            issues.append("type=\(issue.auditType.rawValue) \(issue.compactDescription) | \(issue.detailedDescription) | \(element)")
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
        check(a, el(a, "qr.result").waitForExistence(timeout: 30), "anchor-code result screen")
        check(a, !el(a, "qr.result").label.contains("["), "result text resolved")
        record(a, "qr-result")
        el(a, "qr.close").tap()
        check(a, el(a, "home.search.field").waitForExistence(timeout: 20), "back home")
    }
}
