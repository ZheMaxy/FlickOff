import Combine
import Foundation
import Sparkle

/// Sparkle owns scheduling, user preferences, signature verification and installation.
/// FlickOff has no Dock icon, so an update alert opening behind other windows could go unseen for
/// weeks. Scheduled updates are announced on the menu bar icon and in the menu instead.
@MainActor
final class UpdateController: NSObject, ObservableObject {
    static let shared = UpdateController()

    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false
    /// A scheduled check found this version and nobody has looked at it yet.
    @Published private(set) var waitingUpdateVersion: String?
    /// Everything is a beta for now, so this starts on. Stable users can turn it off once a stable release exists.
    @Published private(set) var includesBetaUpdates: Bool
    private var controller: SPUStandardUpdaterController!
    private var started = false

    private nonisolated static let includeBetasKey = "includeBetaUpdates"

    private nonisolated static var betasAreIncluded: Bool {
        UserDefaults.standard.object(forKey: includeBetasKey) as? Bool ?? true
    }

    override init() {
        includesBetaUpdates = Self.betasAreIncluded
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$canCheckForUpdates)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$automaticallyChecksForUpdates)
    }

    func start() {
        guard !started else { return }
        started = true
        controller.startUpdater()
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    func setAutomaticChecks(_ enabled: Bool) {
        controller.updater.automaticallyChecksForUpdates = enabled
    }

    func setIncludesBetaUpdates(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.includeBetasKey)
        includesBetaUpdates = enabled
    }

    fileprivate func announce(_ version: String?) {
        if let version { NSLog("FlickOff: update %@ is waiting in the menu", version) }
        waitingUpdateVersion = version
    }
}

extension UpdateController: SPUUpdaterDelegate {
    nonisolated func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        Self.betasAreIncluded ? ["beta"] : []
    }
}

/// Sparkle calls these on the main thread.
extension UpdateController: SPUStandardUserDriverDelegate {
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Sparkle's alert is fine when the user is looking, for example right after launch.
    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        immediateFocus
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        guard !handleShowingUpdate else { return }
        let version = update.displayVersionString
        MainActor.assumeIsolated { announce(version) }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        MainActor.assumeIsolated { announce(nil) }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated { announce(nil) }
    }
}
