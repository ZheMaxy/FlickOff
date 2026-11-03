import AppKit
import Combine
import TBPrivate

public enum Mode: String, CaseIterable, Identifiable, Sendable {
    case auto, manual, off

    public var id: String { rawValue }
}

/// Light output shown in the menu header. Separate from Controller so a changing reading redraws
/// only that label; a change on Controller itself also redraws the menu bar icon.
@MainActor
public final class PanelTelemetry: ObservableObject {
    @Published public fileprivate(set) var physicalNits: Float = 0
}

/// Keeps the Touch Bar in the user's chosen state. corebrightnessd forgets manual settings on reboot
/// and TouchBarServer dims/turns the panel off on idle, so the state is re-applied continuously.
@MainActor
public final class Controller: ObservableObject {
    /// What one connection attempt produced: the Touch Bar if reachable, and the report saying why not otherwise.
    public typealias Connection = (touchBar: TouchBarControlling?, report: CompatibilityReport)

    /// nil while the compatibility check fails: the app then only shows the problem.
    public private(set) var touchBar: TouchBarControlling?
    @Published public private(set) var compatibility: CompatibilityReport
    public let telemetry = PanelTelemetry()
    private let system: SystemStateProviding
    private let loginItem: LoginItemControlling
    private let defaults: UserDefaults
    private let bundlePath: String
    private let reconnect: (@MainActor () -> Connection)?

    @Published public var mode: Mode {
        didSet {
            guard mode != oldValue else { return }
            defaults.set(mode.rawValue, forKey: Keys.mode)
            resetPanelRefusals()
            applySettings()
            if oldValue == .off, mode != .off, canControl, panelShouldBeLit() {
                if touchBar?.panelState != .on { notePanelWrite(touchBar?.turnOn() ?? true) }
                notePanelWrite(touchBar?.undim() ?? true)
            }
        }
    }

    @Published public var level: Double {
        didSet {
            let valid = Self.validatedLevel(level)
            if level != valid { level = valid; return }
            guard level != oldValue else { return }
            defaults.set(level, forKey: Keys.level)
            if mode == .manual, canControl, !awaitingOriginal, let tb = touchBar {
                publish(\.controlFailed, !tb.setBrightness(Float(level)))
            }
        }
    }

    @Published public var preventDimming: Bool {
        didSet {
            defaults.set(preventDimming, forKey: Keys.preventDimming)
            resetPanelRefusals()
            enforcePanelState()
        }
    }

    @Published public private(set) var launchAtLogin = false
    @Published public private(set) var loginNeedsApproval = false
    /// macOS refused a brightness write.
    @Published public private(set) var controlFailed = false
    /// macOS kept refusing to turn the panel on or off or to undo its dimming.
    @Published public private(set) var panelControlFailed = false
    @Published public private(set) var setupIssues: [SetupIssue] = []
    private var loginItemFailed = false
    private var menuIsOpen = false

    public var physicalNits: Float { telemetry.physicalNits }

    /// Set while diagnostics probes run, so the controller doesn't undo what they test.
    public var enforcementPaused = false

    // Used on the main actor, and from deinit once nothing else can reach them.
    nonisolated(unsafe) private var timer: Timer?
    nonisolated(unsafe) private var reconnectTimer: Timer?
    nonisolated(unsafe) private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var ticks = 0
    private var started = false
    private var reconnectAttempts = 0
    private var originalBrightness: BrightnessState?
    /// No write may happen until the launch-time brightness was read, or our own value would be restored on quit.
    private var awaitingOriginal = false
    private var panelRefusals = 0
    private var probeRecovery: (@MainActor (_ panelMayLight: Bool) -> Void)?
    private var sessionActive = true
    private(set) var systemAsleep = false

    /// Waits between attempts to reach services that weren't up yet: about a minute in total.
    static let reconnectDelays: [TimeInterval] = [1, 2, 4, 8, 15, 30]
    /// One refused call can be a service restarting; at the 0.5-second tick this is a couple of seconds of refusals.
    static let refusalsBeforeWarning = 4

    enum Keys {
        static let mode = "mode"
        static let level = "level"
        static let preventDimming = "preventDimming"
        static let loginItemConfigured = "loginItemConfigured"
    }

    public init(
        touchBar: TouchBarControlling?,
        compatibility: CompatibilityReport,
        system: SystemStateProviding,
        loginItem: LoginItemControlling,
        defaults: UserDefaults,
        bundlePath: String = Bundle.main.bundlePath,
        reconnect: (@MainActor () -> Connection)? = nil
    ) {
        self.touchBar = compatibility.isSupported ? touchBar : nil
        self.compatibility = compatibility
        self.system = system
        self.loginItem = loginItem
        self.defaults = defaults
        self.bundlePath = bundlePath
        self.reconnect = reconnect
        mode = Mode(rawValue: defaults.string(forKey: Keys.mode) ?? "") ?? .manual
        level = Self.validatedLevel(defaults.object(forKey: Keys.level) as? Double ?? 1.0)
        preventDimming = defaults.object(forKey: Keys.preventDimming) as? Bool ?? true
    }

    private static func validatedLevel(_ value: Double) -> Double {
        value.isFinite ? min(1, max(0, value)) : 1
    }

    /// The real thing: runs the compatibility check and connects only if it passed.
    public static func live() -> Controller {
        let connection = connectLive()
        return Controller(
            touchBar: connection.touchBar,
            compatibility: connection.report,
            system: LiveSystemState(),
            loginItem: MainAppLoginItem(),
            defaults: .standard,
            reconnect: { connectLive() }
        )
    }

    private static func connectLive() -> Connection {
        let report = CompatibilityReport.run()
        let touchBar = report.isSupported ? TBTouchBar.connect() : nil
        let effectiveReport = report.isSupported && touchBar == nil
            ? CompatibilityReport(checks: report.checks + [
                CompatibilityCheck(name: "control", passed: false, detail: "Touch Bar connection was lost; reopen the app")
            ]) : report
        return (touchBar, effectiveReport)
    }

    public var levelNits: Int {
        guard let tb = touchBar else { return 0 }
        let nits = Double(tb.minNits) + level * Double(tb.maxNits - tb.minNits)
        guard nits.isFinite, (0...10_000).contains(nits) else { return 0 }
        return Int(nits.rounded())
    }

    public func start() {
        guard !started else { return }
        started = true
        enforcementPaused = false
        configureLoginItemOnFirstLaunch()
        observeSystemEvents()
        if touchBar != nil { beginControl() } else { scheduleReconnect() }
    }

    /// Takes over the panel; runs once the Touch Bar is reachable, possibly long after launch.
    private func beginControl() {
        guard let touchBar else { return }
        sessionActive = system.isSessionActive
        awaitingOriginal = true
        touchBar.onPanelStateChange { [weak self] in self?.enforcePanelState() }
        applySettings()
        startTimer()
    }

    private func startTimer() {
        guard started, timer == nil, touchBar != nil else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // Lets macOS coalesce the wakeups. The common modes keep it running during slider drags and modal panels.
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    var isPolling: Bool { timer != nil }

    /// One attempt to reach services that failed the compatibility check. true once the Touch Bar is under control.
    @discardableResult
    func retryConnection() -> Bool {
        guard started, touchBar == nil, compatibility.mayRecover, let reconnect else { return false }
        let connection = reconnect()
        if connection.report.isSupported, let connected = connection.touchBar {
            reconnectTimer?.invalidate()
            reconnectTimer = nil
            touchBar = connected
            compatibility = connection.report
            beginControl()
            return true
        }
        publish(\.compatibility, connection.report)
        return false
    }

    private func scheduleReconnect() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        guard reconnect != nil, touchBar == nil, compatibility.mayRecover,
              reconnectAttempts < Self.reconnectDelays.count else { return }
        let delay = Self.reconnectDelays[reconnectAttempts]
        reconnectAttempts += 1
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.reconnectTimerFired() }
        }
    }

    func reconnectTimerFired() {
        if !retryConnection() { scheduleReconnect() }
    }

    var reconnectIsScheduled: Bool { reconnectTimer != nil }

    public func prepareForQuit() {
        stopTimer()
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
        releaseControl(panelMayLight: panelShouldBeLit())
        enforcementPaused = true
        started = false
    }

    /// Hands the panel back as it was found.
    private func releaseControl(panelMayLight: Bool) {
        probeRecovery?(panelMayLight)
        probeRecovery = nil
        if let originalBrightness {
            touchBar?.setAutoBrightness(originalBrightness.auto)
            if !originalBrightness.auto { touchBar?.setBrightness(originalBrightness.level) }
            self.originalBrightness = nil
        }
        if mode == .off, panelMayLight {
            touchBar?.turnOn()
            touchBar?.undim()
        }
    }

    deinit {
        timer?.invalidate()
        reconnectTimer?.invalidate()
        for (center, token) in observers { center.removeObserver(token) }
    }

    /// Pauses enforcement for a diagnostics probe. `recover` runs if the app quits before the probe finishes.
    /// Returns true when it had to light the panel, because a dark panel would read as "no visible change".
    @discardableResult
    public func beginProbe(recover: @escaping @MainActor (_ panelMayLight: Bool) -> Void) -> Bool {
        enforcementPaused = true
        probeRecovery = recover
        guard let tb = touchBar, tb.panelState != .on, panelShouldBeLit() else { return false }
        tb.turnOn()
        tb.undim()
        return true
    }

    public func endProbe() {
        probeRecovery = nil
        enforcementPaused = false
        applySettings()
    }

    /// Push the saved brightness settings to corebrightnessd.
    public func applySettings() {
        guard let tb = touchBar, canControl else { return }
        guard let state = tb.brightnessState else {
            // corebrightnessd didn't answer. Treating that as "manual, 0%" would make the flickering
            // range the brightness restored on quit, so write nothing until it answers again.
            enforcePanelState()
            return
        }
        if awaitingOriginal {
            originalBrightness = state
            awaitingOriginal = false
        }
        var accepted = true
        switch mode {
        case .auto:
            if !state.auto { accepted = tb.setAutoBrightness(true) }
        case .manual:
            if state.auto { accepted = tb.setAutoBrightness(false) }
            if accepted && abs(Double(state.level) - level) > 0.02 { accepted = tb.setBrightness(Float(level)) }
        case .off:
            break
        }
        publish(\.controlFailed, !accepted)
        enforcePanelState()
    }

    func tick() {
        guard canControl else { return }
        enforcePanelState()
        ticks += 1
        if menuIsOpen, ticks % 2 == 0 { refreshTelemetry() }
        if ticks % 10 == 0 {
            applySettings()
            // Asking macOS is an XPC round trip, so only while waiting for approval in System Settings.
            if setupIssues.contains(.loginItemNeedsApproval) || setupIssues.contains(.loginItemFailed) {
                refreshLoginStatus()
            }
        }
    }

    /// The menu or another of the app's windows opened or closed; nobody reads the light output otherwise.
    public func setMenuOpen(_ open: Bool) {
        menuIsOpen = open
        guard open else { return }
        refreshTelemetry()
        refreshLoginStatus()
    }

    private func refreshTelemetry() {
        let value = touchBar?.physicalNits ?? 0
        let valid = value.isFinite ? min(10_000, max(0, value)) : 0
        if valid.rounded() != telemetry.physicalNits.rounded() { telemetry.physicalNits = valid }
    }

    func systemWillSleep() {
        systemAsleep = true
        stopTimer()
    }

    func systemDidWake() {
        systemAsleep = false
        startTimer()
        userReturned()
    }

    /// The screen woke or was unlocked.
    func userReturned() {
        retryConnection()
        applySettings()
    }

    /// Another user took over the console: hand the Touch Bar back. The lock state of an
    /// inactive session says nothing about the screen the other user is looking at, so it is ignored here.
    func sessionDidResignActive() {
        guard sessionActive else { return }
        releaseControl(panelMayLight: !systemAsleep && !system.isLidClosed && !system.isBuiltInDisplayAsleep)
        sessionActive = false
    }

    func sessionDidBecomeActive() {
        guard !sessionActive else { return }
        sessionActive = true
        awaitingOriginal = touchBar != nil
        userReturned()
    }

    /// Undo TouchBarServer's idle dimming / idle power-off, or keep the panel off in Off mode.
    func enforcePanelState() {
        guard let tb = touchBar, canControl else { return }
        if mode == .off {
            if tb.panelState == .on { notePanelWrite(tb.turnOff()) }
            return
        }
        guard preventDimming else { return }
        let needsOn = tb.panelState == .off
        let needsUndim = tb.dimmingStep != 0
        guard needsOn || needsUndim, panelShouldBeLit() else { return }
        if needsOn { notePanelWrite(tb.turnOn()) }
        if needsUndim { notePanelWrite(tb.undim()) }
    }

    /// The panel must stay dark while the Mac sleeps, the lid is closed, the built-in display sleeps or the screen is locked.
    func panelShouldBeLit() -> Bool {
        !systemAsleep && !system.isLidClosed && !system.isBuiltInDisplayAsleep && !system.isScreenLocked
    }

    /// Paused for a probe, or another user owns the console: leave the panel alone.
    private var canControl: Bool { !enforcementPaused && sessionActive }

    /// @Published notifies even when the value is unchanged, and every notification redraws the
    /// menu bar icon. Polling sets these values constantly, so only real changes may get through.
    private func publish<Value: Equatable>(_ property: ReferenceWritableKeyPath<Controller, Value>, _ value: Value) {
        if self[keyPath: property] != value { self[keyPath: property] = value }
    }

    private func notePanelWrite(_ accepted: Bool) {
        panelRefusals = accepted ? 0 : panelRefusals + 1
        publish(\.panelControlFailed, panelRefusals >= Self.refusalsBeforeWarning)
    }

    private func resetPanelRefusals() {
        panelRefusals = 0
        publish(\.panelControlFailed, false)
    }

    private func observeSystemEvents() {
        let ws = NSWorkspace.shared.notificationCenter
        let events: [(NotificationCenter, Notification.Name, @MainActor (Controller) -> Void)] = [
            (ws, NSWorkspace.willSleepNotification, { $0.systemWillSleep() }),
            (ws, NSWorkspace.didWakeNotification, { $0.systemDidWake() }),
            (ws, NSWorkspace.screensDidWakeNotification, { $0.userReturned() }),
            (ws, NSWorkspace.sessionDidResignActiveNotification, { $0.sessionDidResignActive() }),
            (ws, NSWorkspace.sessionDidBecomeActiveNotification, { $0.sessionDidBecomeActive() }),
            (DistributedNotificationCenter.default(), .init("com.apple.screenIsUnlocked"), { $0.userReturned() }),
        ]
        for (center, name, action) in events {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { if let self { action(self) } }
            }
            observers.append((center, token))
        }
    }

    func configureLoginItemOnFirstLaunch() {
        // A copy running from Downloads or a disk image would register a path that soon disappears;
        // wait until the app sits in Applications.
        if !defaults.bool(forKey: Keys.loginItemConfigured), SetupInspector.isInApplications(bundlePath) {
            setLaunchAtLogin(true)
        }
        refreshLoginStatus()
    }

    public func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try loginItem.register() } else { try loginItem.unregister() }
            loginItemFailed = false
            defaults.set(true, forKey: Keys.loginItemConfigured)
        } catch {
            NSLog("FlickOff: login item change failed: \(error)")
            loginItemFailed = enabled
            // A refused registration stays unconfigured, so the next launch tries again and can show the guide.
            if !enabled { defaults.set(true, forKey: Keys.loginItemConfigured) }
        }
        refreshLoginStatus()
    }

    public func refreshLoginStatus() {
        let status = loginItem.status
        publish(\.launchAtLogin, status == .enabled || status == .requiresApproval)
        publish(\.loginNeedsApproval, status == .requiresApproval)
        publish(\.setupIssues, SetupInspector.issues(bundlePath: bundlePath, loginItem: status, loginItemFailed: loginItemFailed))
    }
}
