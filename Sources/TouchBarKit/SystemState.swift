import CoreGraphics
import IOKit
import ServiceManagement

/// Conditions under which the panel must be left dark or left alone.
public protocol SystemStateProviding {
    var isLidClosed: Bool { get }
    var isBuiltInDisplayAsleep: Bool { get }
    var isScreenLocked: Bool { get }
    /// false while another user owns the console (fast user switching).
    var isSessionActive: Bool { get }
}

public struct LiveSystemState: SystemStateProviding {
    public init() {}

    public var isLidClosed: Bool {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return true }
        defer { IOObjectRelease(root) }
        let value = IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
        return value as? Bool ?? true
    }

    public var isBuiltInDisplayAsleep: Bool {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return true }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return true }
        guard let builtIn = ids.first(where: { CGDisplayIsBuiltin($0) != 0 }) else { return true }
        return CGDisplayIsAsleep(builtIn) != 0
    }

    public var isScreenLocked: Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return true }
        return session["CGSSessionScreenIsLocked"] as? Bool ?? false
    }

    public var isSessionActive: Bool {
        // kCGSessionOnConsoleKey is a C macro, which Swift can't import.
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return session["kCGSSessionOnConsoleKey"] as? Bool ?? false
    }
}

public enum LoginItemStatus: Equatable, Sendable {
    case enabled, requiresApproval, disabled
}

public protocol LoginItemControlling {
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() throws
}

public struct MainAppLoginItem: LoginItemControlling {
    public init() {}

    public var status: LoginItemStatus {
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        default: return .disabled
        }
    }

    public func register() throws { try SMAppService.mainApp.register() }
    public func unregister() throws { try SMAppService.mainApp.unregister() }
}
