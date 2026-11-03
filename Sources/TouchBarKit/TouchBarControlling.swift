import TBPrivate

public enum PanelState: Equatable, Sendable {
    case on, off, unknown
}

/// What Controller needs from the Touch Bar: TBTouchBar in the app, a fake in tests.
public protocol TouchBarControlling: AnyObject {
    var autoBrightness: Bool { get }
    @discardableResult func setAutoBrightness(_ enabled: Bool) -> Bool
    var brightness: Float { get }
    @discardableResult func setBrightness(_ value: Float) -> Bool
    var physicalNits: Float { get }
    var minNits: Float { get }
    var maxNits: Float { get }
    var panelState: PanelState { get }
    var dimmingStep: Int { get }
    func undim()
    func turnOn()
    func turnOff()
    func onPanelStateChange(_ handler: @escaping () -> Void)
}

extension TBTouchBar: TouchBarControlling {
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
