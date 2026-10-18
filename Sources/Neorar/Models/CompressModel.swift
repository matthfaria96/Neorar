import AppKit
import NeorarCore
import Observation

@Observable
final class CompressModel {
    enum State {
        case idle
        case running(Double)
        case finished([URL])
        case failed(ArchiveError)
    }

    struct VolumePreset: Identifiable, Hashable {
        let id: String
        let title: String
        let bytes: UInt64?
    }

    static let volumePresets: [VolumePreset] = [
        VolumePreset(id: "none", title: String(localized: "Arquivo único"), bytes: nil),
        VolumePreset(id: "10m", title: String(localized: "10 MB"), bytes: 10 * 1_048_576),
        VolumePreset(id: "100m", title: String(localized: "100 MB"), bytes: 100 * 1_048_576),
        VolumePreset(id: "700m", title: String(localized: "700 MB (CD)"), bytes: 700 * 1_048_576),
        VolumePreset(id: "2g", title: String(localized: "2 GB"), bytes: 2 * 1_073_741_824),
        VolumePreset(id: "fat32", title: String(localized: "4 GB (FAT32)"), bytes: 4_294_967_295),
        VolumePreset(id: "dvd", title: String(localized: "4,7 GB (DVD)"), bytes: 4_700_000_000),
    ]

    var items: [URL] = [] {
        didSet {
            refreshName()
            refreshSize()
        }
    }
    private(set) var totalSize: UInt64 = 0
    var options = Preferences.compressionDefaults()
    var password = ""
    var usePassword = false
    var volumePreset = "none"
    var comment = ""
    var archiveName = ""
    var destination: URL?
    var state: State = .idle

    @ObservationIgnored private var nameEdited = false
    @ObservationIgnored private var task: Task<Void, Never>?

    var isRunning: Bool { if case .running = state { true } else { false } }

    var replaceExisting = false

    /// The file the user asked for, before any renaming.
    var requestedURL: URL? {
        guard let directory = destination ?? items.first?.deletingLastPathComponent() else { return nil }
        let name = FileNaming.sanitize(archiveName.isEmpty ? CompressionService.defaultName(for: items) : archiveName)
        return directory.appendingPathComponent("\(name).\(options.format.fileExtension)")
    }

    var existingFile: URL? {
        guard let requested = requestedURL, FileManager.default.fileExists(atPath: requested.path) else { return nil }
        return requested
    }

    var outputURL: URL? {
        guard let requested = requestedURL else { return nil }
        if replaceExisting || existingFile == nil { return requested }
        return FileNaming.uniqueURL(in: requested.deletingLastPathComponent(), name: requested.lastPathComponent, isDirectory: false)
    }

    func add(_ urls: [URL]) {
        let new = urls.filter { url in !items.contains(where: { $0.standardizedFileURL == url.standardizedFileURL }) }
        items.append(contentsOf: new)
        if case .finished = state { state = .idle }
        if case .failed = state { state = .idle }
    }

    func remove(_ url: URL) { items.removeAll { $0 == url } }

    func clear() {
        items.removeAll()
        nameEdited = false
        archiveName = ""
        state = .idle
    }

    func nameChanged(_ value: String) {
        archiveName = value
        nameEdited = !value.isEmpty
    }

    private func refreshName() {
        guard !nameEdited else { return }
        archiveName = items.isEmpty ? "" : CompressionService.defaultName(for: items)
    }

    private func refreshSize() {
        let items = items
        Task {
            let size = await Task.detached(priority: .utility) { items.reduce(0) { $0 + Self.size(of: $1) } }.value
            if items == self.items { totalSize = size }
        }
    }

    func start() {
        guard !items.isEmpty, let output = outputURL else { return }
        if replaceExisting, let existing = existingFile {
            try? FileManager.default.trashItem(at: existing, resultingItemURL: nil)
        }
        var options = options
        options.password = usePassword && options.format.supportsPassword && !password.isEmpty ? password : nil
        let trimmedComment = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        options.comment = options.format.supportsComment && !trimmedComment.isEmpty ? trimmedComment : nil
        options.volumeSize = options.format.supportsVolumes
            ? Self.volumePresets.first { $0.id == volumePreset }?.bytes : nil
        let items = items
        state = .running(0)
        task = Task {
            do {
                let written = try await CompressionService.compress(items, to: output, options: options) { progress in
                    Task { @MainActor in
                        guard case .running(let current) = self.state else { return }
                        self.state = .running(max(current, progress.fraction))
                    }
                }
                state = .idle
                AppModel.shared.compressFinished(written)
                if Preferences.revealAfter { NSWorkspace.shared.activateFileViewerSelecting(written) }
            } catch {
                let failure = (error as? ArchiveError) ?? (error is CancellationError ? .cancelled : .failed(error.localizedDescription))
                state = failure == .cancelled ? .idle : .failed(failure)
            }
        }
    }

    func cancel() { task?.cancel() }

    func chooseDestination() {
        let panel = NSOpenPanel()
        panel.message = String(localized: "Onde salvar o arquivo compactado?")
        panel.prompt = String(localized: "Escolher")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = destination ?? items.first?.deletingLastPathComponent()
        if panel.runModal() == .OK { destination = panel.url }
    }

    nonisolated static func size(of url: URL) -> UInt64 {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .totalFileAllocatedSizeKey, .fileSizeKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        guard values.isDirectory == true else { return UInt64(values.fileSize ?? 0) }
        var total: UInt64 = 0
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey])
        while let child = enumerator?.nextObject() as? URL {
            total += UInt64((try? child.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        return total
    }
}
