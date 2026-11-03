import Foundation

/// Something the user has to do in macOS before the app works fully.
public enum SetupIssue: Equatable, Sendable {
    /// Running from Downloads or a disk image (possibly via App Translocation): login items break, updates get lost.
    case moveToApplications(translocated: Bool)
    /// macOS wants the user to approve the login item in System Settings.
    case loginItemNeedsApproval
    /// Registering the login item failed for another reason.
    case loginItemFailed
}

public enum SetupInspector {
    public static func issues(bundlePath: String, loginItem: LoginItemStatus, loginItemFailed: Bool) -> [SetupIssue] {
        var issues: [SetupIssue] = []
        if !isInApplications(bundlePath) {
            issues.append(.moveToApplications(translocated: bundlePath.contains("/AppTranslocation/")))
        }
        if loginItem == .requiresApproval {
            issues.append(.loginItemNeedsApproval)
        } else if loginItemFailed && loginItem != .enabled {
            issues.append(.loginItemFailed)
        }
        return issues
    }

    static func isInApplications(_ bundlePath: String) -> Bool {
        let path = (bundlePath as NSString).standardizingPath
        let roots = ["/Applications/", (NSHomeDirectory() as NSString).appendingPathComponent("Applications") + "/"]
        return roots.contains { path.hasPrefix($0) }
    }
}

/// Names of System Settings places exactly as this Mac shows them, in the user's language,
/// read from the system's own bundles. nil when this macOS keeps them somewhere else.
public struct SystemSettingsNames: Equatable, Sendable {
    public let systemSettings: String?
    public let general: String?
    public let loginItems: String?
    public let openAtLogin: String?

    public init(systemSettings: String?, general: String?, loginItems: String?, openAtLogin: String?) {
        self.systemSettings = systemSettings
        self.general = general
        self.loginItems = loginItems
        self.openAtLogin = openAtLogin
    }

    static let extensions = "/System/Library/ExtensionKit/Extensions"

    public static func read() -> SystemSettingsNames {
        let generalPane = Bundle(path: "\(extensions)/GeneralSettings.appex")
        let loginItemsPane = Bundle(path: "\(extensions)/LoginItems.appex")
        let app = "/System/Applications/System Settings.app"
        return SystemSettingsNames(
            systemSettings: FileManager.default.fileExists(atPath: app)
                ? clean((FileManager.default.displayName(atPath: app) as NSString).deletingPathExtension) : nil,
            general: clean(generalPane?.localizedInfoDictionary?["CFBundleDisplayName"] as? String),
            loginItems: lookup(generalPane, "Login Items & Extensions") ?? lookup(loginItemsPane, "Login Items & Extensions"),
            openAtLogin: lookup(loginItemsPane, "Open at Login")
        )
    }

    /// System strings carry typesetting characters (no-break spaces, soft hyphens) that look odd in our text.
    static func clean(_ s: String?) -> String? {
        s?.replacingOccurrences(of: "\u{a0}", with: " ").replacingOccurrences(of: "\u{ad}", with: "")
    }

    private static func lookup(_ bundle: Bundle?, _ key: String) -> String? {
        guard let bundle else { return nil }
        let missing = "\u{0}missing"
        let value = bundle.localizedString(forKey: key, value: missing, table: nil)
        return value == missing ? nil : clean(value)
    }
}
