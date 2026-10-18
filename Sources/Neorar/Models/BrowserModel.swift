import AppKit
import SwiftUI
import NeorarCore
import Observation

/// One row of the archive outline. Folders that the archive only implies are synthesized.
struct ArchiveNode: Identifiable, Hashable {
    let id: String          // archive path
    let name: String
    let isDirectory: Bool
    let size: UInt64
    let packedSize: UInt64
    let modified: Date?
    let isEncrypted: Bool
    var children: [ArchiveNode]?

    var kindDescription: String {
        isDirectory ? String(localized: "Pasta") : (name as NSString).pathExtension.uppercased().nilIfEmpty.map { String(localized: "Arquivo \($0)") } ?? String(localized: "Arquivo")
    }
}

@Observable
final class BrowserModel {
    enum State {
        case loading
        case ready
        case needsPassword
        case failed(ArchiveError)
    }

    enum SortKey: String { case name, size, date }

    let archive: URL
    var state: State = .loading
    var listing: ArchiveListing?
    var engine: (any ArchiveEngine)?
    var password: String?
    @ObservationIgnored private var draggedFiles: [String: Task<URL, any Error>] = [:]
    var codePage: Int?
    var detectedCodePage: Int?
    var roots: [ArchiveNode] = []
    var searchText = ""
    var selection = Set<String>()
    var sortKey: SortKey = .name
    var ascending = true
    var previewURL: URL?
    /// Folder inside the archive shown by the grid view ("" is the root).
    var gridPath = ""
    var busyMessage: String?

    @ObservationIgnored private weak var app: AppModel?

    init(archive: URL, app: AppModel) {
        self.archive = archive
        self.app = app
    }

    var isZip: Bool { listing?.format == .zip }

    /// Whether this archive can be edited in place, and why not when it cannot.
    var editability: Result<ArchiveEditor.Tool, ArchiveError>? {
        listing.map { ArchiveEditor.tool(for: archive, listing: $0) }
    }

    var isEditable: Bool { if case .success = editability { true } else { false } }

    var editBlockedReason: String? {
        if case .failure(let error) = editability { return error.errorDescription }
        return nil
    }

    func load() {
        state = .loading
        Task {
            do {
                if codePage == nil, ArchiveFormat.sniff(archive) == .zip {
                    let detected = await Task.detached { ZipEncodingDetector.detect(self.archive) }.value
                    detectedCodePage = detected
                    let forced = UserDefaults.standard.integer(forKey: PrefKey.codePage)
                    codePage = forced > 0 ? forced : detected
                }
                let (listing, engine) = try await Engines.list(archive, password: password, codePage: codePage)
                self.listing = listing
                self.engine = engine
                roots = Self.sorted(Self.buildTree(listing.entries), by: sortKey, ascending: ascending)
                state = .ready
            } catch let error as ArchiveError {
                handle(error)
            } catch {
                state = .failed(.failed(error.localizedDescription))
            }
        }
    }

    private func handle(_ error: ArchiveError) {
        switch error {
        case .passwordRequired, .wrongPassword:
            state = .needsPassword
            app?.requestPassword(for: archive.lastPathComponent, wrong: error == .wrongPassword) { [weak self] password in
                self?.password = password
                self?.load()
            } cancel: { [weak self] in
                self?.state = .failed(.passwordRequired)
            }
        default:
            state = .failed(error)
        }
    }

    func changeEncoding(_ page: Int?) {
        codePage = page ?? detectedCodePage
        selection.removeAll()
        load()
    }

    /// Search shows a flat list of matches; otherwise the outline.
    var visibleRoots: [ArchiveNode] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty, let listing else { return roots }
        return listing.entries.lazy
            .filter { $0.name.localizedCaseInsensitiveContains(query) }
            .prefix(5000)
            .map { ArchiveNode(id: $0.path, name: $0.path, isDirectory: $0.isDirectory, size: $0.size,
                               packedSize: $0.packedSize, modified: $0.modified, isEncrypted: $0.isEncrypted, children: nil) }
    }

    /// Nodes for the grid: the current archive folder, or flat search results.
    var gridNodes: [ArchiveNode] {
        guard searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return visibleRoots }
        var nodes = roots
        for component in gridPath.split(separator: "/") {
            guard let next = nodes.first(where: { $0.name == component })?.children else { return [] }
            nodes = next
        }
        return nodes
    }

    func enterGridFolder(_ node: ArchiveNode) {
        withAnimation(.smooth(duration: 0.25)) {
            gridPath = node.id
            selection.removeAll()
        }
    }

    func gridUp() {
        withAnimation(.smooth(duration: 0.25)) {
            let parent = (gridPath as NSString).deletingLastPathComponent
            selection = [gridPath]
            gridPath = parent
        }
    }

    func entry(for path: String) -> ArchiveEntry? {
        listing?.entries.first { $0.path == path }
    }

    // MARK: - Actions

    func extract(selectionOnly: Bool, chooseDestination: Bool) {
        let destination: URL?
        if chooseDestination {
            guard let chosen = Preferences.askForFolder(title: String(localized: "Escolha onde extrair"), near: archive) else { return }
            destination = chosen
        } else {
            destination = nil
        }
        app?.enqueueExtraction(from: self, selection: selectionOnly && !selection.isEmpty ? selection : nil, destination: destination)
    }

    func quickLook(_ path: String? = nil) {
        guard let path = path ?? selection.first else { return }
        withExtracted(path) { [weak self] url in self?.previewURL = url }
    }

    func open(_ path: String) {
        withExtracted(path) { url in NSWorkspace.shared.open(url) }
    }

    /// Extracts one entry to the preview cache when it is dropped outside Neorar (Finder copies it from there).
    func extractForDrag(_ path: String) async throws -> URL {
        guard let listing, let engine else { throw ArchiveError.cancelled }
        let entry = entry(for: path) ?? ArchiveEntry(id: -1, path: path, isDirectory: true, size: 0, packedSize: 0,
                                                     modified: nil, isEncrypted: false)
        // The drop asks more than once (sometimes at the same time); share one extraction per entry.
        if let running = draggedFiles[path], let url = try? await running.value,
           FileManager.default.fileExists(atPath: url.path) { return url }
        let archive = archive, password = password
        let task = Task { [weak self] in
            self?.busyMessage = String(localized: "Preparando “\(entry.name)”…")
            defer { self?.busyMessage = nil }
            return try await ExtractionService.extractForPreview(archive, entry: entry, listing: listing,
                                                                engine: engine, password: password)
        }
        draggedFiles[path] = task
        do { return try await task.value } catch {
            draggedFiles[path] = nil
            throw error
        }
    }

    private func withExtracted(_ path: String, then action: @escaping (URL) -> Void) {
        guard let listing, let engine else { return }
        let entry = entry(for: path) ?? ArchiveEntry(id: -1, path: path, isDirectory: true, size: 0, packedSize: 0,
                                                     modified: nil, isEncrypted: false)
        busyMessage = String(localized: "Preparando “\(entry.name)”…")
        let password = password
        Task {
            defer { busyMessage = nil }
            do {
                let url = try await ExtractionService.extractForPreview(archive, entry: entry, listing: listing,
                                                                        engine: engine, password: password)
                action(url)
            } catch let error as ArchiveError {
                state = .failed(error)
            } catch {}
        }
    }

    // MARK: - Tree

    static func buildTree(_ entries: [ArchiveEntry]) -> [ArchiveNode] {
        final class Builder {
            let name: String
            let path: String
            var isDirectory: Bool
            var size: UInt64 = 0
            var packed: UInt64 = 0
            var modified: Date?
            var encrypted = false
            var children: [String: Builder] = [:]

            init(name: String, path: String, isDirectory: Bool) {
                self.name = name
                self.path = path
                self.isDirectory = isDirectory
            }

            func child(_ name: String, path: String, isDirectory: Bool) -> Builder {
                if let existing = children[name] {
                    if isDirectory { existing.isDirectory = true }
                    return existing
                }
                let node = Builder(name: name, path: path, isDirectory: isDirectory)
                children[name] = node
                return node
            }

            func node() -> ArchiveNode {
                guard isDirectory else {
                    return ArchiveNode(id: path, name: name, isDirectory: false, size: size, packedSize: packed,
                                       modified: modified, isEncrypted: encrypted, children: nil)
                }
                let kids = children.values.map { $0.node() }
                return ArchiveNode(id: path, name: name, isDirectory: true,
                                   size: kids.reduce(0) { $0 + $1.size }, packedSize: kids.reduce(0) { $0 + $1.packedSize },
                                   modified: modified, isEncrypted: encrypted, children: kids)
            }
        }

        let root = Builder(name: "", path: "", isDirectory: true)
        for entry in entries where !entry.path.isEmpty {
            let components = entry.path.split(separator: "/").map(String.init)
            var current = root
            var path = ""
            for (index, component) in components.enumerated() {
                path = path.isEmpty ? component : path + "/" + component
                let isLast = index == components.count - 1
                current = current.child(component, path: path, isDirectory: isLast ? entry.isDirectory : true)
            }
            current.size = entry.size
            current.packed = entry.packedSize
            current.modified = entry.modified
            current.encrypted = entry.isEncrypted
        }
        return root.children.values.map { $0.node() }
    }

    static func sorted(_ nodes: [ArchiveNode], by key: SortKey, ascending: Bool) -> [ArchiveNode] {
        nodes.map { node in
            var copy = node
            copy.children = node.children.map { sorted($0, by: key, ascending: ascending) }
            return copy
        }
        .sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            let ordered: Bool = switch key {
            case .name: a.name.localizedStandardCompare(b.name) == .orderedAscending
            case .size: a.size < b.size
            case .date: (a.modified ?? .distantPast) < (b.modified ?? .distantPast)
            }
            return ascending ? ordered : !ordered
        }
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// An archive entry dragged out of the preview: nothing is extracted until it is dropped (e.g. in Finder),
/// and then only that entry, straight to where it was dropped.
struct ArchiveDragItem: Transferable, Identifiable {
    let id: String          // archive path
    let isDirectory: Bool
    let browser: BrowserModel

    var name: String { (id as NSString).lastPathComponent }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .item) { item in
            SentTransferredFile(try await item.browser.extractForDrag(item.id))
        }
        .exportingCondition(\.isDirectory)
        .suggestedFileName(\.name)
        FileRepresentation(exportedContentType: .data) { item in
            SentTransferredFile(try await item.browser.extractForDrag(item.id))
        }
        .exportingCondition { !$0.isDirectory }
        .suggestedFileName(\.name)
    }
}
