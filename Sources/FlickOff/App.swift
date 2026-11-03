import ServiceManagement
import SwiftUI
import TouchBarKit
import UniformTypeIdentifiers

/// Strings live in Resources/<lang>.lproj/Localizable.strings; macOS picks the first supported system language, English otherwise.
func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }

let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"

extension Mode {
    var title: String {
        switch self {
        case .auto: return L("mode.auto")
        case .manual: return L("mode.manual")
        case .off: return L("mode.off")
        }
    }

    var symbol: String {
        switch self {
        case .auto: return "sun.max.circle"
        case .manual: return "sun.max.fill"
        case .off: return "moon.zzz.fill"
        }
    }
}

extension CompatibilityProblem {
    var message: String {
        switch self {
        case .unsupportedOS: return L("error.unsupportedOS")
        case .noTouchBar: return L("error.noTouchBar")
        case .controlDenied: return L("error.controlDenied")
        }
    }
}

/// System Settings labels as this Mac shows them (read from the system), with our own wording as fallback.
struct SettingsLabels {
    let systemSettings: String
    let general: String
    let loginItems: String
    let openAtLogin: String
    let applications: String

    static func current(names: SystemSettingsNames = .read()) -> SettingsLabels {
        SettingsLabels(
            systemSettings: names.systemSettings ?? L("settings.systemSettings"),
            general: names.general ?? L("settings.general"),
            loginItems: names.loginItems ?? L("settings.loginItemsAndExtensions"),
            openAtLogin: names.openAtLogin ?? L("settings.openAtLogin"),
            applications: FileManager.default.displayName(atPath: "/Applications")
        )
    }

    var loginItemsPath: String { [systemSettings, general, loginItems].joined(separator: " → ") }
}

enum GuideAction: Hashable {
    case openLoginItems, openApplications, copyReport, runDiagnostics

    func title(_ labels: SettingsLabels) -> String {
        switch self {
        case .openLoginItems: return L("setup.button.openSettings")
        case .openApplications: return String(format: L("setup.button.openFolder"), labels.applications)
        case .copyReport: return L("error.copyReport")
        case .runDiagnostics: return L("setup.button.runDiagnostics")
        }
    }
}

/// What the user sees for one problem: title, why it matters, numbered steps, buttons.
struct Guide {
    let title: String
    let why: String?
    let steps: [String]
    let actions: [GuideAction]

    init(_ issue: SetupIssue, _ labels: SettingsLabels) {
        switch issue {
        case .loginItemNeedsApproval, .loginItemFailed:
            let approval = issue == .loginItemNeedsApproval
            title = approval ? L("setup.loginApproval.title") : L("setup.loginFailed.title")
            why = approval ? L("setup.loginApproval.why") : L("setup.loginFailed.why")
            steps = [
                String(format: L("setup.step.openLoginItems"), labels.loginItemsPath),
                String(format: L("setup.step.enableApp"), labels.openAtLogin, labels.applications),
                L("setup.step.comeBack"),
            ]
            actions = [.openLoginItems]
        case .moveToApplications(let translocated):
            title = String(format: L("setup.move.title"), labels.applications)
            why = translocated ? L("setup.move.whyTranslocated") : L("setup.move.whyElsewhere")
            steps = [
                L("setup.step.quit"),
                String(format: L("setup.step.drag"), labels.applications),
                String(format: L("setup.step.openFromFolder"), labels.applications),
            ]
            actions = [.openApplications]
        }
    }

    init(_ problem: CompatibilityProblem) {
        title = problem.message
        switch problem {
        case .noTouchBar:
            why = L("problem.noTouchBar.why")
            steps = []
            actions = [.copyReport]
        case .unsupportedOS:
            why = nil
            steps = [L("problem.unsupportedOS.update"), L("problem.runDiagnostics")]
            actions = [.runDiagnostics]
        case .controlDenied:
            why = nil
            steps = [L("problem.controlDenied.restart"), L("problem.runDiagnostics")]
            actions = [.runDiagnostics]
        }
    }

    /// Plain text for `--setup-info`.
    var text: String {
        var lines = ["## \(title)"]
        if let why { lines.append(why) }
        lines += steps.enumerated().map { "\($0.offset + 1). \($0.element)" }
        return lines.joined(separator: "\n")
    }
}

extension Controller {
    static let shared = Controller.live()

    var menuBarSymbol: String {
        compatibility.isSupported ? mode.symbol : "exclamationmark.triangle"
    }

    func copyReport() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(compatibility.text(appVersion: appVersion), forType: .string)
    }

    func perform(_ action: GuideAction) {
        switch action {
        case .openLoginItems: SMAppService.openSystemSettingsLoginItems()
        case .openApplications: NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications"))
        case .copyReport: copyReport()
        case .runDiagnostics: DiagnosticsWindow.show()
        }
    }
}

struct MenuView: View {
    @ObservedObject var c: Controller
    @ObservedObject var updates = UpdateController.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("FlickOff").font(.headline)
                Spacer()
                if c.touchBar != nil {
                    Text(c.physicalNits > 0 ? String(format: L("status.nits"), Int(c.physicalNits.rounded())) : L("status.off"))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            if let problem = c.compatibility.problem {
                GuideCard(guide: Guide(problem), labels: labels, perform: c.perform)
            } else {
                ForEach(Array(c.setupIssues.enumerated()), id: \.offset) { _, issue in
                    GuideCard(guide: Guide(issue, labels), labels: labels, perform: c.perform)
                }

                if c.controlFailed {
                    Text(L("error.controlDenied"))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if c.panelControlFailed {
                    Text(L("error.panelControlDenied"))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Picker(L("mode.label"), selection: $c.mode) {
                    ForEach(Mode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(L("brightness"))
                        Spacer()
                        Text(String(format: L("brightness.value"), Int((c.level * 100).rounded()), c.levelNits))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $c.level, in: 0...1)
                }
                .disabled(c.mode != .manual)
                .opacity(c.mode == .manual ? 1 : 0.4)

                VStack(alignment: .leading, spacing: 2) {
                    Toggle(L("preventDimming"), isOn: $c.preventDimming)
                    Text(L("preventDimming.note"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .disabled(c.mode == .off)
            }

            Toggle(L("launchAtLogin"), isOn: Binding(
                get: { c.launchAtLogin },
                set: { c.setLaunchAtLogin($0) }
            ))

            Divider()
            Toggle(L("updates.automatic"), isOn: Binding(
                get: { updates.automaticallyChecksForUpdates },
                set: { updates.setAutomaticChecks($0) }
            ))
            Button(L("updates.check")) { updates.checkForUpdates() }
                .disabled(!updates.canCheckForUpdates)
            HStack {
                Button(L("diagnostics.menu")) { DiagnosticsWindow.show() }
                    .buttonStyle(.link)
                Spacer()
                Button(L("quit")) { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .padding(14)
        .frame(width: 320)
        .onAppear { c.refreshLoginStatus() }
    }

    private var labels: SettingsLabels { SettingsLabels.current() }
}

/// Plain ObservableObject: the @State macro needs Xcode's macro plugins, which the Command Line Tools lack.
final class CopyFeedback: ObservableObject {
    @Published var copied = false
}

struct GuideCard: View {
    let guide: Guide
    let labels: SettingsLabels
    let perform: (GuideAction) -> Void
    @StateObject private var feedback = CopyFeedback()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(guide.title).fontWeight(.semibold).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            if let why = guide.why {
                Text(why)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !guide.steps.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(guide.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(index + 1).").monospacedDigit().foregroundStyle(.secondary)
                            Text(step).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .font(.callout)
            }
            HStack {
                ForEach(guide.actions, id: \.self) { action in
                    Button(action == .copyReport && feedback.copied ? L("error.reportCopied") : action.title(labels)) {
                        perform(action)
                        if action == .copyReport { feedback.copied = true }
                    }
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.08)))
    }
}

extension ProbeKind {
    var title: String {
        switch self {
        case .panelOffOn: return L("probe.panelOffOn.title")
        case .coreBrightnessLevel: return L("probe.coreBrightnessLevel.title")
        case .dimmingCoefficient: return L("probe.dimmingCoefficient.title")
        }
    }

    var question: String {
        switch self {
        case .panelOffOn: return L("probe.panelOffOn.question")
        case .coreBrightnessLevel: return L("probe.coreBrightnessLevel.question")
        case .dimmingCoefficient: return L("probe.dimmingCoefficient.question")
        }
    }
}

@MainActor
final class DiagnosticsModel: ObservableObject {
    @Published var sections: [DiagnosticsSection] = []
    @Published var collecting = true
    @Published var outcomes: [ProbeKind: ProbeOutcome] = [:]
    @Published var running: ProbeKind?
    private let runner = ProbeRunner(driver: LiveProbeDriver())

    init() {
        DispatchQueue.global(qos: .userInitiated).async {
            let sections = DiagnosticsSection.collect()
            DispatchQueue.main.async {
                self.sections = sections
                self.collecting = false
            }
        }
    }

    func run(_ kind: ProbeKind) {
        let controller = Controller.shared
        guard running == nil, controller.compatibility.isSupported else { return }
        running = kind
        let runner = self.runner
        let litThePanel = controller.beginProbe { runner.recover(from: kind, panelMayLight: $0) }
        Task {
            // Let a panel that was dark come up first, so the test starts from something visible.
            if litThePanel { await ProbeRunner.sleep(0.5) }
            let outcome = await runner.perform(kind)
            self.outcomes[kind] = outcome
            self.running = nil
            controller.endProbe()
        }
    }

    func answer(_ kind: ProbeKind, sawChange: Bool) {
        outcomes[kind] = .answered(sawChange: sawChange)
    }

    var reportText: String {
        DiagnosticsReport(compatibility: Controller.shared.compatibility, outcomes: outcomes, sections: sections)
            .text(appVersion: appVersion)
    }

    func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(reportText, forType: .string)
    }

    func save() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "FlickOff-report.txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try reportText.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}

/// Plain AppKit window so any button (menu, problem card) can open it without SwiftUI scene plumbing.
@MainActor
enum DiagnosticsWindow {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
                             styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            w.title = L("diagnostics.title")
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: DiagnosticsView(model: DiagnosticsModel()))
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct DiagnosticsView: View {
    @ObservedObject var model: DiagnosticsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("diagnostics.intro")).fixedSize(horizontal: false, vertical: true)

            GroupBox(label: Text(L("diagnostics.tests"))) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(ProbeKind.allCases) { kind in
                        ProbeRow(kind: kind, model: model)
                        if kind != ProbeKind.allCases.last { Divider() }
                    }
                }
                .padding(6)
            }

            GroupBox(label: Text(L("diagnostics.collected"))) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.collecting ? L("diagnostics.collecting")
                                          : String(format: L("diagnostics.collectedSummary"), model.sections.count))
                        .foregroundStyle(.secondary)
                    DisclosureGroup(L("diagnostics.showDetails")) {
                        ScrollView {
                            Text(model.reportText)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 200)
                    }
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Spacer()
                Button(L("diagnostics.save")) { model.save() }
                Button(L("error.copyReport")) { model.copy() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(minWidth: 520)
    }
}

struct ProbeRow: View {
    let kind: ProbeKind
    @ObservedObject var model: DiagnosticsModel

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(kind.title).fontWeight(.medium)
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if model.outcomes[kind] == .awaitingAnswer {
                Button(L("diagnostics.yes")) { model.answer(kind, sawChange: true) }
                Button(L("diagnostics.no")) { model.answer(kind, sawChange: false) }
            } else {
                Button(L("diagnostics.run")) { model.run(kind) }
                    .disabled(model.running != nil || !Controller.shared.compatibility.isSupported)
            }
        }
    }

    private var status: String {
        if model.running == kind { return L("diagnostics.watch") }
        switch model.outcomes[kind] ?? .notRun {
        case .notRun: return L("diagnostics.notRun")
        case .callsFailed(let why): return String(format: L("diagnostics.failed"), why)
        case .awaitingAnswer: return kind.question
        case .answered(let saw): return saw ? L("diagnostics.answeredYes") : L("diagnostics.answeredNo")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var sigterm: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // `kill`/`pkill` skip applicationWillTerminate; still restore the panel.
        signal(SIGTERM, SIG_IGN)
        sigterm = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        sigterm?.setEventHandler {
            Controller.shared.prepareForQuit()
            exit(0)
        }
        sigterm?.resume()

        if !Controller.shared.compatibility.isSupported {
            NSLog("FlickOff: compatibility check failed\n%@", Controller.shared.compatibility.text(appVersion: appVersion))
        }
        Controller.shared.start()
        UpdateController.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        Controller.shared.prepareForQuit()
    }
}

struct FlickOffApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var controller = Controller.shared

    var body: some Scene {
        MenuBarExtra {
            MenuView(c: controller)
        } label: {
            Image(systemName: controller.menuBarSymbol)
        }
        .menuBarExtraStyle(.window)
    }
}

@main
enum Entry {
    static func main() {
        // `FlickOff --self-test`: print the compatibility report and exit 0 (supported) or 1.
        // `FlickOff --diagnose`: self-test plus the system snapshot testers send (no probes).
        if CommandLine.arguments.contains("--diagnose") {
            let report = DiagnosticsReport(compatibility: CompatibilityReport.run(), sections: DiagnosticsSection.collect())
            print(report.text(appVersion: appVersion))
            exit(0)
        }
        // `FlickOff --setup-info [-AppleLanguages '(de)']`: every setup guide as this Mac would show it.
        if CommandLine.arguments.contains("--setup-info") {
            let names = SystemSettingsNames.read()
            let labels = SettingsLabels.current(names: names)
            print("\(SystemInfo.current.osVersion) · app language \(Bundle.main.preferredLocalizations.first ?? "?")")
            print("system names: settings=\(names.systemSettings ?? "-") general=\(names.general ?? "-") loginItems=\(names.loginItems ?? "-") openAtLogin=\(names.openAtLogin ?? "-")")
            print("used: \(labels.loginItemsPath) | \(labels.openAtLogin) | \(labels.applications)")
            let login = MainAppLoginItem().status
            print("this copy: \(Bundle.main.bundlePath) · login item \(login) · issues \(SetupInspector.issues(bundlePath: Bundle.main.bundlePath, loginItem: login, loginItemFailed: false))\n")
            let issues: [SetupIssue] = [.loginItemNeedsApproval, .loginItemFailed, .moveToApplications(translocated: true), .moveToApplications(translocated: false)]
            let problems: [CompatibilityProblem] = [.noTouchBar, .unsupportedOS, .controlDenied]
            print((issues.map { Guide($0, labels).text } + problems.map { Guide($0).text }).joined(separator: "\n\n"))
            exit(0)
        }
        if CommandLine.arguments.contains("--self-test") {
            let report = CompatibilityReport.run()
            print(report.text(appVersion: appVersion))
            exit(report.isSupported ? 0 : 1)
        }
        FlickOffApp.main()
    }
}
