import Foundation
import Testing
@testable import TouchBarKit

@Suite("Reconnecting after a failed launch check")
@MainActor
struct ReconnectTests {
    @Test func serviceThatComesUpAfterLoginIsPickedUp() {
        let h = Harness()
        var attempts = 0
        var serviceIsUp = false
        let c = h.makeController(compatibility: .failing(at: "control"), reconnect: {
            attempts += 1
            return serviceIsUp ? (h.touchBar, .supported) : (nil, .failing(at: "control"))
        })
        c.start()
        #expect(c.touchBar == nil)
        #expect(c.reconnectIsScheduled)

        c.reconnectTimerFired()
        #expect(attempts == 1)
        #expect(c.touchBar == nil)
        #expect(c.compatibility.problem == .controlDenied)

        serviceIsUp = true
        c.reconnectTimerFired()
        #expect(c.touchBar != nil)
        #expect(c.compatibility.isSupported)
        #expect(!c.reconnectIsScheduled)
        #expect(!h.touchBar.autoBrightness, "the saved Manual setting is applied as soon as it connects")
        c.prepareForQuit()
    }

    @Test func connectingLateStillRestoresTheBrightnessFoundThen() {
        let h = Harness()
        h.touchBar.autoBrightness = false
        h.touchBar.brightness = 0.45
        let c = h.makeController(compatibility: .failing(at: "corebrightnessd"), reconnect: { (h.touchBar, .supported) })
        c.start()
        c.reconnectTimerFired()
        c.prepareForQuit()
        #expect(!h.touchBar.autoBrightness)
        #expect(h.touchBar.brightness == 0.45)
    }

    @Test func givesUpAfterAboutAMinute() {
        let h = Harness()
        var attempts = 0
        let c = h.makeController(compatibility: .failing(at: "control"), reconnect: {
            attempts += 1
            return (nil, .failing(at: "control"))
        })
        c.start()
        for _ in 0..<(Controller.reconnectDelays.count + 3) where c.reconnectIsScheduled { c.reconnectTimerFired() }
        #expect(attempts == Controller.reconnectDelays.count)
        #expect(!c.reconnectIsScheduled)
        #expect(Controller.reconnectDelays.reduce(0, +) == 60)
        c.prepareForQuit()
    }

    @Test func wakingTheMacTriesAgainAfterGivingUp() {
        let h = Harness()
        var serviceIsUp = false
        let c = h.makeController(compatibility: .failing(at: "control"), reconnect: {
            serviceIsUp ? (h.touchBar, .supported) : (nil, .failing(at: "control"))
        })
        c.start()
        while c.reconnectIsScheduled { c.reconnectTimerFired() }

        serviceIsUp = true
        c.systemDidWake()
        #expect(c.touchBar != nil)
        c.prepareForQuit()
    }

    @Test(arguments: ["hardware", "frameworks", "api"])
    func failuresThatCannotHealAreNotRetried(failedCheck: String) {
        let h = Harness()
        var attempts = 0
        let c = h.makeController(compatibility: .failing(at: failedCheck), reconnect: {
            attempts += 1
            return (h.touchBar, .supported)
        })
        c.start()
        #expect(!c.reconnectIsScheduled)
        c.systemDidWake()
        #expect(attempts == 0)
        #expect(c.touchBar == nil)
        c.prepareForQuit()
    }

    @Test func aFailureThatTurnsPermanentStopsTheRetries() {
        let h = Harness()
        var attempts = 0
        let c = h.makeController(compatibility: .failing(at: "control"), reconnect: {
            attempts += 1
            return (nil, .failing(at: "api"))
        })
        c.start()
        c.reconnectTimerFired()
        #expect(attempts == 1)
        #expect(!c.reconnectIsScheduled)
        #expect(c.compatibility.problem == .unsupportedOS)
        c.prepareForQuit()
    }

    @Test func missingTouchBarOutranksARecoverableFailure() {
        let report = CompatibilityReport(checks: [
            CompatibilityCheck(name: "hardware", passed: false, detail: "no Touch Bar"),
            CompatibilityCheck(name: "control", passed: false, detail: "no display id"),
        ])
        #expect(!report.mayRecover)
        #expect(!CompatibilityReport.supported.mayRecover)
    }
}

@Suite("Unreadable brightness")
@MainActor
struct UnreadableBrightnessTests {
    @Test func noAnswerAtLaunchIsNotRestoredAsManualZero() {
        let h = Harness()
        h.touchBar.readsFail = true
        let c = h.makeController()
        c.start()
        c.prepareForQuit()
        #expect(h.touchBar.calls.isEmpty)
    }

    @Test func nothingIsWrittenUntilTheFirstAnswer() {
        let h = Harness()
        h.touchBar.readsFail = true
        let c = h.makeController()
        c.start()
        c.applySettings()
        c.level = 0.7
        #expect(!h.touchBar.calls.contains { $0.hasPrefix("brightness") || $0.hasPrefix("auto") })
        #expect(!c.controlFailed, "no answer isn't the same as a refused write")
        c.prepareForQuit()
    }

    @Test func theFirstAnswerBecomesTheBrightnessRestoredOnQuit() {
        let h = Harness(settings: ["level": 0.8])
        h.touchBar.autoBrightness = false
        h.touchBar.brightness = 0.45
        h.touchBar.readsFail = true
        let c = h.makeController()
        c.start()

        h.touchBar.readsFail = false
        c.applySettings()
        #expect(h.touchBar.brightness == 0.8)

        c.prepareForQuit()
        #expect(!h.touchBar.autoBrightness)
        #expect(h.touchBar.brightness == 0.45)
    }

    @Test func aDropoutAfterLaunchKeepsTheOriginalAndWritesNothing() {
        let h = Harness()
        let c = h.makeController()
        c.start()
        #expect(!h.touchBar.autoBrightness)

        h.touchBar.readsFail = true
        h.touchBar.resetCalls()
        c.applySettings()
        #expect(h.touchBar.calls.isEmpty)

        h.touchBar.readsFail = false
        c.prepareForQuit()
        #expect(h.touchBar.autoBrightness)
    }

    @Test(arguments: [Float.nan, .infinity, -1, 2])
    func invalidLevelsCountAsNoAnswer(value: Float) {
        let h = Harness()
        h.touchBar.autoBrightness = false
        h.touchBar.brightness = value
        let c = h.makeController()
        c.start()
        c.prepareForQuit()
        #expect(h.touchBar.calls.isEmpty)
    }
}

@Suite("Probes and quitting")
@MainActor
struct ProbeLifecycleTests {
    @Test func quittingDuringAProbeRunsItsRecovery() {
        let h = Harness()
        let c = h.makeController()
        c.start()
        var recovered: Bool?
        c.beginProbe { recovered = $0 }
        c.prepareForQuit()
        #expect(recovered == true)
    }

    @Test func recoveryIsToldNotToLightADarkMac() {
        let h = Harness()
        let c = h.makeController()
        c.start()
        var recovered: Bool?
        c.beginProbe { recovered = $0 }
        h.system.isLidClosed = true
        c.prepareForQuit()
        #expect(recovered == false)
    }

    @Test func aFinishedProbeHasNothingToRecover() {
        let h = Harness()
        let c = h.makeController()
        c.start()
        var ran = false
        c.beginProbe { _ in ran = true }
        c.endProbe()
        c.prepareForQuit()
        #expect(!ran)
    }

    @Test func aDarkPanelIsLitBeforeTheProbeAndDarkAgainAfterIt() {
        let h = Harness(settings: ["mode": "off"])
        let c = h.makeController()
        c.start()
        #expect(h.touchBar.panelState == .off)

        #expect(c.beginProbe { _ in })
        #expect(h.touchBar.panelState == .on)

        c.endProbe()
        #expect(h.touchBar.panelState == .off)
        c.prepareForQuit()
    }

    @Test func aLitPanelNeedsNoPreparation() {
        let h = Harness()
        let c = h.makeController()
        c.start()
        h.touchBar.resetCalls()
        #expect(!c.beginProbe { _ in })
        #expect(h.touchBar.calls.isEmpty)
        c.prepareForQuit()
    }

    @Test func aProbeDoesNotLightALockedMac() {
        let h = Harness(settings: ["mode": "off"])
        let c = h.makeController()
        c.start()
        h.system.isScreenLocked = true
        #expect(!c.beginProbe { _ in })
        #expect(h.touchBar.panelState == .off)
        c.prepareForQuit()
    }

    @Test func recoveryOfEachProbe() {
        let lit = FakeProbeDriver()
        let runner = ProbeRunner(driver: lit, pause: { _ in })
        runner.recover(from: .panelOffOn, panelMayLight: true)
        runner.recover(from: .dimmingCoefficient, panelMayLight: true)
        runner.recover(from: .coreBrightnessLevel, panelMayLight: true)
        #expect(lit.calls == ["on", "coef=1.0"])

        let dark = FakeProbeDriver()
        let darkRunner = ProbeRunner(driver: dark, pause: { _ in })
        darkRunner.recover(from: .panelOffOn, panelMayLight: false)
        darkRunner.recover(from: .dimmingCoefficient, panelMayLight: false)
        #expect(dark.calls == ["coef=1.0"])
    }
}

@Suite("Refused panel calls")
@MainActor
struct PanelRefusalTests {
    private func refusals(_ c: Controller, _ count: Int = Controller.refusalsBeforeWarning) {
        for _ in 0..<count { c.tick() }
    }

    @Test func offModeWarnsWhenTurnOffKeepsBeingRefused() {
        let h = Harness(settings: ["mode": "off"])
        h.touchBar.panelWritesSucceed = false
        let c = h.makeController()
        refusals(c, Controller.refusalsBeforeWarning - 1)
        #expect(!c.panelControlFailed, "one bad moment isn't a problem worth showing")
        refusals(c, 1)
        #expect(c.panelControlFailed)

        h.touchBar.panelWritesSucceed = true
        c.tick()
        #expect(!c.panelControlFailed)
    }

    @Test func applyingSettingsDoesNotHideTheWarning() {
        let h = Harness(settings: ["mode": "off"])
        h.touchBar.panelWritesSucceed = false
        let c = h.makeController()
        refusals(c)
        c.applySettings()
        #expect(c.panelControlFailed)
        #expect(!c.controlFailed, "brightness writes are a separate warning")
    }

    @Test func stayingLitWarnsWhenTurnOnKeepsBeingRefused() {
        let h = Harness()
        h.touchBar.panelState = .off
        h.touchBar.panelWritesSucceed = false
        let c = h.makeController()
        refusals(c)
        #expect(c.panelControlFailed)
    }

    @Test func changingTheModeClearsTheWarning() {
        let h = Harness(settings: ["mode": "off"])
        h.touchBar.panelWritesSucceed = false
        let c = h.makeController()
        refusals(c)
        h.touchBar.panelWritesSucceed = true
        c.mode = .auto
        #expect(!c.panelControlFailed)
    }
}

@Suite("Fast user switching")
@MainActor
struct UserSessionTests {
    @Test func leavesTheOtherUsersTouchBarAlone() {
        let h = Harness(settings: ["mode": "off"])
        let c = h.makeController()
        c.start()
        c.sessionDidResignActive()
        h.touchBar.resetCalls()

        h.touchBar.simulatePanelStateChange(to: .on)
        c.tick()
        c.applySettings()
        c.level = 0.2
        #expect(h.touchBar.calls.isEmpty)
        c.prepareForQuit()
    }

    @Test func handsBackBrightnessAndOffWhenSwitchingAway() {
        let h = Harness(settings: ["mode": "off"])
        h.touchBar.autoBrightness = false
        h.touchBar.brightness = 0.45
        let c = h.makeController()
        c.start()
        #expect(h.touchBar.panelState == .off)

        c.sessionDidResignActive()
        #expect(h.touchBar.panelState == .on)
        #expect(!h.touchBar.autoBrightness)
        #expect(h.touchBar.brightness == 0.45)
        c.prepareForQuit()
    }

    @Test func anInactiveSessionsLockStateDoesNotKeepThePanelDark() {
        let h = Harness(settings: ["mode": "off"])
        let c = h.makeController()
        c.start()
        h.system.isScreenLocked = true
        c.sessionDidResignActive()
        #expect(h.touchBar.panelState == .on)
        c.prepareForQuit()
    }

    @Test func switchingAwayDoesNotLightAClosedMac() {
        let h = Harness(settings: ["mode": "off"])
        let c = h.makeController()
        c.start()
        h.system.isLidClosed = true
        c.sessionDidResignActive()
        #expect(h.touchBar.panelState == .off)
        c.prepareForQuit()
    }

    @Test func comingBackReappliesAndRemembersWhatTheOtherUserLeft() {
        let h = Harness(settings: ["level": 0.8])
        let c = h.makeController()
        c.start()
        c.sessionDidResignActive()

        h.touchBar.autoBrightness = false
        h.touchBar.brightness = 0.6
        c.sessionDidBecomeActive()
        #expect(h.touchBar.brightness == 0.8)

        c.prepareForQuit()
        #expect(h.touchBar.brightness == 0.6)
    }

    @Test func launchingInABackgroundSessionWaitsForTheConsole() {
        let h = Harness(settings: ["mode": "off"])
        h.system.isSessionActive = false
        let c = h.makeController()
        c.start()
        c.tick()
        #expect(h.touchBar.calls.isEmpty)

        c.sessionDidBecomeActive()
        #expect(h.touchBar.panelState == .off)
        c.prepareForQuit()
    }
}

@Suite("Login item retries")
@MainActor
struct LoginItemRetryTests {
    @Test func aRefusedFirstRegistrationIsRetriedOnTheNextLaunch() {
        let h = Harness()
        h.loginItem.failNextCall = true
        let first = h.makeController()
        first.configureLoginItemOnFirstLaunch()
        #expect(first.setupIssues == [.loginItemFailed])

        let relaunched = h.makeController()
        relaunched.configureLoginItemOnFirstLaunch()
        #expect(h.loginItem.registerCount == 2)
        #expect(relaunched.launchAtLogin)
        #expect(relaunched.setupIssues.isEmpty)

        // Configured now: a later launch must not register again.
        h.makeController().configureLoginItemOnFirstLaunch()
        #expect(h.loginItem.registerCount == 2)
    }

    @Test func aRefusedOptOutStillCountsAsTheUsersChoice() {
        let h = Harness()
        h.loginItem.failNextCall = true
        h.makeController().setLaunchAtLogin(false)
        h.makeController().configureLoginItemOnFirstLaunch()
        #expect(h.loginItem.registerCount == 0)
    }
}
