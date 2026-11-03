import Testing
@testable import TouchBarKit

@Suite("Compatibility report")
struct CompatibilityTests {
    @Test func allChecksPassedMeansSupported() {
        #expect(CompatibilityReport.supported.isSupported)
        #expect(CompatibilityReport.supported.problem == nil)
    }

    @Test func noChecksMeansUnsupported() {
        #expect(CompatibilityReport(checks: []).problem == .unsupportedOS)
    }

    @Test(arguments: [
        ("hardware", CompatibilityProblem.noTouchBar),
        ("frameworks", .unsupportedOS),
        ("api", .unsupportedOS),
        ("touchBar", .noTouchBar),
        ("corebrightnessd", .unsupportedOS),
        ("control", .controlDenied),
        ("touchBarServer", .unsupportedOS),
        ("exception", .unsupportedOS),
    ])
    func firstFailureDecidesTheMessage(failedCheck: String, problem: CompatibilityProblem) {
        let report = CompatibilityReport.failing(at: failedCheck)
        #expect(!report.isSupported)
        #expect(report.problem == problem)
    }

    @Test func missingHardwareWinsOverBrokenAPIs() {
        let report = CompatibilityReport(checks: [
            CompatibilityCheck(name: "hardware", passed: false, detail: "no Touch Bar"),
            CompatibilityCheck(name: "frameworks", passed: true, detail: "loaded"),
            CompatibilityCheck(name: "api", passed: false, detail: "missing DFRBrightnessClient"),
        ])
        #expect(report.problem == .noTouchBar)
    }

    @Test func reportTextListsEveryCheck() {
        let report = CompatibilityReport(checks: [
            CompatibilityCheck(name: "frameworks", passed: true, detail: "loaded"),
            CompatibilityCheck(name: "api", passed: false, detail: "missing DFRBrightnessClient -dimToStep:"),
        ])
        let text = report.text(appVersion: "1.2", system: SystemInfo(osVersion: "macOS 27.1 (26B10)", model: "MacBookPro17,1"))
        #expect(text == """
        FlickOff 1.2 compatibility report
        macOS 27.1 (26B10) · MacBookPro17,1

        [PASS] frameworks  loaded
        [FAIL] api         missing DFRBrightnessClient -dimToStep:

        Result: NOT supported (unsupportedOS)
        """)
    }

    @Test func currentSystemInfoIsFilledIn() {
        let info = SystemInfo.current
        #expect(info.osVersion.range(of: #"^macOS \d+\.\d+\.\d+ \(\w+\)$"#, options: .regularExpression) != nil, "\(info.osVersion)")
        #expect(!info.model.isEmpty)
    }
}
