import AppKit
import Sparkle
import SwiftUI

/// In-app updates through Sparkle, as in Sirena and Wineup. The feed (SUFeedURL), the EdDSA public key
/// (SUPublicEDKey) and the daily automatic check live in Resources/Info.plist; versions are signed with the
/// witchmymac EdDSA key and the app with the witchmymac certificate.
///
/// When Neorar runs in the background for Finder work it has no Dock icon. If Sparkle shows an update window
/// then, Neorar becomes a regular app for the length of the update session so the window isn't lost behind
/// other apps, and goes back to the background when the session ends.
@MainActor
@Observable
final class AppUpdater: NSObject {
    static let shared = AppUpdater()

    /// False while a check or an install is already under way.
    private(set) var canCheckForUpdates = false

    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var canCheckObservation: NSKeyValueObservation?
    @ObservationIgnored private var addedDockIcon = false

    private override init() {
        super.init()
    }

    /// Starts Sparkle's scheduler (daily check, from Info.plist). Call once at launch.
    /// Test copies with another bundle id don't check, unless NEORAR_UPDATES is set.
    func start() {
        guard controller == nil else { return }
        let env = ProcessInfo.processInfo.environment
        guard Bundle.main.bundleIdentifier == "app.neorar.mac" || env["NEORAR_UPDATES"] != nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: self)
        self.controller = controller
        canCheckObservation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            let canCheck = updater.canCheckForUpdates
            DispatchQueue.main.async { self?.canCheckForUpdates = canCheck }
        }
        controller.startUpdater()
    }

    /// "Verificar Atualizações…": always shows a result, even "You're up to date".
    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    private func showDockIconForUpdate() {
        guard NSApp.activationPolicy() != .regular else { return }
        addedDockIcon = true
        NSApp.setActivationPolicy(.regular)
    }

    private func hideDockIconAfterUpdate() {
        guard addedDockIcon else { return }
        addedDockIcon = false
        // Only back to the background if Neorar is still in its Finder-only mode.
        if AppDelegate.isQuiet { NSApp.setActivationPolicy(.accessory) }
    }
}

extension AppUpdater: @MainActor SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        true
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        showDockIconForUpdate()
        if !state.userInitiated, !NSApp.isActive {
            NSApp.requestUserAttention(.informationalRequest)
        }
    }

    func standardUserDriverWillFinishUpdateSession() {
        hideDockIconAfterUpdate()
    }
}

/// App menu item and the button in Settings › About: disabled while a check is already under way.
struct CheckForUpdatesButton: View {
    private var updater = AppUpdater.shared

    var body: some View {
        Button("Verificar Atualizações…") { updater.checkForUpdates() }
            .disabled(!updater.canCheckForUpdates)
    }
}
