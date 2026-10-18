import AppKit
import FinderSync
import Observation
import UniformTypeIdentifiers

/// What Neorar needs from macOS, checked live for the onboarding and Settings › Geral.
@Observable
final class SetupModel {
    private(set) var finderExtension = false
    private(set) var downloadsAccess = false
    private(set) var defaultApp = false
    private(set) var settingDefault = false

    /// Archive types Neorar offers to open by default (Finder's double-click).
    static let defaultTypes: [UTType] = [
        UTType("com.rarlab.rar-archive"), UTType("org.7-zip.7-zip-archive"),
    ].compactMap { $0 }

    init() {
        refresh()
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    /// Required items still missing (the optional rar tool is not counted).
    var pendingCount: Int { [finderExtension, downloadsAccess, defaultApp].filter { !$0 }.count }

    func refresh() {
        finderExtension = FIFinderSyncController.isExtensionEnabled
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        downloadsAccess = (try? FileManager.default.contentsOfDirectory(atPath: downloads.path)) != nil
        let me = Bundle.main.bundleURL.standardizedFileURL
        defaultApp = Self.defaultTypes.allSatisfy { type in
            NSWorkspace.shared.urlForApplication(toOpen: type)?.standardizedFileURL == me
        }
    }

    func enableFinderExtension() {
        FIFinderSyncController.showExtensionManagementInterface()
    }

    /// Reading the folder makes macOS ask for permission the first time; afterwards it lives in System Settings.
    func requestDownloads() {
        refresh()
        if !downloadsAccess,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") {
            NSWorkspace.shared.open(url)
        }
    }

    func makeDefault() {
        settingDefault = true
        let app = Bundle.main.bundleURL
        Task {
            for type in Self.defaultTypes {
                try? await NSWorkspace.shared.setDefaultApplication(at: app, toOpen: type)
            }
            settingDefault = false
            refresh()
        }
    }
}
