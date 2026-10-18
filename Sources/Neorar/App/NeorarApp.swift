import AppKit
import NeorarCore
import SwiftUI

@main
struct NeorarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.shared

    var body: some Scene {
        Window("Neorar", id: "main") {
            MainView()
                .environment(model)
                .frame(minWidth: 760, minHeight: 520)
        }
        .defaultSize(width: 1060, height: 680)
        // Background (Finder) runs quit with the window hidden; restoring that would open Neorar with no window.
        .restorationBehavior(.disabled)
        .windowToolbarStyle(.unified)
        .commands {
            ViewCommands()
            CommandGroup(after: .pasteboard) {
                Button("Copiar Caminho") { model.copyCurrentPath() }
                    .keyboardShortcut("c", modifiers: [.command, .option])
            }
            CommandGroup(replacing: .newItem) {
                Button("Abrir…") { model.chooseLocation() }
                    .keyboardShortcut("o")
                Button("Ir para Downloads") { model.navigate(to: FolderModel.downloads) }
                    .keyboardShortcut("l", modifiers: [.command, .option])
                Divider()
                Button("Adicionar ao Arquivo…") { model.compressSelection() }
                    .keyboardShortcut("a", modifiers: [.command, .option])
                Button("Extrair Aqui") { model.extractSelection(here: true) }
                    .keyboardShortcut("e", modifiers: [.command, .option])
                Divider()
                Button("Testar Arquivo") { model.testSelection() }
                    .keyboardShortcut("t", modifiers: [.command, .option])
                Button("Reparar Arquivo…") { if let target = model.repairTarget { model.repair(target) } }
                    .disabled(model.repairTarget == nil)
            }
        }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let services = ServiceProvider()

    /// True while Neorar runs only for Finder work (double-click, Dock drop, Finder menu): no window, no Dock icon.
    /// It quits on its own when that work is done; opening Neorar normally turns it into the regular app.
    private(set) static var isQuiet = false
    private static var receivedFinderWork = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Launched to open a file or a neorar:// link (not by the user opening the app): stay in the background.
        // `open -a` also reports a non-default launch, so the window comes back if no Finder work shows up.
        if notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool == false {
            Self.isQuiet = true
            NSApp.setActivationPolicy(.accessory)
            NSApp.windows.filter(Self.isMainWindow).forEach { $0.orderOut(nil) }
            NotificationCenter.default.addObserver(self, selector: #selector(keepWindowHidden(_:)),
                                                   name: NSWindow.didUpdateNotification, object: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                if Self.isQuiet, !Self.receivedFinderWork { Self.showMainWindow() }
            }
        }
        NSApp.servicesProvider = services
        NSUpdateDynamicServices()
        ExtractionService.clearPreviewCache()
        (AppTheme(rawValue: UserDefaults.standard.string(forKey: PrefKey.theme) ?? "") ?? .system).apply()
        Preferences.broadcastFinderMenu()
    }

    /// SwiftUI shows the main window at launch; in background mode it never stays on screen.
    @objc private func keepWindowHidden(_ note: Notification) {
        guard Self.isQuiet, let window = note.object as? NSWindow, window.isVisible, Self.isMainWindow(window) else { return }
        window.orderOut(nil)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        Self.receivedFinderWork = true
        // neorar:// links come from the Finder extension; everything else is a file opened in Finder.
        let actions = urls.filter { $0.scheme == "neorar" }
        actions.forEach { AppModel.shared.handleAction($0) }
        let files = urls.filter(\.isFileURL)
        guard !files.isEmpty else { return }
        // Finder brings Neorar forward on a double-click; step aside so only the result shows up.
        if !Self.isQuiet { DispatchQueue.main.async { NSApp.hide(nil) } }
        AppModel.shared.open(files, fromFinder: true)
    }

    /// The user opened Neorar (Dock, Launchpad, Spotlight) while it was working in the background.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if Self.isQuiet { Self.showMainWindow() }
        return true
    }

    /// Leaves background mode and shows the main window (e.g. Finder's compress set to “ask”).
    static func showMainWindow() {
        isQuiet = false
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        NSApp.windows.first(where: isMainWindow)?.makeKeyAndOrderFront(nil)
    }

    /// Quits a background-only launch once its Finder work is done.
    static func quitIfIdle() {
        guard isQuiet else { return }
        Task {
            try? await Task.sleep(for: .seconds(1))
            let model = AppModel.shared
            guard isQuiet, !model.hasActiveWork, model.passwordRequests.isEmpty, model.conflictRequests.isEmpty else { return }
            NSApp.terminate(nil)
        }
    }

    /// Asks the user something about Finder work with a small system alert, never the main window.
    static func runAlert(_ alert: NSAlert) -> NSApplication.ModalResponse {
        // Activating would bring the (hidden) main window back with the alert; keep it out of the way meanwhile.
        let main = NSApp.windows.first(where: isMainWindow)
        let restore = !isQuiet && main != nil
        main?.orderOut(nil)
        NSApp.activate()
        alert.window.level = .floating
        let response = alert.runModal()
        if restore, let main {
            NSApp.hide(nil)
            main.orderFront(nil)
        }
        return response
    }

    private static func isMainWindow(_ window: NSWindow) -> Bool {
        window.identifier?.rawValue.hasPrefix("main") == true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !AppModel.shared.hasActiveWork
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard AppModel.shared.hasActiveWork else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Há operações em andamento"
        alert.informativeText = "Se você sair agora, as extrações e compactações em curso serão canceladas."
        alert.addButton(withTitle: "Continuar no Neorar")
        alert.addButton(withTitle: "Sair Mesmo Assim")
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.cancelAll()
        ExtractionService.clearPreviewCache()
    }
}

/// Finder › Serviços: "Extrair com o Neorar" and "Compactar com o Neorar".
final class ServiceProvider: NSObject {
    @objc func extractFiles(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = Self.fileURLs(pasteboard)
        guard !urls.isEmpty else { return }
        AppModel.shared.enqueueExtraction(urls)
        NSApp.activate()
    }

    @objc func compressFiles(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = Self.fileURLs(pasteboard)
        guard !urls.isEmpty else { return }
        AppModel.shared.startCompress(urls)
        NSApp.activate()
    }

    private static func fileURLs(_ pasteboard: NSPasteboard) -> [URL] {
        (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }
}

/// View menu: list / icon modes, like Finder.
struct ViewCommands: Commands {
    @AppStorage(PrefKey.viewMode) private var viewMode = ViewMode.list.rawValue
    @AppStorage(PrefKey.iconStyle) private var iconStyle = IconStyle.color.rawValue

    var body: some Commands {
        CommandGroup(before: .toolbar) {
            Picker("Visualização", selection: $viewMode.animation(.smooth(duration: 0.22))) {
                Text("como Lista").tag(ViewMode.list.rawValue).keyboardShortcut("1")
                Text("como Ícones").tag(ViewMode.grid.rawValue).keyboardShortcut("2")
            }
            .pickerStyle(.inline)
            Divider()
            Picker("Ícones da Barra", selection: $iconStyle.animation(.smooth(duration: 0.3))) {
                Text("Vidro").tag(IconStyle.glass.rawValue)
                Text("Coloridos").tag(IconStyle.color.rawValue)
            }
            Divider()
        }
    }
}

