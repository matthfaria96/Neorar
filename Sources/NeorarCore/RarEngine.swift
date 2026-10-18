import CUnrar
import Foundation

/// RAR 1.5–7 extraction in-process through RARLAB's UnRAR library.
public struct RarEngine: ArchiveEngine {
    public init() {}

    /// UnRAR keeps some process-wide state (its error handler), so archives are processed one at a time.
    /// Each archive still decompresses on several threads internally (RAR_SMP).
    private static let gate = AsyncGate()

    public func list(_ archive: URL, password: String?, codePage: Int?) async throws -> ArchiveListing {
        try await Self.gate.run {
            try await Task.detached(priority: .userInitiated) {
                try Self.listSync(archive, password: password)
            }.value
        }
    }

    public func extract(_ archive: URL, to directory: URL, paths: Set<String>?, password: String?, codePage: Int?,
                        totalBytes: UInt64, progress: @escaping ProgressHandler) async throws {
        try await Self.gate.run {
            let state = ExtractState(total: totalBytes, progress: progress)
            try await withTaskCancellationHandler {
                try await Task.detached(priority: .userInitiated) {
                    try Self.extractSync(archive, to: directory, paths: paths, password: password, state: state, testOnly: false)
                }.value
            } onCancel: {
                state.cancel()
            }
        }
    }

    public func test(_ archive: URL, password: String?, codePage: Int?, totalBytes: UInt64,
                     progress: @escaping ProgressHandler) async throws {
        try await Self.gate.run {
            let state = ExtractState(total: totalBytes, progress: progress)
            try await withTaskCancellationHandler {
                try await Task.detached(priority: .userInitiated) {
                    try Self.extractSync(archive, to: nil, paths: nil, password: password, state: state, testOnly: true)
                }.value
            } onCancel: {
                state.cancel()
            }
        }
    }

    // MARK: - Synchronous core

    static func listSync(_ archive: URL, password: String?) throws -> ArchiveListing {
        var openResult: Int32 = 0
        var flags: UInt32 = 0
        guard let handle = nr_open(archive.path, 0, password, nil, nil, &openResult, &flags) else {
            throw ArchiveError.failed(String(localized: "Memória insuficiente."))
        }
        defer { nr_close(handle) }
        if openResult != NR_OK {
            throw mapError(openResult, handle: handle, archive: archive, hadPassword: password != nil)
        }

        var entries: [ArchiveEntry] = []
        let entry = UnsafeMutablePointer<nr_entry>.allocate(capacity: 1)
        defer { entry.deallocate() }
        var index = 0
        while true {
            let code = nr_read_header(handle, entry)
            if code == NR_END_ARCHIVE { break }
            if code != NR_OK { throw mapError(code, handle: handle, archive: archive, hadPassword: password != nil) }
            let item = makeEntry(entry.pointee, id: index)
            // Files split across volumes appear once per volume; keep the first header only.
            if entry.pointee.flags & UInt32(NR_ENTRY_SPLIT_BEFORE) == 0 {
                entries.append(item)
                index += 1
            }
            let skip = nr_process(handle, Int32(NR_OP_SKIP), nil)
            if skip != NR_OK { throw mapError(skip, handle: handle, archive: archive, hadPassword: password != nil) }
        }
        return ArchiveListing(
            archiveURL: archive, format: .rar, entries: entries,
            hasEncryptedHeaders: flags & UInt32(NR_ARC_ENCHEADERS) != 0,
            isSolid: flags & UInt32(NR_ARC_SOLID) != 0,
            isMultiVolume: flags & UInt32(NR_ARC_VOLUME) != 0,
            comment: String(cString: nr_comment(handle))
        )
    }

    static func extractSync(_ archive: URL, to directory: URL?, paths: Set<String>?, password: String?,
                            state: ExtractState, testOnly: Bool) throws {
        var openResult: Int32 = 0
        var flags: UInt32 = 0
        let context = Unmanaged.passUnretained(state).toOpaque()
        guard let handle = nr_open(archive.path, 1, password, rarProgressCallback, context, &openResult, &flags) else {
            throw ArchiveError.failed(String(localized: "Memória insuficiente."))
        }
        defer { nr_close(handle) }
        if openResult != NR_OK {
            throw mapError(openResult, handle: handle, archive: archive, hadPassword: password != nil)
        }

        let wanted = paths.map(SelectionMatcher.init)
        let entry = UnsafeMutablePointer<nr_entry>.allocate(capacity: 1)
        defer { entry.deallocate() }
        let destination = directory?.path
        while true {
            if state.isCancelled { throw ArchiveError.cancelled }
            let code = nr_read_header(handle, entry)
            if code == NR_END_ARCHIVE { break }
            if code != NR_OK { throw mapError(code, handle: handle, archive: archive, hadPassword: password != nil) }

            let name = ArchiveEntry.normalize(entryName(entry.pointee))
            let include = wanted?.matches(name) ?? true
            state.currentItem = name
            let operation = include ? (testOnly ? NR_OP_TEST : NR_OP_EXTRACT) : NR_OP_SKIP
            let result = nr_process(handle, Int32(operation), include && !testOnly ? destination : nil)
            if state.isCancelled { throw ArchiveError.cancelled }
            if result != NR_OK { throw mapError(result, handle: handle, archive: archive, hadPassword: password != nil) }
        }
        state.finish()
    }

    private static func entryName(_ raw: nr_entry) -> String {
        raw.name.map { String(cString: $0) } ?? ""
    }

    private static func makeEntry(_ raw: nr_entry, id: Int) -> ArchiveEntry {
        ArchiveEntry(
            id: id, path: entryName(raw),
            isDirectory: raw.flags & UInt32(NR_ENTRY_DIRECTORY) != 0,
            size: raw.unpacked_size, packedSize: raw.packed_size,
            modified: raw.mtime > 0 ? Date(timeIntervalSince1970: raw.mtime) : nil,
            isEncrypted: raw.flags & UInt32(NR_ENTRY_ENCRYPTED) != 0,
            isLink: raw.redir_type != 0
        )
    }

    private static func mapError(_ code: Int32, handle: OpaquePointer, archive: URL, hadPassword: Bool) -> ArchiveError {
        if nr_password_was_requested(handle) != 0 { return .passwordRequired }
        let missing = String(cString: nr_missing_volume(handle))
        if !missing.isEmpty { return .missingVolume(missing) }
        switch Int(code) {
        case Int(NR_MISSING_PASSWORD): return .passwordRequired
        case Int(NR_BAD_PASSWORD): return .wrongPassword
        // RAR 2/3/4 have no password check value: a bad password surfaces as a CRC failure.
        case Int(NR_BAD_DATA): return hadPassword ? .wrongPassword : .corrupted(nil)
        case Int(NR_BAD_ARCHIVE), Int(NR_UNKNOWN_FORMAT): return .unsupportedFormat
        case Int(NR_EOPEN): return FileManager.default.isReadableFile(atPath: archive.path) ? .missingVolume(nil) : .cannotRead(archive.path)
        case Int(NR_ECREATE), Int(NR_EWRITE): return .cannotWrite(archive.deletingLastPathComponent().path)
        case Int(NR_EREAD): return .corrupted(String(localized: "Falha de leitura."))
        case Int(NR_NO_MEMORY): return .failed(String(localized: "Memória insuficiente."))
        case Int(NR_UNKNOWN): return .cancelled
        default: return .failed(String(localized: "Erro do UnRAR (\(code))."))
        }
    }
}

/// Mutable state shared with the C progress callback.
final class ExtractState: @unchecked Sendable {
    private let lock = NSLock()
    private let total: UInt64
    private let progress: ProgressHandler
    private var done: UInt64 = 0
    private var cancelled = false
    private var lastReport = ContinuousClock.now
    var currentItem: String?

    init(total: UInt64, progress: @escaping ProgressHandler) {
        self.total = total
        self.progress = progress
    }

    var isCancelled: Bool { lock.withLock { cancelled } }
    func cancel() { lock.withLock { cancelled = true } }

    /// Returns false to abort.
    func add(_ bytes: Int64) -> Bool {
        let (shouldReport, snapshot, isCancelled): (Bool, UInt64, Bool) = lock.withLock {
            done += UInt64(max(0, bytes))
            let now = ContinuousClock.now
            let report = now - lastReport > .milliseconds(80)
            if report { lastReport = now }
            return (report, done, cancelled)
        }
        if shouldReport {
            let fraction = total > 0 ? min(1, Double(snapshot) / Double(total)) : 0
            progress(ExtractProgress(fraction: fraction, bytesDone: snapshot, bytesTotal: total, currentItem: currentItem))
        }
        return !isCancelled
    }

    func finish() {
        progress(ExtractProgress(fraction: 1, bytesDone: total, bytesTotal: total, currentItem: nil))
    }
}

private func rarProgressCallback(_ context: UnsafeMutableRawPointer?, _ bytes: Int64) -> Int32 {
    guard let context else { return 0 }
    let state = Unmanaged<ExtractState>.fromOpaque(context).takeUnretainedValue()
    return state.add(bytes) ? 0 : 1
}

/// Matches archive paths against a selection where picking a folder includes its contents.
struct SelectionMatcher: Sendable {
    private let exact: Set<String>
    private let prefixes: [String]

    init(_ paths: Set<String>) {
        let normalized = Set(paths.map(ArchiveEntry.normalize))
        exact = normalized
        prefixes = normalized.map { $0 + "/" }
    }

    func matches(_ path: String) -> Bool {
        exact.contains(path) || prefixes.contains(where: path.hasPrefix)
    }
}

/// Serializes async work without blocking threads.
actor AsyncGate {
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func run<T: Sendable>(_ work: @Sendable () async throws -> T) async throws -> T {
        if busy {
            await withCheckedContinuation { waiters.append($0) }
        }
        busy = true
        defer {
            if waiters.isEmpty { busy = false } else { waiters.removeFirst().resume() }
        }
        return try await work()
    }
}
