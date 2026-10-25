import AppKit
import SwiftUI

/// NEORAR_SHOWCASE=1: screenshots for witchmymac.com, taken from a renamed copy run with
/// CFFIXED_USER_HOME pointing at a temporary home whose Downloads holds fictional archives (see
/// CLAUDE.md). No updater, Services or Finder-menu broadcast, so the installed Neorar and its
/// Finder extension are never touched. Once the window is up:
/// - NEORAR_SHOWCASE_SELECT=name1|name2 selects those items of the current folder.
/// - NEORAR_SHOWCASE_BROWSE=name opens that archive inside the window.
/// - NEORAR_SHOWCASE_SHEET=compress|info opens the Compress sheet for the selection or the Info sheet.
/// - NEORAR_SHOWCASE_SETTINGS=general|extraction|compression|rar|about opens Settings on that tab.
@MainActor
enum Showcase {
    nonisolated static let isActive = ProcessInfo.processInfo.environment["NEORAR_SHOWCASE"] == "1"
    /// Posted to the main window, which opens Settings through SwiftUI (AppKit's action needs an active app).
    nonisolated static let openSettings = Notification.Name("app.neorar.showcase.openSettings")

    static func start() {
        let environment = ProcessInfo.processInfo.environment
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            let model = AppModel.shared
            let folder = model.folder.location
            if let names = environment["NEORAR_SHOWCASE_SELECT"] {
                model.folder.selection = Set(names.split(separator: "|").map { folder.appending(path: String($0)) })
            }
            if let name = environment["NEORAR_SHOWCASE_BROWSE"] {
                model.browse(folder.appending(path: name))
            }
            switch environment["NEORAR_SHOWCASE_SHEET"] {
            case "compress": model.startCompress(Array(model.folder.selection).sorted { $0.path < $1.path })
            case "info": model.showInfo()
            default: break
            }
            if let tab = environment["NEORAR_SHOWCASE_SETTINGS"] {
                UserDefaults.standard.set(tab, forKey: PrefKey.settingsTab)
                NotificationCenter.default.post(name: openSettings, object: nil)
            }
        }
    }
}
