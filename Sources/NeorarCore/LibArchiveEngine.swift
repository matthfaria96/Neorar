import CLibArchive
import Foundation

/// tar and compressed tar (gz, bz2, xz, zstd, lz4, Z), cpio and pax through the system libarchive,
/// in a single streaming pass and without spawning processes.
public struct LibArchiveEngine: ArchiveEngine {
    public init() {}

    private static let blockSize = 1 << 17

    /// True when the file is a container libarchive understands (not just a single compressed stream).
    static func recognizes(_ url: URL) -> Bool {
        guard let reader = try? Reader(url) else { return false }
        defer { reader.close() }
        var entry: OpaquePointer?
        return archive_read_next_header(reader.handle, &entry) == ARCHIVE_OK
    }

    public func list(_ archive: URL, password: String?, codePage: Int?) async throws -> ArchiveListing {
        try await Task.detached(priority: .userInitiated) {
            let reader = try Reader(archive)
            defer { reader.close() }
            var entries: [ArchiveEntry] = []
            var entry: OpaquePointer?
            while true {
                try Task.checkCancellation()
                let status = archive_read_next_header(reader.handle, &entry)
                if status == ARCHIVE_EOF { break }
                guard status >= ARCHIVE_WARN, let entry else { throw reader.error(status) }
                let type = archive_entry_filetype(entry) & mode_t(AE_IFMT)
                let mtime = archive_entry_mtime(entry)
                entries.append(ArchiveEntry(
                    id: entries.count,
                    path: Self.pathname(entry),
                    isDirectory: type == mode_t(AE_IFDIR),
                    size: archive_entry_size_is_set(entry) != 0 ? UInt64(max(0, archive_entry_size(entry))) : 0,
                    packedSize: 0,
                    modified: mtime > 0 ? Date(timeIntervalSince1970: TimeInterval(mtime)) : nil,
                    isEncrypted: archive_entry_is_encrypted(entry) != 0,
                    isLink: type == mode_t(AE_IFLNK)
                ))
                archive_read_data_skip(reader.handle)
            }
            return ArchiveListing(archiveURL: archive, format: ArchiveFormat.sniff(archive), entries: entries)
        }.value
    }

    public func extract(_ archive: URL, to directory: URL, paths: Set<String>?, password: String?, codePage: Int?,
                        totalBytes: UInt64, progress: @escaping ProgressHandler) async throws {
        try await Task.detached(priority: .userInitiated) {
            let reader = try Reader(archive)
            defer { reader.close() }
            guard let writer = archive_write_disk_new() else { throw ArchiveError.failed(String(localized: "Memória insuficiente.")) }
            defer { archive_write_free(writer) }
            archive_write_disk_set_options(writer, ARCHIVE_EXTRACT_TIME | ARCHIVE_EXTRACT_PERM | ARCHIVE_EXTRACT_XATTR
                | ARCHIVE_EXTRACT_FFLAGS | ARCHIVE_EXTRACT_SECURE_SYMLINKS | ARCHIVE_EXTRACT_SECURE_NODOTDOT)
            // Entry paths are rewritten below as staging + normalized path, so they are absolute on purpose;
            // SECURE_NODOTDOT still rejects any ".." that would climb out of the staging folder.
            archive_write_disk_set_standard_lookup(writer)

            let matcher = paths.map(SelectionMatcher.init)
            let fileSize = Double((try? archive.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            // SECURE_SYMLINKS checks every component, so the root must be free of links (/var → /private/var).
            // (Foundation's resolvingSymlinksInPath deliberately keeps /var, so use realpath.)
            let root = realpath(directory.path, nil).map { pointer in defer { free(pointer) }; return String(cString: pointer) } ?? directory.path
            var entry: OpaquePointer?
            var lastReport = ContinuousClock.now

            while true {
                try Task.checkCancellation()
                let status = archive_read_next_header(reader.handle, &entry)
                if status == ARCHIVE_EOF { break }
                guard status >= ARCHIVE_WARN, let entry else { throw reader.error(status) }

                let path = ArchiveEntry.normalize(Self.pathname(entry))
                guard !path.isEmpty, matcher?.matches(path) ?? true else {
                    archive_read_data_skip(reader.handle)
                    continue
                }
                archive_entry_set_pathname_utf8(entry, root + "/" + path)
                if let link = archive_entry_hardlink(entry) {
                    archive_entry_set_hardlink(entry, root + "/" + ArchiveEntry.normalize(String(cString: link)))
                }
                let result = archive_read_extract2(reader.handle, entry, writer)
                if result < ARCHIVE_WARN {
                    let message = archive_error_string(writer).map { String(cString: $0) } ?? ""
                    if message.localizedCaseInsensitiveContains("space") { throw ArchiveError.diskFull }
                    if message.localizedCaseInsensitiveContains("permission") { throw ArchiveError.cannotWrite(root) }
                    throw reader.error(result)
                }

                let now = ContinuousClock.now
                if now - lastReport > .milliseconds(80), fileSize > 0 {
                    lastReport = now
                    let read = Double(archive_filter_bytes(reader.handle, -1))
                    let fraction = min(1, read / fileSize)
                    progress(ExtractProgress(fraction: fraction, bytesDone: UInt64(Double(totalBytes) * fraction),
                                             bytesTotal: totalBytes, currentItem: path))
                }
            }
            progress(ExtractProgress(fraction: 1, bytesDone: totalBytes, bytesTotal: totalBytes))
        }.value
    }

    private static func pathname(_ entry: OpaquePointer) -> String {
        if let utf8 = archive_entry_pathname_utf8(entry) { return String(cString: utf8) }
        if let raw = archive_entry_pathname(entry) { return String(cString: raw) }
        return ""
    }

    private final class Reader {
        let handle: OpaquePointer
        private let url: URL

        init(_ url: URL) throws {
            guard let handle = archive_read_new() else { throw ArchiveError.failed(String(localized: "Memória insuficiente.")) }
            self.handle = handle
            self.url = url
            archive_read_support_filter_all(handle)
            archive_read_support_format_all(handle)
            if archive_read_open_filename(handle, url.path, LibArchiveEngine.blockSize) != ARCHIVE_OK {
                let error = self.error(ARCHIVE_FATAL)
                archive_read_free(handle)
                throw error
            }
        }

        func close() { archive_read_free(handle) }

        func error(_ status: Int32) -> ArchiveError {
            let message = archive_error_string(handle).map { String(cString: $0) } ?? ""
            let lower = message.lowercased()
            if archive_errno(handle) == EACCES { return .cannotRead(url.path) }
            if lower.contains("unrecognized archive format") { return .unsupportedFormat }
            if lower.contains("truncated") || lower.contains("premature end") { return .corrupted(String(localized: "O arquivo está truncado.")) }
            if lower.contains("passphrase") || lower.contains("encrypted") { return .passwordRequired }
            return message.isEmpty ? .corrupted(nil) : .corrupted(message)
        }
    }
}
