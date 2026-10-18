import Foundation

/// Optional fallback for legacy formats (StuffIt, ACE, ZOO, Amiga…) through The Unarchiver's
/// `lsar`/`unar`, used only when they are installed (e.g. `brew install unar`).
public struct UnarEngine: ArchiveEngine {
    let lsar: URL
    let unar: URL

    public static var ifAvailable: UnarEngine? {
        guard let lsar = ToolLocator.lsar, let unar = ToolLocator.unar else { return nil }
        return UnarEngine(lsar: lsar, unar: unar)
    }

    public func list(_ archive: URL, password: String?, codePage: Int?) async throws -> ArchiveListing {
        var arguments = ["-j"]
        if let password { arguments += ["-p", password] }
        if let encoding = Self.encodingName(codePage) { arguments += ["-e", encoding] }
        arguments.append(archive.path)
        let result = try await ProcessRunner.run(lsar, arguments: arguments)
        guard let json = try? JSONSerialization.jsonObject(with: result.stdout) as? [String: Any],
              let contents = json["lsarContents"] as? [[String: Any]] else {
            throw Self.classify(result.stderrText + result.stdoutText, hadPassword: password != nil)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        let entries = contents.enumerated().map { index, item in
            ArchiveEntry(
                id: index,
                path: item["XADFileName"] as? String ?? "?",
                isDirectory: (item["XADIsDirectory"] as? Bool) ?? ((item["XADIsDirectory"] as? Int) == 1),
                size: (item["XADFileSize"] as? NSNumber)?.uint64Value ?? 0,
                packedSize: (item["XADCompressedSize"] as? NSNumber)?.uint64Value ?? 0,
                modified: (item["XADLastModificationDate"] as? String).flatMap(formatter.date(from:)),
                isEncrypted: (item["XADIsEncrypted"] as? NSNumber)?.boolValue ?? false,
                isLink: item["XADLinkDestination"] != nil
            )
        }
        return ArchiveListing(archiveURL: archive, format: .other, entries: entries, codePage: codePage)
    }

    public func extract(_ archive: URL, to directory: URL, paths: Set<String>?, password: String?, codePage: Int?,
                        totalBytes: UInt64, progress: @escaping ProgressHandler) async throws {
        var arguments = ["-o", directory.path, "-f", "-D", "-k", "skip"]
        if let password { arguments += ["-p", password] }
        if let encoding = Self.encodingName(codePage) { arguments += ["-e", encoding] }
        arguments.append(archive.path)
        if let paths { arguments += paths.sorted() }

        let expected = max(1, paths?.count ?? 1)
        let counter = LineCounter()
        let result = try await ProcessRunner.run(unar, arguments: arguments, onOutput: { chunk in
            let lines = counter.add(chunk)
            progress(ExtractProgress(fraction: min(0.99, Double(lines) / Double(max(expected, lines + 1)))))
        })
        try Task.checkCancellation()
        if result.status != 0 {
            throw Self.classify(result.stderrText + result.stdoutText, hadPassword: password != nil)
        }
        progress(ExtractProgress(fraction: 1, bytesDone: totalBytes, bytesTotal: totalBytes))
    }

    private static func encodingName(_ codePage: Int?) -> String? {
        guard let codePage else { return nil }
        let cf = CFStringConvertWindowsCodepageToEncoding(UInt32(codePage))
        guard cf != kCFStringEncodingInvalidId, let name = CFStringConvertEncodingToIANACharSetName(cf) else { return nil }
        return name as String
    }

    private static func classify(_ text: String, hadPassword: Bool) -> ArchiveError {
        let lower = text.lowercased()
        if lower.contains("password") { return hadPassword ? .wrongPassword : .passwordRequired }
        if lower.contains("couldn't recognize") || lower.contains("unknown") { return .unsupportedFormat }
        if lower.contains("corrupt") || lower.contains("checksum") { return .corrupted(nil) }
        return .failed(text.split(separator: "\n").last.map(String.init) ?? "Falha no unar.")
    }
}

private final class LineCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func add(_ data: Data) -> Int {
        lock.withLock {
            count += data.reduce(0) { $1 == UInt8(ascii: "\n") ? $0 + 1 : $0 }
            return count
        }
    }
}
