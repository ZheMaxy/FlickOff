import AppKit
import Foundation
import Testing
import TBPrivate
@testable import TouchBarKit

private let hardwareTestsEnabled = ProcessInfo.processInfo.environment["TB_HARDWARE_TESTS"] == "1"
private let appIsRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: "io.github.ZheMaxy.FlickOff").isEmpty

/// Runs against the private frameworks of the macOS the tests run on; no Touch Bar needed.
@Suite("Private API contract", .enabled(if: ProcessInfo.processInfo.environment["TB_API_TESTS"] == "1" || hardwareTestsEnabled, "set TB_API_TESTS=1 to check this macOS private API"))
@MainActor
struct PrivateAPITests {
    @Test func everyPrivateClassAndSelectorExists() {
        #expect(TBTouchBar.missingAPIs() == [])
    }
}

/// Needs a real Touch Bar and changes its state (restored afterwards):
///   TB_HARDWARE_TESTS=1 swift test --filter Hardware
@Suite(
    "Hardware",
    .serialized,
    .enabled(if: hardwareTestsEnabled, "set TB_HARDWARE_TESTS=1 to run on a Mac with a Touch Bar"),
    .disabled(if: appIsRunning, "quit FlickOff.app first: it re-applies its own settings")
)
@MainActor
struct HardwareTests {
    @Test func selfTestPasses() {
        let report = CompatibilityReport.run()
        #expect(report.isSupported, "\(report.text(appVersion: "tests"))")
    }

    @Test func brightnessRoundTrip() throws {
        let tb = try #require(TBTouchBar.connect())
        let savedAuto = tb.autoBrightness, savedLevel = tb.brightness
        defer {
            tb.setBrightness(savedLevel)
            tb.setAutoBrightness(savedAuto)
        }

        tb.setAutoBrightness(false)
        #expect(!tb.autoBrightness)
        for level: Float in [0.5, 0.8] {
            tb.setBrightness(level)
            #expect(abs(tb.brightness - level) < 0.02, "set \(level), read \(tb.brightness)")
        }
        tb.setAutoBrightness(true)
        #expect(tb.autoBrightness)
    }

    @Test func panelOffAndOn() throws {
        let tb = try #require(TBTouchBar.connect())
        defer { tb.turnOn(); tb.undim() }

        #expect(tb.turnOff())
        #expect(waitFor { tb.panelState == .off }, "panel did not report off")
        #expect(tb.turnOff(), "turning off a dark panel must not read as a refusal")
        #expect(tb.turnOn())
        #expect(tb.undim())
        #expect(waitFor { tb.panelState == .on }, "panel did not report on")
        #expect(tb.turnOn(), "turning on a lit panel must not read as a refusal")
        #expect(tb.undim(), "undimming an undimmed panel must not read as a refusal")
    }

    @Test func brightnessSettingsAreReadable() throws {
        let tb = try #require(TBTouchBar.connect())
        let state = try #require(tb.brightnessState)
        #expect(state.auto == tb.autoBrightness)
        #expect(abs(state.level - tb.brightness) < 0.02)
    }

    @Test func thisSessionOwnsTheConsole() {
        #expect(LiveSystemState().isSessionActive)
    }

    @Test func idleTimeIsReadable() {
        let seconds = LiveSystemState().secondsSinceLastInput
        #expect(seconds.isFinite && seconds >= 0)
    }

    @Test(arguments: ProbeKind.allCases)
    func probeRunsAndPutsEverythingBack(kind: ProbeKind) async throws {
        let tb = try #require(TBTouchBar.connect())
        let before = (auto: tb.autoBrightness, level: tb.brightness)
        let outcome = await ProbeRunner(driver: LiveProbeDriver()).perform(kind)
        #expect(outcome == .awaitingAnswer)
        #expect(waitFor { tb.panelState == .on }, "panel left off")
        tb.undim()
        #expect(tb.autoBrightness == before.auto)
        if !before.auto { #expect(abs(tb.brightness - before.level) < 0.02, "level \(tb.brightness), was \(before.level)") }
    }

    private func waitFor(_ condition: () -> Bool) -> Bool {
        for _ in 0..<20 {
            if condition() { return true }
            usleep(100_000)
        }
        return condition()
    }
}
