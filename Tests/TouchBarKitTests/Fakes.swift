import Foundation
@testable import TouchBarKit

/// Behaves like corebrightnessd + TouchBarServer as observed on a MacBookPro17,1 and records every call.
final class FakeTouchBar: TouchBarControlling {
    var autoWritesSucceed = true
    var brightnessWritesSucceed = true
    var autoBrightness = true
    var brightness: Float = 0.3
    var physicalNits: Float = 100
    var minNits: Float = 11.9
    var maxNits: Float = 357.1
    var panelState: PanelState = .on
    var dimmingStep = 0
    private(set) var calls: [String] = []
    private var panelStateHandler: (() -> Void)?

    func setAutoBrightness(_ enabled: Bool) -> Bool {
        calls.append("auto=\(enabled)")
        guard autoWritesSucceed else { return false }
        autoBrightness = enabled
        return true
    }

    func setBrightness(_ value: Float) -> Bool {
        calls.append("brightness=\(value)")
        guard brightnessWritesSucceed else { return false }
        brightness = min(value, 0.9909091) // corebrightnessd reads back 0.9909 after setting 1.0
        return true
    }

    func undim() {
        calls.append("undim")
        dimmingStep = 0
    }

    func turnOn() {
        calls.append("on")
        panelState = .on
    }

    func turnOff() {
        calls.append("off")
        panelState = .off
    }

    func onPanelStateChange(_ handler: @escaping () -> Void) {
        panelStateHandler = handler
    }

    /// TouchBarServer turned the panel on/off by itself.
    func simulatePanelStateChange(to state: PanelState) {
        panelState = state
        panelStateHandler?()
    }

    func resetCalls() {
        calls.removeAll()
    }
}

final class FakeSystemState: SystemStateProviding {
    var isLidClosed = false
    var isBuiltInDisplayAsleep = false
    var isScreenLocked = false
}

final class FakeLoginItem: LoginItemControlling {
    struct Failure: Error {}

    var status: LoginItemStatus = .disabled
    var failNextCall = false
    private(set) var registerCount = 0
    private(set) var unregisterCount = 0

    func register() throws {
        registerCount += 1
        if failNextCall { failNextCall = false; throw Failure() }
        status = .enabled
    }

    func unregister() throws {
        unregisterCount += 1
        if failNextCall { failNextCall = false; throw Failure() }
        status = .disabled
    }
}

extension CompatibilityReport {
    static let supported = CompatibilityReport(checks: [
        CompatibilityCheck(name: "hardware", passed: true, detail: "ok"),
        CompatibilityCheck(name: "frameworks", passed: true, detail: "ok"),
        CompatibilityCheck(name: "api", passed: true, detail: "ok"),
        CompatibilityCheck(name: "touchBar", passed: true, detail: "Touch Bar display id 3"),
    ])

    static func failing(at name: String) -> CompatibilityReport {
        CompatibilityReport(checks: [
            CompatibilityCheck(name: "frameworks", passed: true, detail: "ok"),
            CompatibilityCheck(name: name, passed: false, detail: "broken"),
        ])
    }
}

/// A controller wired to fakes and a throwaway UserDefaults suite.
@MainActor
final class Harness {
    let touchBar = FakeTouchBar()
    let system = FakeSystemState()
    let loginItem = FakeLoginItem()
    let defaults: UserDefaults
    private let suiteName = "TouchBarKitTests.\(UUID().uuidString)"

    init(settings: [String: Any] = [:]) {
        defaults = UserDefaults(suiteName: suiteName)!
        settings.forEach { defaults.set($0.value, forKey: $0.key) }
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func makeController(
        compatibility: CompatibilityReport = .supported,
        bundlePath: String = "/Applications/FlickOff.app"
    ) -> Controller {
        Controller(touchBar: touchBar, compatibility: compatibility, system: system, loginItem: loginItem,
                   defaults: defaults, bundlePath: bundlePath)
    }
}
