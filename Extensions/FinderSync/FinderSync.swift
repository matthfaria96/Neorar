// Finder Sync extension: adds Neorar's actions to Finder's right-click menu.
// It only builds the menu; the work happens in the main app, reached through neorar:// URLs.
import AppKit
import FinderSync

final class FinderSync: FIFinderSync {
    private static let archiveExtensions: Set<String> = [
        "rar", "zip", "7z", "tar", "gz", "tgz", "bz2", "tbz", "tbz2", "xz", "txz", "zst", "tzst", "lzma", "z", "taz",
        "cab", "iso", "xar", "cpio", "cpgz", "pax", "jar", "cbz", "cbr", "cb7", "zipx", "sit", "sitx", "lzh",
        "lha", "arj", "ace", "wim", "rpm", "deb", "001",
    ]

    /// Posted by the Neorar app with "extract=1;compress=0"-style text whenever Settings change.
    static let menuChanged = Notification.Name("app.neorar.finderMenuChanged")
    private static let showExtractKey = "showExtract"
    private static let showCompressKey = "showCompress"

    override init() {
        super.init()
        // Watch every volume so the menu is available everywhere in Finder.
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
        UserDefaults.standard.register(defaults: [Self.showExtractKey: true, Self.showCompressKey: true])
        // The extension is sandboxed and can't read the app's settings, so the app tells it; the choice is kept here.
        DistributedNotificationCenter.default().addObserver(
            forName: Self.menuChanged, object: nil, queue: .main
        ) { note in
            guard let text = note.object as? String else { return }
            for pair in text.split(separator: ";") {
                let parts = pair.split(separator: "=")
                guard parts.count == 2 else { continue }
                let on = parts[1] == "1"
                switch parts[0] {
                case "extract": UserDefaults.standard.set(on, forKey: Self.showExtractKey)
                case "compress": UserDefaults.standard.set(on, forKey: Self.showCompressKey)
                default: break
                }
            }
        }
    }

    private static func isArchive(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if archiveExtensions.contains(ext) { return true }
        return ext.range(of: #"^(r\d{2,3}|z\d{2})$"#, options: .regularExpression) != nil
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems else { return nil }
        let items = FIFinderSyncController.default().selectedItemURLs() ?? []
        guard !items.isEmpty else { return nil }
        let menu = NSMenu(title: "Neorar")
        // Just two actions, each switchable in Neorar › Ajustes › Geral.
        if UserDefaults.standard.bool(forKey: Self.showExtractKey), items.contains(where: Self.isArchive) {
            menu.addItem(item(NSLocalizedString("Extrair com Neorar", comment: ""), symbol: "arrow.down.doc",
                              action: #selector(extractHere(_:))))
        }
        if UserDefaults.standard.bool(forKey: Self.showCompressKey) {
            menu.addItem(item(NSLocalizedString("Comprimir com Neorar", comment: ""), symbol: "archivebox",
                              action: #selector(compress(_:))))
        }
        return menu.items.isEmpty ? nil : menu
    }

    /// Outline symbol drawn like Finder's own items. Finder doesn't tint template images from extensions,
    /// so the menu's text colour is resolved here for the current light/dark appearance.
    private func item(_ title: String, symbol: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        var color = NSColor.labelColor
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            color = NSColor(cgColor: NSColor.labelColor.cgColor) ?? .labelColor
        }
        let configuration = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        if let glyph = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) {
            item.image = Self.menuIcon(glyph)
        }
        item.target = self
        return item
    }

    /// Finder stretches menu images to fill the icon slot, so the glyph is centred on a fixed 16 pt canvas
    /// (rendered at 2x) to match the margins of Finder's own icons.
    private static func menuIcon(_ glyph: NSImage) -> NSImage {
        let side: CGFloat = 16, scale: CGFloat = 2
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(side * scale), pixelsHigh: Int(side * scale),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return glyph }
        rep.size = NSSize(width: side, height: side)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let size = glyph.size
        glyph.draw(in: NSRect(x: (side - size.width) / 2, y: (side - size.height) / 2, width: size.width, height: size.height))
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }

    @objc private func extractHere(_ sender: AnyObject?) { send("extract-here", archivesOnly: true) }
    @objc private func compress(_ sender: AnyObject?) { send("compress", archivesOnly: false) }

    private func send(_ action: String, archivesOnly: Bool) {
        var items = FIFinderSyncController.default().selectedItemURLs() ?? []
        if archivesOnly { items = items.filter(Self.isArchive) }
        guard !items.isEmpty else { return }
        var components = URLComponents()
        components.scheme = "neorar"
        components.host = action
        components.queryItems = items.map { URLQueryItem(name: "path", value: $0.path) }
        guard let url = components.url else { return }
        // Extraction runs quietly in the background; Neorar comes forward by itself only when it needs the user.
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = action != "extract-here"
        NSWorkspace.shared.open(url, configuration: configuration)
    }
}
