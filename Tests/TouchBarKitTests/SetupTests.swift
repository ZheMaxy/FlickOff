import Foundation
import Testing
@testable import TouchBarKit

@Suite("Setup guidance")
struct SetupTests {
    static let installed = "/Applications/FlickOff.app"
    static let translocated = "/private/var/folders/xy/abc/T/AppTranslocation/1234-ABCD/d/FlickOff.app"
    static let downloads = NSHomeDirectory() + "/Downloads/FlickOff.app"

    @Test(arguments: [
        (installed, true),
        (NSHomeDirectory() + "/Applications/FlickOff.app", true),
        (downloads, false),
        (translocated, false),
        ("/Volumes/FlickOff/FlickOff.app", false),
        ("/Applications/../Users/x/FlickOff.app", false),
    ])
    func recognisesTheApplicationsFolder(path: String, inApplications: Bool) {
        #expect(SetupInspector.isInApplications(path) == inApplications)
    }

    @Test func installedAndApprovedMeansNothingToDo() {
        #expect(SetupInspector.issues(bundlePath: Self.installed, loginItem: .enabled, loginItemFailed: false).isEmpty)
    }

    @Test func translocatedCopyIsToldToMove() {
        let issues = SetupInspector.issues(bundlePath: Self.translocated, loginItem: .disabled, loginItemFailed: false)
        #expect(issues == [.moveToApplications(translocated: true)])
    }

    @Test func copyInDownloadsIsToldToMove() {
        let issues = SetupInspector.issues(bundlePath: Self.downloads, loginItem: .disabled, loginItemFailed: false)
        #expect(issues == [.moveToApplications(translocated: false)])
    }

    @Test func pendingApprovalIsReported() {
        let issues = SetupInspector.issues(bundlePath: Self.installed, loginItem: .requiresApproval, loginItemFailed: false)
        #expect(issues == [.loginItemNeedsApproval])
    }

    @Test func failedRegistrationIsReportedUntilItWorks() {
        #expect(SetupInspector.issues(bundlePath: Self.installed, loginItem: .disabled, loginItemFailed: true) == [.loginItemFailed])
        #expect(SetupInspector.issues(bundlePath: Self.installed, loginItem: .enabled, loginItemFailed: true).isEmpty)
    }

    @Test func systemSettingsNamesAreReadFromThisMac() {
        let names = SystemSettingsNames.read()
        #expect(names.systemSettings?.isEmpty == false)
        // Private System Settings bundles vary by macOS release; nil activates the UI fallback.
        for name in [names.systemSettings, names.general, names.loginItems, names.openAtLogin].compactMap({ $0 }) {
            #expect(!name.contains("\u{a0}") && !name.contains("\u{ad}"), "\(name)")
        }
    }

    @Test func cleansTypesettingCharacters() {
        #expect(SystemSettingsNames.clean("System\u{ad}einstellungen") == "Systemeinstellungen")
        #expect(SystemSettingsNames.clean("Объекты входа и\u{a0}расширения") == "Объекты входа и расширения")
    }
}

@Suite("Setup in the controller")
@MainActor
struct ControllerSetupTests {
    @Test func doesNotRegisterALoginItemFromOutsideApplications() {
        let h = Harness()
        let c = h.makeController(bundlePath: SetupTests.downloads)
        c.configureLoginItemOnFirstLaunch()
        #expect(h.loginItem.registerCount == 0)
        #expect(c.setupIssues == [.moveToApplications(translocated: false)])

        // Moved into Applications and relaunched: now it registers.
        let moved = h.makeController()
        moved.configureLoginItemOnFirstLaunch()
        #expect(h.loginItem.registerCount == 1)
        #expect(moved.setupIssues.isEmpty)
    }

    @Test func approvalGivenInSystemSettingsClearsTheIssue() {
        let h = Harness()
        h.loginItem.status = .requiresApproval
        let c = h.makeController()
        c.refreshLoginStatus()
        #expect(c.setupIssues == [.loginItemNeedsApproval])

        h.loginItem.status = .enabled
        for _ in 0..<10 { c.tick() }
        #expect(c.setupIssues.isEmpty)
    }

    @Test func failedRegistrationShowsAGuide() {
        let h = Harness()
        h.loginItem.failNextCall = true
        let c = h.makeController()
        c.setLaunchAtLogin(true)
        #expect(c.setupIssues == [.loginItemFailed])

        c.setLaunchAtLogin(true)
        #expect(c.setupIssues.isEmpty)
    }
}
