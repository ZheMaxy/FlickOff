import AppKit
import Combine
import TBPrivate

public enum Mode: String, CaseIterable, Identifiable, Sendable {
    case auto, manual, off

    public var id: String { rawValue }
}

/// Keeps the Touch Bar in the user's chosen state. corebrightnessd forgets manual settings on reboot
/// and TouchBarServer dims/turns the panel off on idle, so the state is re-applied continuously.
@MainActor
public final class Controller: ObservableObject {
    /// nil when the compatibility check failed: the app then only shows the problem.
    public let touchBar: TouchBarControlling?
    public let compatibility: CompatibilityReport
    private let system: SystemStateProviding
    private let loginItem: LoginItemControlling
    private let defaults: UserDefaults
    private let bundlePath: String

    @Published public var mode: Mode {
        didSet {
            guard mode != oldValue else { return }
            defaults.set(mode.rawValue, forKey: Keys.mode)
            applySettings()
            if oldValue == .off, mode != .off, !enforcementPaused, panelShouldBeLit() {
                if touchBar?.panelState != .on { touchBar?.turnOn() }
                touchBar?.undim()
            }
        }
    }

    @Published public var level: Double {
        didSet {
            let valid = Self.validatedLevel(level)
            if level != valid { level = valid; return }
            defaults.set(level, forKey: Keys.level)
            if mode == .manual, !enforcementPaused, let tb = touchBar {
                controlFailed = !tb.setBrightness(Float(level))
            }
        }
    }

    @Published public var preventDimming: Bool {
        didSet {
            defaults.set(preventDimming, forKey: Keys.preventDimming)
            enforcePanelState()
        }
    }

    @Published public private(set) var launchAtLogin = false
    @Published public private(set) var loginNeedsApproval = false
    @Published public private(set) var controlFailed = false
    @Published public private(set) var physicalNits: Float = 0
    @Published public private(set) var setupIssues: [SetupIssue] = []
    private var loginItemFailed = false

    /// Set while diagnostics probes run, so the controller doesn't undo what they test.
    public var enforcementPaused = false

    // Used on the main actor, and from deinit once nothing else can reach them.
    nonisolated(unsafe) private var timer: Timer?
    nonisolated(unsafe) private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var ticks = 0
    private var started = false
    private var originalBrightness: (auto: Bool, level: Float)?
    private(set) var systemAsleep = false

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
        bundlePath: String = Bundle.main.bundlePath
    ) {
        self.touchBar = compatibility.isSupported ? touchBar : nil
        self.compatibility = compatibility
        self.system = system
        self.loginItem = loginItem
        self.defaults = defaults
        self.bundlePath = bundlePath
        mode = Mode(rawValue: defaults.string(forKey: Keys.mode) ?? "") ?? .manual
        level = Self.validatedLevel(defaults.object(forKey: Keys.level) as? Double ?? 1.0)
        preventDimming = defaults.object(forKey: Keys.preventDimming) as? Bool ?? true
    }

    private static func validatedLevel(_ value: Double) -> Double {
        value.isFinite ? min(1, max(0, value)) : 1
    }

    /// The real thing: runs the compatibility check and connects only if it passed.
    public static func live() -> Controller {
        let report = CompatibilityReport.run()
        let touchBar = report.isSupported ? TBTouchBar.connect() : nil
        let effectiveReport = report.isSupported && touchBar == nil
            ? CompatibilityReport(checks: report.checks + [
                CompatibilityCheck(name: "control", passed: false, detail: "Touch Bar connection was lost; reopen the app")
            ]) : report
        return Controller(
            touchBar: touchBar,
            compatibility: effectiveReport,
            system: LiveSystemState(),
            loginItem: MainAppLoginItem(),
            defaults: .standard
        )
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
        configureLoginItemOnFirstLaunch()
        guard let touchBar else { return }
        originalBrightness = (touchBar.autoBrightness, touchBar.brightness)
        enforcementPaused = false
        touchBar.onPanelStateChange { [weak self] in self?.enforcePanelState() }
        observeSystemEvents()
        applySettings()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    public func prepareForQuit() {
        timer?.invalidate()
        timer = nil
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
        if let originalBrightness {
            touchBar?.setAutoBrightness(originalBrightness.auto)
            if !originalBrightness.auto { touchBar?.setBrightness(originalBrightness.level) }
            self.originalBrightness = nil
        }
        if mode == .off, panelShouldBeLit() { touchBar?.turnOn(); touchBar?.undim() }
        enforcementPaused = true
        started = false
    }

    deinit {
        timer?.invalidate()
        for (center, token) in observers { center.removeObserver(token) }
    }

    /// Push the saved brightness settings to corebrightnessd.
    public func applySettings() {
        guard let tb = touchBar, !enforcementPaused else { return }
        var accepted = true
        switch mode {
        case .auto:
            if !tb.autoBrightness { accepted = tb.setAutoBrightness(true) }
        case .manual:
            if tb.autoBrightness { accepted = tb.setAutoBrightness(false) }
            if accepted && abs(Double(tb.brightness) - level) > 0.02 { accepted = tb.setBrightness(Float(level)) }
        case .off:
            break
        }
        controlFailed = !accepted
        enforcePanelState()
    }

    func tick() {
        guard !enforcementPaused else { return }
        enforcePanelState()
        ticks += 1
        if ticks % 2 == 0 {
            let value = touchBar?.physicalNits ?? 0
            physicalNits = value.isFinite ? min(10_000, max(0, value)) : 0
        }
        if ticks % 10 == 0 {
            applySettings()
            refreshLoginStatus() // picks up approval given in System Settings
        }
    }

    func systemWillSleep() {
        systemAsleep = true
    }

    func systemDidWake() {
        systemAsleep = false
        applySettings()
    }

    /// Undo TouchBarServer's idle dimming / idle power-off, or keep the panel off in Off mode.
    func enforcePanelState() {
        guard let tb = touchBar, !enforcementPaused else { return }
        if mode == .off {
            if tb.panelState == .on { tb.turnOff() }
            return
        }
        guard preventDimming else { return }
        let needsOn = tb.panelState == .off
        let needsUndim = tb.dimmingStep != 0
        guard needsOn || needsUndim, panelShouldBeLit() else { return }
        if needsOn { tb.turnOn() }
        if needsUndim { tb.undim() }
    }

    /// The panel must stay dark while the Mac sleeps, the lid is closed, the built-in display sleeps or the screen is locked.
    func panelShouldBeLit() -> Bool {
        !systemAsleep && !system.isLidClosed && !system.isBuiltInDisplayAsleep && !system.isScreenLocked
    }

    private func observeSystemEvents() {
        let ws = NSWorkspace.shared.notificationCenter
        let events: [(NotificationCenter, Notification.Name, @MainActor (Controller) -> Void)] = [
            (ws, NSWorkspace.willSleepNotification, { $0.systemWillSleep() }),
            (ws, NSWorkspace.didWakeNotification, { $0.systemDidWake() }),
            (ws, NSWorkspace.screensDidWakeNotification, { $0.applySettings() }),
            (DistributedNotificationCenter.default(), .init("com.apple.screenIsUnlocked"), { $0.applySettings() }),
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
            defaults.set(true, forKey: Keys.loginItemConfigured)
            setLaunchAtLogin(true)
        }
        refreshLoginStatus()
    }

    public func setLaunchAtLogin(_ enabled: Bool) {
        defaults.set(true, forKey: Keys.loginItemConfigured)
        do {
            if enabled { try loginItem.register() } else { try loginItem.unregister() }
            loginItemFailed = false
        } catch {
            NSLog("FlickOff: login item change failed: \(error)")
            loginItemFailed = enabled
        }
        refreshLoginStatus()
    }

    public func refreshLoginStatus() {
        let status = loginItem.status
        launchAtLogin = status == .enabled || status == .requiresApproval
        loginNeedsApproval = status == .requiresApproval
        let issues = SetupInspector.issues(bundlePath: bundlePath, loginItem: status, loginItemFailed: loginItemFailed)
        if issues != setupIssues { setupIssues = issues }
    }
}
