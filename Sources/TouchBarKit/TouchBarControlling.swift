import TBPrivate

public enum PanelState: Equatable, Sendable {
    case on, off, unknown
}

/// The brightness setting corebrightnessd reports for the Touch Bar.
public struct BrightnessState: Equatable, Sendable {
    public let auto: Bool
    public let level: Float

    public init(auto: Bool, level: Float) {
        self.auto = auto
        self.level = level
    }
}

/// What Controller needs from the Touch Bar: TBTouchBar in the app, a fake in tests.
public protocol TouchBarControlling: AnyObject {
    /// nil when corebrightnessd didn't answer with valid values.
    var brightnessState: BrightnessState? { get }
    @discardableResult func setAutoBrightness(_ enabled: Bool) -> Bool
    @discardableResult func setBrightness(_ value: Float) -> Bool
    var physicalNits: Float { get }
    var minNits: Float { get }
    var maxNits: Float { get }
    var panelState: PanelState { get }
    var dimmingStep: Int { get }
    @discardableResult func undim() -> Bool
    @discardableResult func turnOn() -> Bool
    @discardableResult func turnOff() -> Bool
    func onPanelStateChange(_ handler: @escaping () -> Void)
}

extension TBTouchBar: TouchBarControlling {
    public var brightnessState: BrightnessState? {
        guard let auto = autoBrightnessValue, let level = brightnessValue else { return nil }
        return BrightnessState(auto: auto.boolValue, level: level.floatValue)
    }

    public var panelState: PanelState {
        switch displayState {
        case .on: return .on
        case .off: return .off
        default: return .unknown
        }
    }

    public func onPanelStateChange(_ handler: @escaping () -> Void) {
        setDisplayStateHandler { _ in handler() }
    }
}
