import Foundation

public enum CompressionFormat: String, CaseIterable, Identifiable, Sendable {
    // Display order: open formats first, proprietary RAR last.
    case sevenZip, zip, tarGz, tarXz, tarBz2, rar

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .rar: "RAR"
        case .sevenZip: "7Z"
        case .zip: "ZIP"
        case .tarGz: "TAR.GZ"
        case .tarXz: "TAR.XZ"
        case .tarBz2: "TAR.BZ2"
        }
    }
    public var fileExtension: String {
        switch self {
        case .rar: "rar"
        case .sevenZip: "7z"
        case .zip: "zip"
        case .tarGz: "tar.gz"
        case .tarXz: "tar.xz"
        case .tarBz2: "tar.bz2"
        }
    }
    public var supportsPassword: Bool { self == .rar || self == .sevenZip || self == .zip }
    public var supportsEncryptedNames: Bool { self == .rar || self == .sevenZip }
    public var supportsVolumes: Bool { self == .rar || self == .sevenZip || self == .zip }
    public var supportsSolid: Bool { self == .rar || self == .sevenZip }
    public var supportsRecovery: Bool { self == .rar }
    /// 7Z and TAR have no archive comment.
    public var supportsComment: Bool { self == .rar || self == .zip }
}

public enum CompressionLevel: Int, CaseIterable, Identifiable, Sendable {
    case store, fastest, fast, normal, good, best
    public var id: Int { rawValue }
    public var title: String {
        switch self {
        case .store: String(localized: "Sem compressão")
        case .fastest: String(localized: "Mais rápida")
        case .fast: String(localized: "Rápida")
        case .normal: String(localized: "Normal")
        case .good: String(localized: "Boa")
        case .best: String(localized: "Máxima")
        }
    }
    var sevenZip: Int { [0, 1, 3, 5, 7, 9][rawValue] }
    var tar: Int { [1, 1, 3, 6, 7, 9][rawValue] }
}

public struct CompressionOptions: Sendable {
    public var format: CompressionFormat = .sevenZip
    public var level: CompressionLevel = .normal
    public var password: String?
    public var encryptNames = true
    public var volumeSize: UInt64?
    public var solid = true
    public var recoveryRecord = false
    public var excludeMacJunk = true
    public var trashSourcesAfter = false
    /// Archive comment (RAR and single-file ZIP).
    public var comment: String?

    public init() {}
}

public enum CompressionService {
    public static func defaultName(for items: [URL]) -> String {
        if items.count == 1, let item = items.first { return item.lastPathComponent }
        let parent = Set(items.map { $0.deletingLastPathComponent().standardizedFileURL })
        if parent.count == 1, let only = parent.first, only.path != "/" { return only.lastPathComponent }
        return String(localized: "Arquivo")
    }

    /// Compresses `items` into `output` and returns every file written (one per volume).
    public static func compress(
        _ items: [URL], to output: URL, options: CompressionOptions, progress: @escaping ProgressHandler
    ) async throws -> [URL] {
        guard !items.isEmpty else { throw ArchiveError.failed(String(localized: "Nenhum item para compactar.")) }
        let fileManager = FileManager.default
        let directory = output.deletingLastPathComponent()
        guard fileManager.isWritableFile(atPath: directory.path) else { throw ArchiveError.cannotWrite(directory.path) }
        let startedAt = Date()

        do {
            switch options.format {
            case .rar: try await compressRar(items, to: output, options: options, progress: progress)
            case .sevenZip, .zip: try await compressSevenZip(items, to: output, options: options, progress: progress)
            case .tarGz, .tarXz, .tarBz2: try await compressTar(items, to: output, options: options, progress: progress)
            }
        } catch {
            for file in writtenFiles(for: output, since: startedAt) { try? fileManager.removeItem(at: file) }
            throw (error as? CancellationError).map { _ in ArchiveError.cancelled } ?? error
        }

        let written = writtenFiles(for: output, since: startedAt)
        guard !written.isEmpty else { throw ArchiveError.failed(String(localized: "O arquivo compactado não foi criado.")) }
        if options.trashSourcesAfter {
            for item in items { try? fileManager.trashItem(at: item, resultingItemURL: nil) }
        }
        progress(ExtractProgress(fraction: 1))
        return written
    }

    // MARK: - RAR (RARLAB's rar)

    private static func compressRar(_ items: [URL], to output: URL, options: CompressionOptions,
                                    progress: @escaping ProgressHandler) async throws {
        guard let rar = ToolLocator.rar else { throw ArchiveError.toolMissing("rar") }
        var arguments = ["a", "-ma5", "-m\(options.level.rawValue)", "-ep1", "-idc", "-y", "-o+"]
        if options.solid { arguments.append("-s") }
        if options.recoveryRecord { arguments.append("-rr5%") }
        if let size = options.volumeSize { arguments.append("-v\(size)b") }
        if options.excludeMacJunk { arguments += ["-x*.DS_Store", "-x*/__MACOSX", "-x*/._*", "-x__MACOSX"] }
        var input: Data?
        if let password = options.password, !password.isEmpty {
            arguments.append(options.encryptNames ? "-hp" : "-p")
            input = Data("\(password)\n\(password)\n".utf8)
        }
        var commentFile: URL?
        if let comment = options.comment?.trimmingCharacters(in: .whitespacesAndNewlines), !comment.isEmpty {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("neorar-comment-\(UUID().uuidString).txt")
            try Data(comment.utf8).write(to: file)
            arguments.append("-scfc") // comment file charset: UTF-8
            arguments.append("-z\(file.path)")
            commentFile = file
        }
        defer { commentFile.map { try? FileManager.default.removeItem(at: $0) } }
        arguments += ["--", output.path] + items.map(\.path)

        let result = try await ProcessRunner.run(rar, arguments: arguments, stdin: input, onOutput: { chunk in
            if let percent = PercentParser.lastPercent(in: chunk) { progress(ExtractProgress(fraction: Double(percent) / 100)) }
        })
        try Task.checkCancellation()
        switch result.status {
        case 0, 1: return
        case 5, 9: throw ArchiveError.cannotWrite(output.deletingLastPathComponent().path)
        case 6: throw ArchiveError.cannotRead(items.first?.path ?? "")
        case 8: throw ArchiveError.failed(String(localized: "Memória insuficiente."))
        case 10: throw ArchiveError.failed(String(localized: "Nenhum arquivo para adicionar."))
        case 255: throw ArchiveError.cancelled
        default:
            let message = result.stdoutText.split(separator: "\n").last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
            throw ArchiveError.failed(String(localized: "O rar falhou (código \(result.status))") + (message.map { ": \($0)" } ?? "."))
        }
    }

    // MARK: - 7z / ZIP (bundled 7-Zip)

    private static func compressSevenZip(_ items: [URL], to output: URL, options: CompressionOptions,
                                         progress: @escaping ProgressHandler) async throws {
        guard let tool = ToolLocator.sevenZip else { throw ArchiveError.toolMissing("7zz") }
        let isZip = options.format == .zip
        var arguments = ["a", isZip ? "-tzip" : "-t7z", "-mx=\(options.level.sevenZip)", "-mmt=on",
                         "-bsp1", "-bso0", "-bse2", "-sccUTF-8", "-y"]
        if !isZip { arguments.append(options.solid ? "-ms=on" : "-ms=off") }
        if options.excludeMacJunk { arguments += ["-xr!.DS_Store", "-xr!__MACOSX", "-xr!._*"] }
        if let size = options.volumeSize { arguments.append("-v\(size)b") }
        var input: Data?
        if let password = options.password, !password.isEmpty {
            arguments.append("-p")
            if isZip { arguments.append("-mem=AES256") } else if options.encryptNames { arguments.append("-mhe=on") }
            input = Data("\(password)\n\(password)\n".utf8)
        }
        arguments += ["--", output.path] + items.map(\.path)

        let result = try await ProcessRunner.run(tool, arguments: arguments, stdin: input, onOutput: { chunk in
            if let percent = PercentParser.lastPercent(in: chunk) { progress(ExtractProgress(fraction: Double(percent) / 100)) }
        })
        try Task.checkCancellation()
        if result.status > 1 {
            throw SevenZipEngine.classify(result, hadPassword: true, destination: output.deletingLastPathComponent())
                ?? ArchiveError.failed(String(localized: "O 7-Zip terminou com o código \(result.status)."))
        }
        if isZip, options.volumeSize == nil,
           let comment = options.comment?.trimmingCharacters(in: .whitespacesAndNewlines), !comment.isEmpty {
            try ZipComment.write(comment, to: output)
        }
    }

    // MARK: - tar.* (system bsdtar)

    private static func compressTar(_ items: [URL], to output: URL, options: CompressionOptions,
                                    progress: @escaping ProgressHandler) async throws {
        let (flag, filter): (String, String) = switch options.format {
        case .tarXz: ("-J", "xz")
        case .tarBz2: ("-j", "bzip2")
        default: ("-z", "gzip")
        }
        var compressorOptions = "\(filter):compression-level=\(options.level.tar)"
        if options.format == .tarXz { compressorOptions += ",xz:threads=0" }
        var arguments = ["-c", "-v", flag, "--options", compressorOptions, "-f", output.path]
        if options.excludeMacJunk { arguments += ["--exclude", ".DS_Store", "--exclude", "__MACOSX", "--exclude", "._*"] }
        for item in items { arguments += ["-C", item.deletingLastPathComponent().path, item.lastPathComponent] }

        let total = Double(max(1, countItems(items)))
        let counter = ByteLineCounter()
        let result = try await ProcessRunner.run(
            ToolLocator.tar, arguments: arguments, environment: ["COPYFILE_DISABLE": "1"],
            onOutput: { chunk in
                let lines = counter.add(chunk)
                progress(ExtractProgress(fraction: min(0.99, Double(lines) / total)))
            }
        )
        try Task.checkCancellation()
        if result.status != 0 {
            let message = result.stderrText.split(separator: "\n").last(where: { !$0.hasPrefix("a ") }).map(String.init)
            throw ArchiveError.failed(message ?? String(localized: "O tar terminou com o código \(result.status)."))
        }
    }

    // MARK: - Helpers

    static func countItems(_ items: [URL]) -> Int {
        var count = 0
        for item in items {
            count += 1
            guard let enumerator = FileManager.default.enumerator(at: item, includingPropertiesForKeys: nil) else { continue }
            for case _ as URL in enumerator { count += 1 }
        }
        return count
    }

    /// The output plus volumes created for it (`.part1.rar`, `.7z.001`…), written after `since`.
    static func writtenFiles(for output: URL, since: Date) -> [URL] {
        let directory = output.deletingLastPathComponent()
        let name = output.lastPathComponent
        let stem = (name as NSString).deletingPathExtension
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return contents.map { directory.appendingPathComponent($0) }.filter { url in
            let candidate = url.lastPathComponent
            let related = candidate == name
                || (candidate.hasPrefix(name + ".") && candidate.dropFirst(name.count + 1).allSatisfy(\.isNumber))
                || (candidate.hasPrefix(stem + ".part") && candidate.hasSuffix(".rar"))
            guard related else { return false }
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return modified >= since.addingTimeInterval(-1)
        }
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}

private final class ByteLineCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func add(_ data: Data) -> Int {
        lock.withLock {
            count += data.reduce(0) { $1 == UInt8(ascii: "\n") ? $0 + 1 : $0 }
            return count
        }
    }
}
