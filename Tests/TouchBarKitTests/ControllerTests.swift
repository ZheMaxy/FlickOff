import Foundation
import Testing
@testable import TouchBarKit

@Suite("Settings")
@MainActor
struct SettingsTests {
    @Test func firstLaunchDefaultsToManualMaxWithoutDimming() {
        let c = Harness().makeController()
        #expect(c.mode == .manual)
        #expect(c.level == 1.0)
        #expect(c.preventDimming)
    }

    @Test func restoresSavedSettings() {
        let h = Harness(settings: ["mode": "auto", "level": 0.4, "preventDimming": false])
        let c = h.makeController()
        #expect(c.mode == .auto)
        #expect(c.level == 0.4)
        #expect(!c.preventDimming)
    }

    @Test func unknownSavedModeFallsBackToManual() {
        let c = Harness(settings: ["mode": "disco"]).makeController()
        #expect(c.mode == .manual)
    }

    @Test func persistsChanges() {
        let h = Harness()
        let c = h.makeController()
        c.mode = .off
        c.level = 0.25
        c.preventDimming = false
        #expect(h.defaults.string(forKey: "mode") == "off")
        #expect(h.defaults.double(forKey: "level") == 0.25)
        #expect(h.defaults.object(forKey: "preventDimming") as? Bool == false)
    }

    @Test(arguments: [(0.0, 12), (0.5, 185), (1.0, 357)])
    func levelMapsLinearlyToNits(level: Double, nits: Int) {
        let c = Harness(settings: ["level": level]).makeController()
        #expect(c.levelNits == nits)
    }
}

@Suite("Brightness")
@MainActor
struct BrightnessTests {
    @Test func manualModeTurnsAutoOffAndAppliesLevel() {
        let h = Harness(settings: ["level": 0.6])
        let c = h.makeController()
        c.applySettings()
        #expect(!h.touchBar.autoBrightness)
        #expect(h.touchBar.brightness == 0.6)
    }

    @Test func manualModeDoesNotRewriteAnUnchangedLevel() {
        // corebrightnessd reads 1.0 back as 0.9909; that must not count as drift.
        let h = Harness()
        let c = h.makeController()
        c.applySettings()
        h.touchBar.resetCalls()
        c.applySettings()
        #expect(h.touchBar.calls.isEmpty)
    }

    @Test func manualModeRestoresLevelAfterExternalReset() {
        let h = Harness(settings: ["level": 0.8])
        let c = h.makeController()
        c.applySettings()
        h.touchBar.autoBrightness = true // e.g. after a reboot
        h.touchBar.brightness = 0.1
        c.applySettings()
        #expect(!h.touchBar.autoBrightness)
        #expect(h.touchBar.brightness == 0.8)
    }

    @Test func autoModeOnlyEnablesAutoBrightness() {
        let h = Harness(settings: ["mode": "auto"])
        h.touchBar.autoBrightness = false
        let c = h.makeController()
        c.applySettings()
        #expect(h.touchBar.calls == ["auto=true"])
    }

    @Test func sliderAppliesImmediatelyOnlyInManualMode() {
        let h = Harness()
        let c = h.makeController()
        c.level = 0.25
        #expect(h.touchBar.brightness == 0.25)

        c.mode = .auto
        h.touchBar.resetCalls()
        c.level = 0.7
        #expect(!h.touchBar.calls.contains { $0.hasPrefix("brightness") })
    }
}

@Suite("Panel state")
@MainActor
struct PanelStateTests {
    @Test func offModeTurnsThePanelOff() {
        let h = Harness(settings: ["mode": "off"])
        let c = h.makeController()
        c.tick()
        #expect(h.touchBar.panelState == .off)
        #expect(!h.touchBar.calls.contains("on"))
    }

    @Test func offModeTurnsThePanelBackOffWhenTouchBarServerWakesIt() {
        let h = Harness(settings: ["mode": "off"])
        let c = h.makeController()
        c.start()
        h.touchBar.resetCalls()
        h.touchBar.simulatePanelStateChange(to: .on)
        #expect(h.touchBar.calls == ["off"])
    }

    @Test func leavingOffModeTurnsThePanelOn() {
        let h = Harness(settings: ["mode": "off"])
        let c = h.makeController()
        c.tick()
        c.mode = .manual
        #expect(h.touchBar.panelState == .on)
        #expect(h.touchBar.calls.contains("undim"))
    }

    @Test func undoesIdleDimming() {
        let h = Harness()
        let c = h.makeController()
        h.touchBar.dimmingStep = 2
        c.tick()
        #expect(h.touchBar.dimmingStep == 0)
    }

    @Test func turnsThePanelBackOnAfterIdlePowerOff() {
        let h = Harness()
        let c = h.makeController()
        h.touchBar.panelState = .off
        c.tick()
        #expect(h.touchBar.panelState == .on)
    }

    @Test func leavesIdleDimmingAloneWhenDisabled() {
        let h = Harness(settings: ["preventDimming": false])
        let c = h.makeController()
        h.touchBar.dimmingStep = 1
        h.touchBar.panelState = .off
        c.tick()
        #expect(h.touchBar.calls.isEmpty)
    }

    enum DarkReason: String, CaseIterable {
        case lidClosed, builtInDisplayAsleep, screenLocked, systemAsleep
    }

    @Test(arguments: DarkReason.allCases)
    func neverLightsThePanelWhenItMustStayDark(reason: DarkReason) {
        let h = Harness()
        let c = h.makeController()
        switch reason {
        case .lidClosed: h.system.isLidClosed = true
        case .builtInDisplayAsleep: h.system.isBuiltInDisplayAsleep = true
        case .screenLocked: h.system.isScreenLocked = true
        case .systemAsleep: c.systemWillSleep()
        }
        h.touchBar.panelState = .off
        h.touchBar.dimmingStep = 1
        c.tick()
        #expect(!h.touchBar.calls.contains("on"))
        #expect(!h.touchBar.calls.contains("undim"))
    }

    @Test func wakeReappliesSettingsAndLightsThePanel() {
        let h = Harness()
        let c = h.makeController()
        c.systemWillSleep()
        h.touchBar.panelState = .off
        h.touchBar.autoBrightness = true
        c.systemDidWake()
        #expect(!h.touchBar.autoBrightness)
        #expect(h.touchBar.panelState == .on)
    }

    @Test func quitInOffModeLeavesThePanelOn() {
        let h = Harness(settings: ["mode": "off"])
        let c = h.makeController()
        c.tick()
        c.prepareForQuit()
        #expect(h.touchBar.panelState == .on)
    }

    @Test func quitInManualModeTouchesNothing() {
        let h = Harness()
        let c = h.makeController()
        c.prepareForQuit()
        #expect(h.touchBar.calls.isEmpty)
    }
}

@Suite("Login item")
@MainActor
struct LoginItemTests {
    @Test func registersOnlyOnFirstLaunch() {
        let h = Harness()
        let first = h.makeController()
        first.configureLoginItemOnFirstLaunch()
        #expect(h.loginItem.registerCount == 1)
        #expect(first.launchAtLogin)

        // The user turned it off; a relaunch must not turn it back on.
        h.makeController().setLaunchAtLogin(false)
        let relaunched = h.makeController()
        relaunched.configureLoginItemOnFirstLaunch()
        #expect(h.loginItem.registerCount == 1)
        #expect(!relaunched.launchAtLogin)
    }

    @Test func showsApprovalHint() {
        let h = Harness()
        h.loginItem.status = .requiresApproval
        let c = h.makeController()
        c.refreshLoginStatus()
        #expect(c.launchAtLogin)
        #expect(c.loginNeedsApproval)
    }

    @Test func failedRegistrationKeepsTheToggleOff() {
        let h = Harness()
        h.loginItem.failNextCall = true
        let c = h.makeController()
        c.setLaunchAtLogin(true)
        #expect(!c.launchAtLogin)
    }
}

@Suite("Unsupported system")
@MainActor
struct UnsupportedSystemTests {
    @Test(arguments: ["api", "touchBar", "control"])
    func failedCheckDisablesAllControl(failedCheck: String) {
        let h = Harness(settings: ["mode": "off"])
        let c = h.makeController(compatibility: .failing(at: failedCheck))
        #expect(c.touchBar == nil)

        c.start()
        c.tick()
        c.applySettings()
        c.mode = .manual
        c.level = 0.3
        c.prepareForQuit()
        #expect(h.touchBar.calls.isEmpty)
    }
}

@Suite("Review regressions")
@MainActor
struct ReviewRegressionTests {
    @Test(arguments: [-1.0, 2.0, Double.nan, .infinity, -.infinity])
    func savedBrightnessIsValidated(value: Double) {
        let c = Harness(settings: ["level": value]).makeController()
        #expect(c.level.isFinite)
        #expect((0...1).contains(c.level))
        #expect((0...1_000).contains(c.levelNits))
    }

    @Test(arguments: [-1.0, 2.0, Double.nan, .infinity, -.infinity])
    func brightnessAssignmentsAreValidated(value: Double) {
        let h = Harness()
        let c = h.makeController()
        c.level = value
        #expect(c.level.isFinite)
        #expect((0...1).contains(c.level))
        #expect(h.defaults.double(forKey: "level") == c.level)
        #expect(h.touchBar.brightness.isFinite)
        #expect((0...1).contains(h.touchBar.brightness))
    }

    @Test(arguments: PanelStateTests.DarkReason.allCases)
    func leavingOffOrQuittingDoesNotWakeADarkMac(reason: PanelStateTests.DarkReason) {
        let h = Harness(settings: ["mode": "off"])
        let c = h.makeController()
        switch reason {
        case .lidClosed: h.system.isLidClosed = true
        case .builtInDisplayAsleep: h.system.isBuiltInDisplayAsleep = true
        case .screenLocked: h.system.isScreenLocked = true
        case .systemAsleep: c.systemWillSleep()
        }
        c.tick()
        h.touchBar.resetCalls()
        c.mode = .manual
        #expect(!h.touchBar.calls.contains("on"))
        #expect(!h.touchBar.calls.contains("undim"))
        c.mode = .off
        h.touchBar.resetCalls()
        c.prepareForQuit()
        #expect(!h.touchBar.calls.contains("on"))
        #expect(!h.touchBar.calls.contains("undim"))
    }

    @Test func everySettingRespectsTheDiagnosticsPause() {
        let h = Harness(settings: ["mode": "off"])
        let c = h.makeController()
        c.enforcementPaused = true
        c.mode = .manual
        c.level = 0.4
        c.preventDimming = false
        #expect(h.touchBar.calls.isEmpty)
    }

    @Test func restoresOriginalBrightnessOnQuitAndIgnoresLateCallbacks() {
        let h = Harness()
        h.touchBar.autoBrightness = false
        h.touchBar.brightness = 0.45
        let c = h.makeController()
        c.start()
        c.prepareForQuit()
        #expect(!h.touchBar.autoBrightness)
        #expect(h.touchBar.brightness == 0.45)
        h.touchBar.resetCalls()
        h.touchBar.simulatePanelStateChange(to: .off)
        c.tick()
        #expect(h.touchBar.calls.isEmpty)
    }

    @Test func restoresOriginalAutoBrightnessOnQuit() {
        let h = Harness()
        let c = h.makeController()
        c.start()
        #expect(!h.touchBar.autoBrightness)
        c.prepareForQuit()
        #expect(h.touchBar.autoBrightness)
    }

    @Test func repeatedStartDoesNotReplaceTheOriginalSettings() {
        let h = Harness()
        let c = h.makeController()
        c.start()
        c.start()
        c.prepareForQuit()
        #expect(h.touchBar.autoBrightness)
    }

    @Test(arguments: [Float.nan, .infinity, -.infinity, -1])
    func invalidTelemetryDoesNotReachTheInterface(value: Float) {
        let h = Harness()
        h.touchBar.physicalNits = value
        let c = h.makeController()
        c.tick()
        c.tick()
        #expect(c.physicalNits == 0)
    }

    @Test func explicitLoginChoiceSurvivesMovingToApplications() {
        let h = Harness()
        h.makeController(bundlePath: SetupTests.downloads).setLaunchAtLogin(false)
        h.makeController().configureLoginItemOnFirstLaunch()
        #expect(h.loginItem.registerCount == 0)
    }
    @Test func refusedAutoWriteDoesNotApplyAManualLevel() {
        let h = Harness()
        h.touchBar.autoWritesSucceed = false
        let c = h.makeController()
        c.applySettings()
        #expect(c.controlFailed)
        #expect(h.touchBar.calls == ["auto=false"])
        h.touchBar.autoWritesSucceed = true
        c.applySettings()
        #expect(!c.controlFailed)
    }

    @Test func refusedSliderWriteIsReported() {
        let h = Harness()
        let c = h.makeController()
        h.touchBar.brightnessWritesSucceed = false
        c.level = 0.7
        #expect(c.controlFailed)
    }

    @Test(arguments: [Float.nan, .infinity, -1, Float.greatestFiniteMagnitude])
    func invalidLuminanceRangeCannotCrashTheInterface(value: Float) {
        let h = Harness()
        h.touchBar.maxNits = value
        #expect(h.makeController().levelNits == 0)
    }

    @Test func startedControllerIsReleasedWithoutExplicitStop() {
        let h = Harness()
        weak var released: Controller?
        do {
            let c = h.makeController()
            released = c
            c.start()
        }
        #expect(released == nil)
    }

}
