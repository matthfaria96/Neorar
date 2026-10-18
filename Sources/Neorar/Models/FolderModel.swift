import AppKit
import NeorarCore
import Observation
import SwiftUI

nonisolated struct FolderItem: Identifiable, Hashable, Sendable {
    var id: URL { url }
    let url: URL
    let name: String
    let isDirectory: Bool
    let isArchive: Bool
    let size: UInt64
    let modified: Date
    let kind: String
}

/// The filesystem side of the browser: the folder on screen, kept in sync with the disk.
@Observable
final class FolderModel {
    private(set) var location: URL
    private(set) var items: [FolderItem] = []
    var selection = Set<URL>()
    var sortOrder: [KeyPathComparator<FolderItem>] = [KeyPathComparator(\.name, comparator: .localizedStandard)] {
        didSet { items = sorted(items) }
    }
    private(set) var error: String?
    private(set) var isLoading = false
    var filterText = ""
    /// Paths created moments ago by Neorar; they get a "new" badge that fades out.
    private(set) var freshPaths = Set<String>()
    @ObservationIgnored private var pendingSelection = Set<String>()

    var visibleItems: [FolderItem] {
        let query = filterText.trimmingCharacters(in: .whitespaces)
        return query.isEmpty ? items : items.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    @ObservationIgnored private var history: [URL] = []
    @ObservationIgnored private var watcher: DispatchSourceFileSystemObject?
    @ObservationIgnored private var pendingReload: Task<Void, Never>?

    static var downloads: URL { FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0] }

    init() {
        location = Self.downloads
        reload()
        watch()
    }

    var canGoBack: Bool { !history.isEmpty }
    var canGoUp: Bool { location.path != "/" }
    var selectedItems: [FolderItem] { items.filter { selection.contains($0.url) } }
    var selectedArchives: [URL] { selectedItems.filter(\.isArchive).map(\.url) }

    func isFresh(_ item: FolderItem) -> Bool { freshPaths.contains(item.url.standardizedFileURL.path) }

    /// Selects and badges items that were just created here (extraction, compression, restore).
    func markNew(_ urls: [URL]) {
        let paths = Set(urls.map { $0.standardizedFileURL.path })
        guard !paths.isEmpty else { return }
        pendingSelection = paths
        withAnimation(.spring(duration: 0.4, bounce: 0.3)) { freshPaths.formUnion(paths) }
        reload(animated: true)
        Task {
            try? await Task.sleep(for: .seconds(6))
            withAnimation(.smooth(duration: 0.6)) { freshPaths.subtract(paths) }
        }
    }

    func navigate(to url: URL) {
        guard url.standardizedFileURL != location.standardizedFileURL else { return reload(animated: true) }
        history.append(location)
        move(to: url)
    }

    func goBack() {
        guard let previous = history.popLast() else { return }
        move(to: previous)
    }

    func goUp() {
        let parent = location.deletingLastPathComponent()
        let child = location
        navigate(to: parent)
        selection = [child]
    }

    private func move(to url: URL) {
        location = url
        selection.removeAll()
        filterText = ""
        freshPaths.removeAll()
        items = []
        Recents.add(url)
        reload()
        watch()
    }

    /// Re-reads the folder. Animated reloads diff the rows so additions and removals slide in and out.
    func reload(animated: Bool = false) {
        let folder = location
        isLoading = true
        Task {
            let result = await Task.detached(priority: .userInitiated) { Self.scan(folder) }.value
            guard folder == location else { return }
            isLoading = false
            switch result {
            case .success(let scanned):
                let next = sorted(scanned)
                // No withAnimation here: animating a Table's data on macOS can leave stale rows behind.
                // The grid animates its own changes (it observes the item ids).
                if next != items { items = next }
                error = nil
            case .failure(let failure):
                items = []
                error = failure.localizedDescription
            }
            selection = selection.filter { url in items.contains { $0.url == url } }
            if !pendingSelection.isEmpty {
                let matches = items.filter { pendingSelection.contains($0.url.standardizedFileURL.path) }.map(\.url)
                if !matches.isEmpty {
                    selection = Set(matches)
                    pendingSelection.removeAll()
                }
            }
        }
    }

    // MARK: - Disk watching

    private func watch() {
        watcher?.cancel()
        let descriptor = Darwin.open(location.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .delete, .rename, .extend, .attrib, .link], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scheduleReload() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        watcher = source
    }

    /// Coalesces bursts of filesystem events (an extraction writes many files) into one reload.
    private func scheduleReload() {
        pendingReload?.cancel()
        pendingReload = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            reload(animated: true)
        }
    }

    // MARK: - Scanning

    private func sorted(_ list: [FolderItem]) -> [FolderItem] {
        list.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            for comparator in sortOrder {
                switch comparator.compare(a, b) {
                case .orderedAscending: return true
                case .orderedDescending: return false
                case .orderedSame: continue
                }
            }
            return false
        }
    }

    nonisolated private static func scan(_ folder: URL) -> Result<[FolderItem], Error> {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .fileSizeKey, .contentModificationDateKey,
                                      .localizedTypeDescriptionKey]
        do {
            let urls = try FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
            return .success(urls.map { url in
                let values = try? url.resourceValues(forKeys: Set(keys))
                let isDirectory = values?.isDirectory == true && values?.isPackage != true
                let isArchive = !isDirectory && FileNaming.isArchive(url)
                return FolderItem(
                    url: url, name: url.lastPathComponent, isDirectory: isDirectory, isArchive: isArchive,
                    size: UInt64(values?.fileSize ?? 0), modified: values?.contentModificationDate ?? .distantPast,
                    kind: isArchive ? String(localized: "Arquivo \(url.pathExtension.uppercased())") : (values?.localizedTypeDescription ?? String(localized: "Documento")))
            })
        } catch {
            return .failure(error)
        }
    }
}

/// Recently visited folders for the location dropdown.
enum Recents {
    private static let key = "recentLocations"

    static var all: [URL] {
        (UserDefaults.standard.stringArray(forKey: key) ?? [])
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func add(_ url: URL) {
        var paths = UserDefaults.standard.stringArray(forKey: key) ?? []
        paths.removeAll { $0 == url.path }
        paths.insert(url.path, at: 0)
        UserDefaults.standard.set(Array(paths.prefix(8)), forKey: key)
    }
}
