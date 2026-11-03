import Foundation
import IOKit
import Testing
@testable import TouchBarKit

@MainActor
final class FakeProbeDriver: ProbeDriving {
    var brightness: (auto: Bool, level: Float)? = (auto: false, level: 0.6)
    var refuse: Set<String> = []
    private(set) var calls: [String] = []

    private func record(_ call: String) -> Bool {
        calls.append(call)
        return !refuse.contains(call)
    }

    func panelTurnOff() -> Bool { record("off") }
    func panelTurnOn() -> Bool { record("on") }
    func setDimmingCoefficient(_ coefficient: Float) -> Bool { record("coef=\(coefficient)") }
    func readBrightness() -> (auto: Bool, level: Float)? { calls.append("read"); return brightness }
    func writeBrightness(auto: Bool, level: Float?) -> Bool { record("write auto=\(auto) level=\(level.map { "\($0)" } ?? "-")") }
}

@MainActor
private func runner(_ driver: FakeProbeDriver) -> ProbeRunner {
    ProbeRunner(driver: driver, pause: { _ in })
}

@Suite("Probes")
@MainActor
struct ProbeTests {
    @Test func panelOffOnTurnsBackOn() async {
        let d = FakeProbeDriver()
        #expect(await runner(d).perform(.panelOffOn) == .awaitingAnswer)
        #expect(d.calls == ["off", "on"])
    }

    @Test func panelIsTurnedOnEvenIfTurnOffWasRefused() async {
        let d = FakeProbeDriver()
        d.refuse = ["off"]
        #expect(await runner(d).perform(.panelOffOn) == .callsFailed("turnOff"))
        #expect(d.calls.last == "on")
    }

    @Test func turnOnIsRetriedOnce() async {
        let d = FakeProbeDriver()
        d.refuse = ["on"]
        #expect(await runner(d).perform(.panelOffOn) == .callsFailed("turnOn"))
        #expect(d.calls == ["off", "on", "on"])
    }

    @Test func brightnessProbeRestoresAManualLevel() async {
        let d = FakeProbeDriver()
        #expect(await runner(d).perform(.coreBrightnessLevel) == .awaitingAnswer)
        #expect(d.calls == ["read", "write auto=false level=0.1", "write auto=false level=1.0", "write auto=false level=0.6"])
    }

    @Test func brightnessProbeRestoresAutoBrightness() async {
        let d = FakeProbeDriver()
        d.brightness = (auto: true, level: 0.2)
        _ = await runner(d).perform(.coreBrightnessLevel)
        #expect(d.calls.last == "write auto=true level=-")
    }

    @Test func brightnessProbeRestoresEvenWhenAWriteFails() async {
        let d = FakeProbeDriver()
        d.refuse = ["write auto=false level=0.1"]
        #expect(await runner(d).perform(.coreBrightnessLevel) == .callsFailed("DisplayBrightness write"))
        #expect(d.calls.last == "write auto=false level=0.6")
    }

    @Test func brightnessProbeNeedsCoreBrightness() async {
        let d = FakeProbeDriver()
        d.brightness = nil
        #expect(await runner(d).perform(.coreBrightnessLevel) == .callsFailed("corebrightnessd has no Touch Bar brightness"))
        #expect(d.calls == ["read"])
    }

    @Test func coefficientProbeRestoresFullOutput() async {
        let d = FakeProbeDriver()
        #expect(await runner(d).perform(.dimmingCoefficient) == .awaitingAnswer)
        #expect(d.calls == ["coef=0.2", "coef=1.0"])
    }

    @Test func pausedControllerLeavesTheProbeAlone() {
        let h = Harness(settings: ["mode": "off"])
        let c = h.makeController()
        c.enforcementPaused = true
        h.touchBar.dimmingStep = 3
        c.tick()
        c.applySettings()
        #expect(h.touchBar.calls.isEmpty)
    }
    @Test func failedRestorationTakesPriorityOverAProbeWriteFailure() async {
        let d = FakeProbeDriver()
        d.refuse = ["write auto=false level=0.1", "write auto=false level=0.6"]
        #expect(await runner(d).perform(.coreBrightnessLevel) == .callsFailed("restoring the previous brightness"))
    }

    @Test func coefficientRestorationFailureIsReported() async {
        let d = FakeProbeDriver()
        d.refuse = ["coef=0.2", "coef=1.0"]
        #expect(await runner(d).perform(.dimmingCoefficient) == .callsFailed("restoring the coefficient"))
    }

    @Test(arguments: [Float.nan, .infinity, -1, 2])
    func invalidSavedBrightnessIsNeverWrittenBack(value: Float) async {
        let d = FakeProbeDriver()
        d.brightness = (auto: false, level: value)
        #expect(await runner(d).perform(.coreBrightnessLevel) == .callsFailed("invalid saved brightness"))
        #expect(d.calls == ["read"])
    }

}

@Suite("Diagnostics report")
@MainActor
struct DiagnosticsReportTests {
    @Test func reportListsProbesAndSections() {
        let report = DiagnosticsReport(
            compatibility: .supported,
            outcomes: [.panelOffOn: .answered(sawChange: true), .dimmingCoefficient: .callsFailed("dimToStep:withCoefficient:")],
            sections: [DiagnosticsSection(title: "Mac", text: "model: X")]
        )
        let text = report.text(appVersion: "1", system: SystemInfo(osVersion: "macOS 1.0 (A)", model: "X"))
        #expect(text.contains("panelOffOn: ran, user SAW the change"))
        #expect(text.contains("coreBrightnessLevel: not run"))
        #expect(text.contains("dimmingCoefficient: API refused: dimToStep:withCoefficient:"))
        #expect(text.contains("== Mac ==\nmodel: X"))
    }

    @Test func reportsNameTheSavedSettingsAndNothingElseFromPreferences() {
        let h = Harness(settings: ["mode": "off", "level": 0.358, "idleOffSeconds": 300, "unrelated": "private"])
        let section = Controller.savedSettingsSection(defaults: h.defaults)
        #expect(section.title == "FlickOff settings")
        #expect(section.text == "mode: off\nlevel: 36%\nwhen idle: turnOff(afterSeconds: 300)")
    }

    @Test func uuidsAreReplacedConsistently() {
        let text = DiagnosticsReport.redactIdentifiers("a 37D8832A-2D66-02CA-B9F7-8F30A301B230 b c7542cdb-cd3d-f549-c90b-a2661d91f570 c 37d8832a-2d66-02ca-b9f7-8f30a301b230")
        #expect(text == "a <uuid-1> b <uuid-2> c <uuid-1>")
    }

    @Test func snapshotOfThisMacHasNoUUIDs() {
        let text = DiagnosticsReport(compatibility: .supported, sections: DiagnosticsSection.collect()).text(appVersion: "1")
        #expect(text.range(of: "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}", options: .regularExpression) == nil)
    }

    @Test func snapshotOfThisMacHasEverySection() {
        let titles = DiagnosticsSection.collect().map(\.title)
        #expect(titles == ["Mac", "IORegistry", "Private classes", "corebrightnessd", "DFRBrightness"])
    }

    @Test func snapshotLeavesOutTheSerialNumber() throws {
        let expert = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        defer { IOObjectRelease(expert) }
        let serial = try #require(IORegistryEntryCreateCFProperty(expert, "IOPlatformSerialNumber" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String)
        let text = DiagnosticsReport(compatibility: .supported, sections: DiagnosticsSection.collect())
            .text(appVersion: "1")
        #expect(!text.contains(serial))
        #expect(!text.contains("IOPlatformSerialNumber"))
    }
}
