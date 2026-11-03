import Foundation
import TBPrivate

public struct CompatibilityCheck: Equatable, Sendable {
    public let name: String
    public let passed: Bool
    public let detail: String

    public init(name: String, passed: Bool, detail: String) {
        self.name = name
        self.passed = passed
        self.detail = detail
    }
}

/// What to tell the user when the launch-time check fails.
public enum CompatibilityProblem: Equatable, Sendable {
    case unsupportedOS, noTouchBar, controlDenied
}

public struct CompatibilityReport: Equatable, Sendable {
    public let checks: [CompatibilityCheck]

    public init(checks: [CompatibilityCheck]) {
        self.checks = checks
    }

    /// Runs the real probes against the private frameworks of the running macOS.
    public static func run() -> CompatibilityReport {
        CompatibilityReport(checks: TBTouchBar.runCompatibilityChecks().map {
            CompatibilityCheck(name: $0.name, passed: $0.passed, detail: $0.detail)
        })
    }

    public var isSupported: Bool { problem == nil }

    public var problem: CompatibilityProblem? {
        guard !checks.isEmpty else { return .unsupportedOS }
        // No Touch Bar is the real answer even if the private APIs are broken too.
        if checks.contains(where: { $0.name == "hardware" && !$0.passed }) { return .noTouchBar }
        guard let failed = checks.first(where: { !$0.passed }) else { return nil }
        return failed.name == "control" ? .controlDenied : .unsupportedOS
    }

    /// A service that wasn't up yet can still appear, for example right after login.
    /// A missing Touch Bar or a changed private API can't.
    public var mayRecover: Bool {
        guard problem != .noTouchBar, let failed = checks.first(where: { !$0.passed }) else { return false }
        return failed.name != "frameworks" && failed.name != "api"
    }

    /// Plain-text report a tester can paste into an email.
    public func text(appVersion: String, system: SystemInfo = .current) -> String {
        let width = checks.map(\.name.count).max() ?? 0
        var lines = [
            "FlickOff \(appVersion) compatibility report",
            "\(system.osVersion) · \(system.model)",
            "",
        ]
        for check in checks {
            let name = check.name.padding(toLength: width, withPad: " ", startingAt: 0)
            lines.append("[\(check.passed ? "PASS" : "FAIL")] \(name)  \(check.detail)")
        }
        lines.append("")
        if let problem {
            lines.append("Result: NOT supported (\(problem))")
        } else {
            lines.append("Result: supported")
        }
        return lines.joined(separator: "\n")
    }
}

public struct SystemInfo: Equatable, Sendable {
    public let osVersion: String
    public let model: String

    public init(osVersion: String, model: String) {
        self.osVersion = osVersion
        self.model = model
    }

    /// Always English: the report goes to the developer, whatever the user's language.
    public static var current: SystemInfo {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return SystemInfo(
            osVersion: "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion) (\(sysctlString("kern.osversion")))",
            model: sysctlString("hw.model")
        )
    }

    private static func sysctlString(_ name: String) -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "unknown" }
        var buffer = [CChar](repeating: 0, count: size + 1)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return "unknown" }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
