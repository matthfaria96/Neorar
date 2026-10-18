import Foundation

public protocol ArchiveEngine: Sendable {
    /// Reads the table of contents without decompressing data.
    func list(_ archive: URL, password: String?, codePage: Int?) async throws -> ArchiveListing

    /// Extracts `paths` (or everything when nil) with their full archive paths under `directory`.
    func extract(_ archive: URL, to directory: URL, paths: Set<String>?, password: String?, codePage: Int?,
                 totalBytes: UInt64, progress: @escaping ProgressHandler) async throws

    /// Decompresses everything and verifies checksums without keeping the output.
    func test(_ archive: URL, password: String?, codePage: Int?, totalBytes: UInt64,
              progress: @escaping ProgressHandler) async throws
}

extension ArchiveEngine {
    /// Fallback for engines without a native test mode: extract to a scratch folder and discard it.
    public func test(_ archive: URL, password: String?, codePage: Int?, totalBytes: UInt64,
                     progress: @escaping ProgressHandler) async throws {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("neorar-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        try await extract(archive, to: scratch, paths: nil, password: password, codePage: codePage,
                          totalBytes: totalBytes, progress: progress)
    }
}

public enum EngineKind: String, Sendable {
    case unrar, libarchive, sevenZip, unar
}

public enum Engines {
    /// Picks the engine for an archive: RAR and tarballs stay in-process, everything else goes to 7-Zip,
    /// and legacy formats fall back to The Unarchiver's command-line tools when installed.
    public static func engine(for archive: URL) -> (kind: EngineKind, engine: any ArchiveEngine) {
        let format = ArchiveFormat.sniff(archive)
        switch format {
        case .rar:
            return (.unrar, RarEngine())
        case .tar, .cpio:
            return (.libarchive, LibArchiveEngine())
        case .gzip, .bzip2, .xz, .zstd:
            // Compressed tarballs; a lone compressed file (no tar inside) goes to 7-Zip.
            if LibArchiveEngine.recognizes(archive) { return (.libarchive, LibArchiveEngine()) }
        default:
            break
        }
        if format == .other, let unar = UnarEngine.ifAvailable, !SevenZipEngine.likelySupports(archive) {
            return (.unar, unar)
        }
        return (.sevenZip, SevenZipEngine())
    }

    /// Lists with the preferred engine, retrying with unar when 7-Zip cannot open the file.
    public static func list(_ archive: URL, password: String?, codePage: Int?) async throws
        -> (listing: ArchiveListing, engine: any ArchiveEngine) {
        let choice = engine(for: archive)
        do {
            return (try await choice.engine.list(archive, password: password, codePage: codePage), choice.engine)
        } catch ArchiveError.unsupportedFormat where choice.kind == .sevenZip {
            guard let unar = UnarEngine.ifAvailable else { throw ArchiveError.unsupportedFormat }
            return (try await unar.list(archive, password: password, codePage: codePage), unar)
        }
    }
}
