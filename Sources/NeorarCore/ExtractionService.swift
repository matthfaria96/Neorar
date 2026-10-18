import Foundation

public enum FolderPolicy: String, CaseIterable, Identifiable, Sendable {
    case smart, always, never
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .smart: String(localized: "Só quando houver vários itens")
        case .always: String(localized: "Sempre")
        case .never: String(localized: "Nunca")
        }
    }
}

public enum ConflictPolicy: String, CaseIterable, Identifiable, Sendable {
    case rename, overwrite
    public var id: String { rawValue }
    public var title: String { self == .rename ? String(localized: "Manter os dois (renomear)") : String(localized: "Substituir (o antigo vai para o Lixo)") }
}

public enum DateChoice: String, CaseIterable, Identifiable, Sendable {
    case original, now
    public var id: String { rawValue }
}

public struct ExtractionOptions: Sendable {
    public var destination: URL
    public var folderPolicy: FolderPolicy = .smart
    public var conflictPolicy: ConflictPolicy = .rename
    public var folderDate: DateChoice = .now
    public var fileDates: DateChoice = .original
    public var removeJunk = true
    public var trashArchiveAfter = false
    /// Forced ZIP code page; nil means auto-detect.
    public var codePage: Int?
    /// Archive paths to extract; nil extracts everything.
    public var selection: Set<String>?

    public init(destination: URL) { self.destination = destination }
}

public struct ExtractionResult: Sendable {
    public let items: [URL]
    public let createdFolder: URL?
    public var revealTarget: URL? { createdFolder ?? items.first }
}

public enum ExtractionService {
    public static func extract(
        _ archive: URL,
        options: ExtractionOptions,
        password: String?,
        prepared: (listing: ArchiveListing, engine: any ArchiveEngine)? = nil,
        progress: @escaping ProgressHandler
    ) async throws -> ExtractionResult {
        let fileManager = FileManager.default
        let volumes = VolumeSet.resolve(archive)
        let source = volumes.first
        guard fileManager.isReadableFile(atPath: source.path) else {
            throw fileManager.fileExists(atPath: source.path) ? ArchiveError.cannotRead(source.path) : .missingVolume(source.path)
        }

        let codePage = options.codePage ?? (ArchiveFormat.sniff(source) == .zip ? ZipEncodingDetector.detect(source) : nil)
        let (listing, engine): (ArchiveListing, any ArchiveEngine)
        if let prepared {
            (listing, engine) = prepared
        } else {
            (listing, engine) = try await Engines.list(source, password: password, codePage: codePage)
        }
        if listing.isEncrypted && (password ?? "").isEmpty { throw ArchiveError.passwordRequired }

        // Expand the selection to concrete entries so every engine receives exact paths.
        var paths: Set<String>?
        var totalBytes = listing.totalSize
        if let selection = options.selection, !selection.isEmpty {
            let matcher = SelectionMatcher(selection)
            let chosen = listing.entries.filter { matcher.matches($0.path) }
            paths = Set(chosen.map(\.path))
            totalBytes = chosen.reduce(0) { $0 + $1.size }
        }

        let destination = options.destination
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        guard fileManager.isWritableFile(atPath: destination.path) else { throw ArchiveError.cannotWrite(destination.path) }
        if let free = try? destination.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage, free > 0, UInt64(free) < totalBytes {
            throw ArchiveError.diskFull
        }

        // Extract next to the destination so the final placement is a rename on the same volume.
        let staging = destination.appendingPathComponent(".neorar-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fileManager.removeItem(at: staging) }

        try await engine.extract(source, to: staging, paths: paths, password: password, codePage: listing.codePage ?? codePage,
                                 totalBytes: totalBytes, progress: progress)
        try Task.checkCancellation()

        if options.removeJunk { removeJunk(in: staging) }
        if options.fileDates == .now { touchAll(in: staging) }

        var roots: [URL]
        if let selection = options.selection, !selection.isEmpty {
            roots = topLevelSelections(selection).map { staging.appendingPathComponent($0) }
                .filter { fileManager.fileExists(atPath: $0.path) }
        } else {
            roots = (try? fileManager.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil)) ?? []
        }
        roots.sort { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        guard !roots.isEmpty else { return ExtractionResult(items: [], createdFolder: nil) }

        let wantsFolder = options.folderPolicy == .always || (options.folderPolicy == .smart && roots.count > 1)
        var placed: [URL] = []
        var createdFolder: URL?

        if wantsFolder {
            let folderName = FileNaming.sanitize(FileNaming.baseName(of: source))
            let folder = try target(for: folderName, in: destination, isDirectory: true, policy: options.conflictPolicy)
            if options.selection == nil {
                try fileManager.moveItem(at: staging, to: folder)
                placed = roots.map { folder.appendingPathComponent($0.lastPathComponent) }
            } else {
                try fileManager.createDirectory(at: folder, withIntermediateDirectories: false)
                for root in roots {
                    let item = folder.appendingPathComponent(root.lastPathComponent)
                    try fileManager.moveItem(at: root, to: item)
                    placed.append(item)
                }
            }
            let date = options.folderDate == .original
                ? ((try? source.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date())
                : Date()
            try? fileManager.setAttributes([.modificationDate: date], ofItemAtPath: folder.path)
            createdFolder = folder
        } else {
            for root in roots {
                var isDirectory: ObjCBool = false
                fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory)
                let item = try target(for: root.lastPathComponent, in: destination, isDirectory: isDirectory.boolValue,
                                      policy: options.conflictPolicy)
                try fileManager.moveItem(at: root, to: item)
                placed.append(item)
            }
        }

        if options.trashArchiveAfter {
            for volume in volumes.members { try? fileManager.trashItem(at: volume, resultingItemURL: nil) }
        }
        return ExtractionResult(items: placed, createdFolder: createdFolder)
    }

    /// Reads the table of contents with the right engine and ZIP code page, ready to hand to `extract`.
    public static func prepare(_ archive: URL, password: String?, codePage: Int?) async throws
        -> (listing: ArchiveListing, engine: any ArchiveEngine) {
        let source = VolumeSet.resolve(archive).first
        let page = codePage ?? (ArchiveFormat.sniff(source) == .zip ? ZipEncodingDetector.detect(source) : nil)
        return try await Engines.list(source, password: password, codePage: page)
    }

    /// Names that extraction will create directly inside `options.destination`.
    public static func plannedNames(for archive: URL, listing: ArchiveListing, options: ExtractionOptions) -> [String] {
        var roots: [String]
        if let selection = options.selection, !selection.isEmpty {
            roots = topLevelSelections(selection).map { ($0 as NSString).lastPathComponent }
        } else {
            var seen = Set<String>()
            roots = listing.entries.compactMap { entry in
                guard let first = entry.path.split(separator: "/").first.map(String.init), seen.insert(first).inserted else { return nil }
                return first
            }
            if options.removeJunk { roots.removeAll { $0 == "__MACOSX" || $0 == ".DS_Store" } }
        }
        let wantsFolder = options.folderPolicy == .always || (options.folderPolicy == .smart && roots.count > 1)
        if wantsFolder { return [FileNaming.sanitize(FileNaming.baseName(of: VolumeSet.resolve(archive).first))] }
        return roots
    }

    /// Planned names that already exist in the destination.
    public static func conflicts(for archive: URL, listing: ArchiveListing, options: ExtractionOptions) -> [String] {
        plannedNames(for: archive, listing: listing, options: options).filter {
            FileManager.default.fileExists(atPath: options.destination.appendingPathComponent($0).path)
        }
    }

    /// Verifies every entry of an archive. Returns the listing so callers can summarize what was checked.
    @discardableResult
    public static func test(
        _ archive: URL, password: String?,
        prepared: (listing: ArchiveListing, engine: any ArchiveEngine)? = nil,
        progress: @escaping ProgressHandler
    ) async throws -> ArchiveListing {
        let source = VolumeSet.resolve(archive).first
        let codePage = ArchiveFormat.sniff(source) == .zip ? ZipEncodingDetector.detect(source) : nil
        let (listing, engine): (ArchiveListing, any ArchiveEngine)
        if let prepared {
            (listing, engine) = prepared
        } else {
            (listing, engine) = try await Engines.list(source, password: password, codePage: codePage)
        }
        if listing.isEncrypted && (password ?? "").isEmpty { throw ArchiveError.passwordRequired }
        try await engine.test(source, password: password, codePage: listing.codePage ?? codePage,
                              totalBytes: listing.totalSize, progress: progress)
        return listing
    }

    /// Extracts a single entry into a private cache folder (Quick Look, drag-out, open).
    public static func extractForPreview(
        _ archive: URL, entry: ArchiveEntry, listing: ArchiveListing, engine: any ArchiveEngine, password: String?
    ) async throws -> URL {
        let root = previewCache.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let matcher = SelectionMatcher([entry.path])
        let paths = Set(listing.entries.filter { matcher.matches($0.path) }.map(\.path))
        try await engine.extract(VolumeSet.resolve(archive).first, to: root, paths: paths, password: password,
                                 codePage: listing.codePage, totalBytes: entry.size, progress: { _ in })
        let url = root.appendingPathComponent(entry.path, isDirectory: entry.isDirectory)
        guard FileManager.default.fileExists(atPath: url.path) else { throw ArchiveError.failed(String(localized: "Não foi possível extrair “\(entry.name)”.")) }
        return url
    }

    public static var previewCache: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Neorar/Preview", isDirectory: true)
    }

    public static func clearPreviewCache() {
        try? FileManager.default.removeItem(at: previewCache)
    }

    // MARK: - Helpers

    private static func target(for name: String, in directory: URL, isDirectory: Bool, policy: ConflictPolicy) throws -> URL {
        let direct = directory.appendingPathComponent(name, isDirectory: isDirectory)
        guard FileManager.default.fileExists(atPath: direct.path) else { return direct }
        switch policy {
        case .rename:
            return FileNaming.uniqueURL(in: directory, name: name, isDirectory: isDirectory)
        case .overwrite:
            try FileManager.default.trashItem(at: direct, resultingItemURL: nil)
            return direct
        }
    }

    /// Keeps only selections whose ancestors were not also selected.
    static func topLevelSelections(_ selection: Set<String>) -> [String] {
        let normalized = Set(selection.map(ArchiveEntry.normalize)).filter { !$0.isEmpty }
        return normalized.filter { path in
            var parent = (path as NSString).deletingLastPathComponent
            while !parent.isEmpty {
                if normalized.contains(parent) { return false }
                parent = (parent as NSString).deletingLastPathComponent
            }
            return true
        }.sorted()
    }

    private static func removeJunk(in directory: URL) {
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: directory.appendingPathComponent("__MACOSX"))
        guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: nil) else { return }
        for case let url as URL in enumerator where url.lastPathComponent == ".DS_Store" {
            try? fileManager.removeItem(at: url)
        }
    }

    private static func touchAll(in directory: URL) {
        let now = Date()
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else { return }
        for case let url as URL in enumerator {
            try? FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: url.path)
        }
    }
}
