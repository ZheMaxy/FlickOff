import AppKit
import Combine
import TBPrivate

public enum Mode: String, CaseIterable, Identifiable, Sendable {
    case auto, manual, off

    public var id: String { rawValue }
}

/// What the panel does while nobody is using the Mac.
public enum IdleBehavior: Hashable, Sendable {
    /// macOS dims and powers off the panel on its own schedule.
    case system
    /// Undo idle dimming and power-off for as long as the Mac is awake, unlocked and open.
    case stayLit
    /// Stay lit while the Mac is in use, then go dark without passing through the dim range.
    case turnOff(afterSeconds: Int)

    /// The delays the menu offers.
    public static let offDelays = [60, 300, 900]
    /// Spares the OLED by default. Existing installations keep staying lit until the user chooses.
    static let newInstallation = IdleBehavior.turnOff(afterSeconds: 300)
    /// Shorter stored values are ignored, so a bad preference can't keep blanking the panel.
    static let shortestOffDelay = 5
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
            noteActivity()
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

    @Published public var idleBehavior: IdleBehavior {
        didSet {
            guard idleBehavior != oldValue else { return }
            Self.save(idleBehavior, to: defaults)
            resetPanelRefusals()
            let wasDarkForIdle = idleOff != .inactive
            noteActivity()
            // macOS won't light a panel it didn't turn off itself.
            if wasDarkForIdle, idleBehavior == .system, mode != .off, canControl, panelShouldBeLit() {
                notePanelWrite(touchBar?.turnOn() ?? true)
                notePanelWrite(touchBar?.undim() ?? true)
            }
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
    private var lastActivity: TimeInterval
    private var idleOff = IdleOff.inactive
    private var probeRecovery: (@MainActor (_ panelMayLight: Bool) -> Void)?
    private var sessionActive = true
    private(set) var systemAsleep = false

    /// Waits between attempts to reach services that weren't up yet: about a minute in total.
    static let reconnectDelays: [TimeInterval] = [1, 2, 4, 8, 15, 30]
    /// One refused call can be a service restarting; at the 0.5-second tick this is a couple of seconds of refusals.
    nonisolated static let refusalsBeforeWarning = 4

    /// How far turning the panel off for idleness has got. corebrightnessd reports the new state a moment
    /// after a call, so "on" only counts as someone else lighting the panel once "off" has been seen.
    private enum IdleOff {
        case inactive, requested, confirmed
    }

    enum Keys {
        static let mode = "mode"
        static let level = "level"
        static let preventDimming = "preventDimming"
        static let idleOffSeconds = "idleOffSeconds"
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
        let idle = Self.savedIdleBehavior(defaults)
        idleBehavior = idle
        lastActivity = system.uptime
        // Written now: "no stored delay" marks an installation from before this setting existed.
        Self.save(idle, to: defaults)
    }

    nonisolated static func savedIdleBehavior(_ defaults: UserDefaults) -> IdleBehavior {
        if defaults.object(forKey: Keys.preventDimming) as? Bool == false { return .system }
        guard let seconds = defaults.object(forKey: Keys.idleOffSeconds) as? Int else {
            let existing = [Keys.mode, Keys.level, Keys.preventDimming, Keys.loginItemConfigured]
                .contains { defaults.object(forKey: $0) != nil }
            return existing ? .stayLit : .newInstallation
        }
        return seconds >= IdleBehavior.shortestOffDelay ? .turnOff(afterSeconds: seconds) : .stayLit
    }

    private static func save(_ behavior: IdleBehavior, to defaults: UserDefaults) {
        defaults.set(behavior != .system, forKey: Keys.preventDimming)
        switch behavior {
        case .system: break
        case .stayLit: defaults.set(0, forKey: Keys.idleOffSeconds)
        case .turnOff(let seconds): defaults.set(seconds, forKey: Keys.idleOffSeconds)
        }
    }

    /// What the user chose, for reports. Read from preferences, so the command-line report can show it too.
    public nonisolated static func savedSettingsSection(defaults: UserDefaults = .standard) -> DiagnosticsSection {
        let mode = defaults.string(forKey: Keys.mode).flatMap(Mode.init(rawValue:)) ?? .manual
        let level = validatedLevel(defaults.object(forKey: Keys.level) as? Double ?? 1.0)
        return DiagnosticsSection(title: "FlickOff settings", text: """
            mode: \(mode.rawValue)
            level: \(Int((level * 100).rounded()))%
            when idle: \(savedIdleBehavior(defaults))
            """)
    }

    private nonisolated static func validatedLevel(_ value: Double) -> Double {
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
        noteActivity()
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
        if mode == .off || idleOff != .inactive, panelMayLight {
            touchBar?.turnOn()
            touchBar?.undim()
        }
        idleOff = .inactive
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
        noteActivity()
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
        noteActivity()
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

    /// Undo TouchBarServer's idle dimming / idle power-off, turn the panel off when idle if asked to,
    /// or keep it off in Off mode.
    func enforcePanelState() {
        guard let tb = touchBar, canControl else { return }
        if mode == .off {
            if tb.panelState == .on { notePanelWrite(tb.turnOff()) }
            return
        }
        switch idleBehavior {
        case .system: return
        case .stayLit: break
        case .turnOff(let seconds):
            if keepsDarkForIdle(after: TimeInterval(seconds), tb) { return }
        }
        let needsOn = tb.panelState == .off
        let needsUndim = tb.dimmingStep != 0
        guard needsOn || needsUndim, panelShouldBeLit() else { return }
        if needsOn { notePanelWrite(tb.turnOn()) }
        if needsUndim { notePanelWrite(tb.undim()) }
    }

    /// Drives the idle power-off. true while the panel should stay dark because nobody is using the Mac.
    private func keepsDarkForIdle(after delay: TimeInterval, _ tb: TouchBarControlling) -> Bool {
        let inputSeconds = system.secondsSinceLastInput
        let state = tb.panelState
        switch idleOff {
        case .inactive:
            guard min(inputSeconds, system.uptime - lastActivity) >= delay else { return false }
            if state == .off {
                idleOff = .confirmed
            } else if state == .on {
                let accepted = tb.turnOff()
                notePanelWrite(accepted)
                if accepted { idleOff = .requested }
            }
            return true
        case .requested:
            if inputSeconds < delay {
                noteActivity()
                return false
            }
            if state == .off {
                idleOff = .confirmed
            } else if state == .on {
                notePanelWrite(tb.turnOff())
            }
            return true
        case .confirmed:
            // Input, or someone else lit it: most likely a touch on the bar, which no input event reports.
            if inputSeconds < delay || state == .on {
                noteActivity()
                return false
            }
            return true
        }
    }

    private func noteActivity() {
        lastActivity = system.uptime
        idleOff = .inactive
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
