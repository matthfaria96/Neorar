import AppKit
import NeorarCore
import SwiftUI

enum OpenBehavior: String, CaseIterable, Identifiable {
    case extract, browse
    var id: String { rawValue }
    var title: String { self == .extract ? String(localized: "Extrair imediatamente") : String(localized: "Mostrar o conteúdo primeiro") }
}

enum DestinationMode: String, CaseIterable, Identifiable {
    case sameFolder, desktop, downloads, lastUsed, custom, ask
    var id: String { rawValue }
    var title: String {
        switch self {
        case .sameFolder: String(localized: "Mesma pasta do arquivo")
        case .desktop: String(localized: "Mesa")
        case .downloads: String(localized: "Downloads")
        case .lastUsed: String(localized: "Último destino usado")
        case .custom: String(localized: "Pasta escolhida")
        case .ask: String(localized: "Perguntar sempre")
        }
    }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    /// Applies the choice to every window; `system` follows macOS.
    func apply() {
        NSApp.appearance = switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// Interface languages, listed alphabetically by their Portuguese name.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, de, es, fr, en, ptBR = "pt-BR"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: String(localized: "Idioma do sistema")
        case .de: String(localized: "Alemão") + " · Deutsch"
        case .es: String(localized: "Espanhol") + " · Español"
        case .fr: String(localized: "Francês") + " · Français"
        case .en: String(localized: "Inglês") + " · English"
        case .ptBR: "Português"
        }
    }

    /// macOS reads the app's languages at launch from AppleLanguages.
    static var current: AppLanguage {
        guard let list = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?["AppleLanguages"] as? [String],
              let first = list.first else { return .system }
        return AppLanguage(rawValue: first) ?? (first.hasPrefix("pt") ? .ptBR : .system)
    }

    func apply() {
        if self == .system {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([rawValue], forKey: "AppleLanguages")
        }
    }
}

/// What "Comprimir com o Neorar" in Finder's menu does.
enum FinderCompressMode: String, CaseIterable, Identifiable {
    case ask, sevenZip, zip, tarGz, tarXz, tarBz2
    var id: String { rawValue }
    var format: CompressionFormat? { CompressionFormat(rawValue: rawValue) }
    var title: String {
        switch self {
        case .ask: String(localized: "Perguntar (abrir a janela Comprimir)")
        case .sevenZip: String(localized: "Comprimir direto em 7Z")
        case .zip: String(localized: "Comprimir direto em ZIP")
        case .tarGz: String(localized: "Comprimir direto em TAR.GZ")
        case .tarXz: String(localized: "Comprimir direto em TAR.XZ")
        case .tarBz2: String(localized: "Comprimir direto em TAR.BZ2")
        }
    }
}

enum IconStyle: String, CaseIterable, Identifiable {
    case glass, color
    var id: String { rawValue }
}

enum ViewMode: String, CaseIterable, Identifiable {
    case list, grid
    var id: String { rawValue }
}

/// UserDefaults keys, shared by @AppStorage in views and by the models.
enum PrefKey {
    static let openBehavior = "openBehavior"
    static let destinationMode = "destinationMode"
    static let customDestination = "customDestination"
    static let lastDestination = "lastDestination"
    static let folderPolicy = "folderPolicy"
    static let conflictPolicy = "conflictPolicy"
    static let folderDate = "folderDate"
    static let fileDates = "fileDates"
    static let trashArchive = "trashArchive"
    static let removeJunk = "removeJunk"
    static let revealAfter = "revealAfter"
    static let codePage = "codePage"
    static let maxConcurrent = "maxConcurrent"
    static let compressFormat = "compressFormat"
    static let compressLevel = "compressLevel"
    static let compressExcludeJunk = "compressExcludeJunk"
    static let compressSolid = "compressSolid"
    static let viewMode = "viewMode"
    static let iconStyle = "iconStyle"
    static let theme = "theme"
    static let finderCompress = "finderCompress"
    static let onboardingDone = "onboardingDone"
    static let finderShowExtract = "finderShowExtract"
    static let finderShowCompress = "finderShowCompress"
    static let settingsTab = "settingsTab"
}

enum Preferences {
    static var defaults: UserDefaults { .standard }

    static func registerDefaults() {
        // "Nunca" was removed from the folder options; move anyone who had it to the safe default.
        if defaults.string(forKey: PrefKey.folderPolicy) == FolderPolicy.never.rawValue {
            defaults.set(FolderPolicy.smart.rawValue, forKey: PrefKey.folderPolicy)
        }
        defaults.register(defaults: [
            PrefKey.openBehavior: OpenBehavior.extract.rawValue,
            PrefKey.destinationMode: DestinationMode.sameFolder.rawValue,
            PrefKey.folderPolicy: FolderPolicy.smart.rawValue,
            PrefKey.conflictPolicy: ConflictPolicy.rename.rawValue,
            PrefKey.folderDate: DateChoice.now.rawValue,
            PrefKey.fileDates: DateChoice.original.rawValue,
            PrefKey.trashArchive: false,
            PrefKey.removeJunk: true,
            PrefKey.revealAfter: false,
            PrefKey.codePage: 0,
            PrefKey.maxConcurrent: 2,
            PrefKey.compressFormat: CompressionFormat.sevenZip.rawValue,
            PrefKey.viewMode: ViewMode.list.rawValue,
            PrefKey.iconStyle: IconStyle.color.rawValue,
            PrefKey.theme: AppTheme.system.rawValue,
            PrefKey.finderCompress: FinderCompressMode.sevenZip.rawValue,
            PrefKey.finderShowExtract: true,
            PrefKey.finderShowCompress: true,
            PrefKey.compressLevel: CompressionLevel.normal.rawValue,
            PrefKey.compressExcludeJunk: true,
            PrefKey.compressSolid: true,
        ])
    }

    static var openBehavior: OpenBehavior {
        OpenBehavior(rawValue: defaults.string(forKey: PrefKey.openBehavior) ?? "") ?? .extract
    }

    static var maxConcurrent: Int { max(1, min(8, defaults.integer(forKey: PrefKey.maxConcurrent))) }
    static var revealAfter: Bool { defaults.bool(forKey: PrefKey.revealAfter) }

    /// Resolves the destination for an archive, asking the user when configured to. Nil means cancelled.
    static func destination(for archive: URL) -> URL? {
        let mode = DestinationMode(rawValue: defaults.string(forKey: PrefKey.destinationMode) ?? "") ?? .sameFolder
        let fileManager = FileManager.default
        switch mode {
        case .sameFolder:
            return archive.deletingLastPathComponent()
        case .desktop:
            return fileManager.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        case .downloads:
            return fileManager.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        case .lastUsed:
            if let path = defaults.string(forKey: PrefKey.lastDestination), fileManager.fileExists(atPath: path) {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
            return askForFolder(title: String(localized: "Escolha onde extrair “\(archive.lastPathComponent)”"), near: archive)
        case .custom:
            if let path = defaults.string(forKey: PrefKey.customDestination), fileManager.fileExists(atPath: path) {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
            return archive.deletingLastPathComponent()
        case .ask:
            return askForFolder(title: String(localized: "Escolha onde extrair “\(archive.lastPathComponent)”"), near: archive)
        }
    }

    /// Destination without side effects (never asks): nil when the user is asked each time.
    static func destination(forPreview archive: URL) -> URL? {
        let mode = DestinationMode(rawValue: defaults.string(forKey: PrefKey.destinationMode) ?? "") ?? .sameFolder
        return mode == .sameFolder ? archive.deletingLastPathComponent() : nil
    }

    static func askForFolder(title: String, near url: URL?) -> URL? {
        let panel = NSOpenPanel()
        panel.message = title
        panel.prompt = String(localized: "Escolher")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if let path = defaults.string(forKey: PrefKey.lastDestination) {
            panel.directoryURL = URL(fileURLWithPath: path)
        } else if let url {
            panel.directoryURL = url.deletingLastPathComponent()
        }
        guard panel.runModal() == .OK, let chosen = panel.url else { return nil }
        defaults.set(chosen.path, forKey: PrefKey.lastDestination)
        return chosen
    }

    /// Tells the Finder extension which items to show (it can't read these settings itself).
    static func broadcastFinderMenu() {
        let extract = defaults.bool(forKey: PrefKey.finderShowExtract) ? "1" : "0"
        let compress = defaults.bool(forKey: PrefKey.finderShowCompress) ? "1" : "0"
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("app.neorar.finderMenuChanged"), object: "extract=\(extract);compress=\(compress)",
            userInfo: nil, deliverImmediately: true)
    }

    /// "Extrair Aqui" never scatters several items in the current folder: they always get a folder named after the archive.
    /// (A single top-level item is placed directly, so "Projeto.zip" gives "Projeto/", not "Projeto/Projeto/".)
    static var safeHereFolderPolicy: FolderPolicy {
        FolderPolicy(rawValue: defaults.string(forKey: PrefKey.folderPolicy) ?? "") == .always ? .always : .smart
    }

    static func extractionOptions(destination: URL) -> ExtractionOptions {
        var options = ExtractionOptions(destination: destination)
        // "Nunca" is no longer offered: a stored value from older builds falls back to the safe default.
        let stored = FolderPolicy(rawValue: defaults.string(forKey: PrefKey.folderPolicy) ?? "") ?? .smart
        options.folderPolicy = stored == .never ? .smart : stored
        options.conflictPolicy = ConflictPolicy(rawValue: defaults.string(forKey: PrefKey.conflictPolicy) ?? "") ?? .rename
        options.folderDate = DateChoice(rawValue: defaults.string(forKey: PrefKey.folderDate) ?? "") ?? .now
        options.fileDates = DateChoice(rawValue: defaults.string(forKey: PrefKey.fileDates) ?? "") ?? .original
        options.trashArchiveAfter = defaults.bool(forKey: PrefKey.trashArchive)
        options.removeJunk = defaults.bool(forKey: PrefKey.removeJunk)
        let page = defaults.integer(forKey: PrefKey.codePage)
        options.codePage = page > 0 ? page : nil
        return options
    }

    static func compressionDefaults() -> CompressionOptions {
        var options = CompressionOptions()
        options.format = CompressionFormat(rawValue: defaults.string(forKey: PrefKey.compressFormat) ?? "") ?? .sevenZip
        options.level = CompressionLevel(rawValue: defaults.integer(forKey: PrefKey.compressLevel)) ?? .normal
        options.excludeMacJunk = defaults.bool(forKey: PrefKey.compressExcludeJunk)
        options.solid = defaults.bool(forKey: PrefKey.compressSolid)
        return options
    }
}
