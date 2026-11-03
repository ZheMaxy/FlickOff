import Foundation
import TBPrivate

/// A short visible change the user confirms; everything is put back afterwards.
public enum ProbeKind: String, CaseIterable, Identifiable, Sendable {
    case panelOffOn          // TouchBarServer channel: off, then on
    case coreBrightnessLevel // corebrightnessd: dim, then bright, then the user's setting
    case dimmingCoefficient  // TouchBarServer channel: scale the light output down, then back

    public var id: String { rawValue }
}

public enum ProbeOutcome: Equatable, Sendable {
    case notRun
    case callsFailed(String)
    case awaitingAnswer
    case answered(sawChange: Bool)

    var reportText: String {
        switch self {
        case .notRun: return "not run"
        case .callsFailed(let why): return "API refused: \(why)"
        case .awaitingAnswer: return "ran, user did not answer"
        case .answered(let saw): return saw ? "ran, user SAW the change" : "ran, user saw NO change"
        }
    }
}

@MainActor
public protocol ProbeDriving {
    func panelTurnOff() -> Bool
    func panelTurnOn() -> Bool
    func setDimmingCoefficient(_ coefficient: Float) -> Bool
    func readBrightness() -> (auto: Bool, level: Float)?
    func writeBrightness(auto: Bool, level: Float?) -> Bool
}

public struct LiveProbeDriver: ProbeDriving {
    public init() {}
    public func panelTurnOff() -> Bool { TBDiagnostics.panelTurnOff() }
    public func panelTurnOn() -> Bool { TBDiagnostics.panelTurnOn() }
    public func setDimmingCoefficient(_ coefficient: Float) -> Bool { TBDiagnostics.setDimmingCoefficient(coefficient) }

    public func readBrightness() -> (auto: Bool, level: Float)? {
        guard let b = TBDiagnostics.readBrightness(), let auto = b["auto"], let level = b["level"] else { return nil }
        return (auto.boolValue, level.floatValue)
    }

    public func writeBrightness(auto: Bool, level: Float?) -> Bool {
        TBDiagnostics.writeAutoBrightness(auto, level: level.map { NSNumber(value: $0) })
    }
}

@MainActor
public struct ProbeRunner {
    let driver: ProbeDriving
    let pause: (TimeInterval) async -> Void

    public init(driver: ProbeDriving, pause: @escaping (TimeInterval) async -> Void = ProbeRunner.sleep) {
        self.driver = driver
        self.pause = pause
    }

    nonisolated public static func sleep(_ seconds: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    /// Undoes what a probe interrupted by quitting left behind. The controller restores the brightness itself.
    public func recover(from kind: ProbeKind, panelMayLight: Bool) {
        switch kind {
        case .panelOffOn:
            if panelMayLight { _ = driver.panelTurnOn() }
        case .coreBrightnessLevel:
            break
        case .dimmingCoefficient:
            _ = driver.setDimmingCoefficient(1.0)
        }
    }

    /// Shows the effect and restores the previous state. `.awaitingAnswer` means: ask the user what they saw.
    public func perform(_ kind: ProbeKind) async -> ProbeOutcome {
        switch kind {
        case .panelOffOn:
            let off = driver.panelTurnOff()
            await pause(1.5)
            let on = driver.panelTurnOn() || driver.panelTurnOn()
            if !off { return .callsFailed("turnOff") }
            return on ? .awaitingAnswer : .callsFailed("turnOn")

        case .coreBrightnessLevel:
            guard let saved = driver.readBrightness() else {
                return .callsFailed("corebrightnessd has no Touch Bar brightness")
            }
            guard saved.level.isFinite, (0...1).contains(saved.level) else {
                return .callsFailed("invalid saved brightness")
            }
            let dim = driver.writeBrightness(auto: false, level: 0.1)
            await pause(1.5)
            let bright = driver.writeBrightness(auto: false, level: 1.0)
            await pause(1.5)
            let restored = driver.writeBrightness(auto: saved.auto, level: saved.auto ? nil : saved.level)
            if !restored { return .callsFailed("restoring the previous brightness") }
            return dim && bright ? .awaitingAnswer : .callsFailed("DisplayBrightness write")

        case .dimmingCoefficient:
            let dim = driver.setDimmingCoefficient(0.2)
            await pause(1.5)
            let restored = driver.setDimmingCoefficient(1.0)
            if !restored { return .callsFailed("restoring the coefficient") }
            return dim ? .awaitingAnswer : .callsFailed("dimToStep:withCoefficient:")
        }
    }
}

public struct DiagnosticsSection: Equatable, Sendable {
    public let title: String
    public let text: String

    public init(title: String, text: String) {
        self.title = title
        self.text = text
    }

    public static func collect() -> [DiagnosticsSection] {
        TBDiagnostics.collectSections().map { DiagnosticsSection(title: $0[0], text: $0[1]) }
    }
}

/// Everything a tester sends back: self-test, their answers to the probes, and the raw system snapshot.
public struct DiagnosticsReport: Equatable, Sendable {
    public var compatibility: CompatibilityReport
    public var outcomes: [ProbeKind: ProbeOutcome]
    public var sections: [DiagnosticsSection]

    public init(compatibility: CompatibilityReport, outcomes: [ProbeKind: ProbeOutcome] = [:], sections: [DiagnosticsSection]) {
        self.compatibility = compatibility
        self.outcomes = outcomes
        self.sections = sections
    }

    public func text(appVersion: String, system: SystemInfo = .current) -> String {
        var parts = [compatibility.text(appVersion: appVersion, system: system), "== Probes =="]
        parts += ProbeKind.allCases.map { "\($0.rawValue): \((outcomes[$0] ?? .notRun).reportText)" }
        for section in sections {
            parts.append("\n== \(section.title) ==\n\(section.text)")
        }
        return Self.redactIdentifiers(parts.joined(separator: "\n"))
    }

    /// Display UUIDs are derived from the panel and can single out a Mac; the report keeps only which ones match.
    static func redactIdentifiers(_ text: String) -> String {
        let uuid = try! NSRegularExpression(pattern: "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}")
        var labels: [String: String] = [:]
        var result = ""
        var last = text.startIndex
        for match in uuid.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text) else { continue }
            let value = text[range].uppercased()
            let label = labels[value] ?? "<uuid-\(labels.count + 1)>"
            labels[value] = label
            result += text[last..<range.lowerBound] + label
            last = range.upperBound
        }
        return result + text[last...]
    }
}
