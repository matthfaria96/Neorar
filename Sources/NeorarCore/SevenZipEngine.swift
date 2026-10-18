import Foundation

/// Every non-RAR format, driven through the official 7-Zip console binary bundled with the app.
public struct SevenZipEngine: ArchiveEngine {
    public init() {}

    /// Extensions only XADMaster (unar) understands; everything else is tried with 7-Zip first.
    static let unarOnlyExtensions: Set<String> = [
        "sit", "sitx", "hqx", "cpt", "sea", "ace", "zoo", "arc", "pak", "lbr", "adf", "adz", "dms",
        "lzx", "alz", "pma", "ha", "nsa", "sar", "warc", "dd", "pit", "now", "macbin", "as",
    ]

    static func likelySupports(_ archive: URL) -> Bool {
        !unarOnlyExtensions.contains(archive.pathExtension.lowercased())
    }

    private func tool() throws -> URL {
        guard let url = ToolLocator.sevenZip else { throw ArchiveError.toolMissing("7zz") }
        return url
    }

    public func list(_ archive: URL, password: String?, codePage: Int?) async throws -> ArchiveListing {
        var arguments = ["l", "-slt", "-ba", "-sccUTF-8"]
        if let codePage { arguments.append("-mcp=\(codePage)") }
        arguments += ["--", archive.path]
        let result = try await ProcessRunner.run(try tool(), arguments: arguments, stdin: passwordInput(password))
        if result.status > 1, let error = Self.classify(result, hadPassword: password != nil, destination: nil) {
            throw error
        }
        let entries = Self.parseTechnicalListing(result.stdoutText)
        let encryptedHeaders = password != nil
            && (result.stderrText + result.stdoutText).contains("Enter password")
        return ArchiveListing(
            archiveURL: archive, format: ArchiveFormat.sniff(archive), entries: entries,
            hasEncryptedHeaders: encryptedHeaders,
            isMultiVolume: VolumeSet.resolve(archive).members.count > 1,
            codePage: codePage,
            comment: ArchiveFormat.sniff(archive) == .zip ? ZipComment.read(archive, codePage: codePage) : nil
        )
    }

    public func extract(_ archive: URL, to directory: URL, paths: Set<String>?, password: String?, codePage: Int?,
                        totalBytes: UInt64, progress: @escaping ProgressHandler) async throws {
        var arguments = ["x", "-y", "-aoa", "-bsp1", "-bso0", "-bse2", "-sccUTF-8", "-scsUTF-8", "-spd",
                         "-o\(directory.path)"]
        if let codePage { arguments.append("-mcp=\(codePage)") }
        var listFile: URL?
        if let paths, !paths.isEmpty {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("neorar-\(UUID().uuidString).txt")
            try paths.sorted().joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
            listFile = file
        }
        defer { listFile.map { try? FileManager.default.removeItem(at: $0) } }
        // No "--" here: it would make 7-Zip read "@listfile" as a literal name. Archive paths are absolute ("/…").
        arguments.append(archive.path)
        if let listFile { arguments.append("@\(listFile.path)") }

        let result = try await ProcessRunner.run(
            try tool(), arguments: arguments, stdin: passwordInput(password),
            onOutput: { chunk in
                guard let percent = PercentParser.lastPercent(in: chunk) else { return }
                let fraction = Double(percent) / 100
                progress(ExtractProgress(fraction: fraction, bytesDone: UInt64(Double(totalBytes) * fraction), bytesTotal: totalBytes))
            }
        )
        try Task.checkCancellation()
        if result.status != 0, let error = Self.classify(result, hadPassword: password != nil, destination: directory) {
            throw error
        }
        progress(ExtractProgress(fraction: 1, bytesDone: totalBytes, bytesTotal: totalBytes))
    }

    public func test(_ archive: URL, password: String?, codePage: Int?, totalBytes: UInt64,
                     progress: @escaping ProgressHandler) async throws {
        var arguments = ["t", "-bsp1", "-bso0", "-bse2", "-sccUTF-8"]
        if let codePage { arguments.append("-mcp=\(codePage)") }
        arguments += ["--", archive.path]
        let result = try await ProcessRunner.run(try tool(), arguments: arguments, stdin: passwordInput(password),
                                                 onOutput: { chunk in
            if let percent = PercentParser.lastPercent(in: chunk) { progress(ExtractProgress(fraction: Double(percent) / 100)) }
        })
        try Task.checkCancellation()
        if result.status != 0, let error = Self.classify(result, hadPassword: password != nil, destination: nil) {
            throw error
        }
        progress(ExtractProgress(fraction: 1, bytesDone: totalBytes, bytesTotal: totalBytes))
    }

    private func passwordInput(_ password: String?) -> Data? {
        // Passwords travel over stdin so they never show up in the process list.
        password.map { Data(($0 + "\n").utf8) }
    }

    // MARK: - Parsing

    static func parseTechnicalListing(_ text: String) -> [ArchiveEntry] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        var entries: [ArchiveEntry] = []
        var fields: [Substring: Substring] = [:]

        func flush() {
            defer { fields.removeAll(keepingCapacity: true) }
            guard let path = fields["Path"], fields["Type"] == nil else { return }
            let attributes = fields["Attributes"] ?? ""
            let isDirectory = fields["Folder"] == "+" || attributes.hasPrefix("D")
            var modified: Date?
            if let raw = fields["Modified"], raw.count >= 19 { modified = formatter.date(from: String(raw.prefix(19))) }
            let link = fields["Symbolic Link"].map { !$0.isEmpty } ?? false
            entries.append(ArchiveEntry(
                id: entries.count, path: String(path), isDirectory: isDirectory,
                size: UInt64(fields["Size"] ?? "") ?? 0,
                packedSize: UInt64(fields["Packed Size"] ?? "") ?? 0,
                modified: modified,
                isEncrypted: fields["Encrypted"] == "+",
                isLink: link
            ))
        }

        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = line.hasSuffix("\r") ? line.dropLast() : line
            if line.isEmpty {
                flush()
                continue
            }
            guard let separator = line.range(of: " = ") else {
                if line.hasSuffix(" =") { fields[line.dropLast(2)] = "" }
                continue
            }
            fields[line[..<separator.lowerBound]] = line[separator.upperBound...]
        }
        flush()
        return entries.filter { !$0.path.isEmpty }
    }

    static func classify(_ result: ProcessResult, hadPassword: Bool, destination: URL?) -> ArchiveError? {
        let text = result.stderrText + "\n" + result.stdoutText
        func has(_ needle: String) -> Bool { text.range(of: needle, options: .caseInsensitive) != nil }

        // 7-Zip asks for a password on stdin; with none supplied it hits EOF and reports "Break signaled".
        if has("Enter password") && !hadPassword { return .passwordRequired }
        if result.status == 255 || has("Break signaled") { return .cancelled }
        if has("Wrong password") || has("Can not open encrypted archive") || has("Cannot open encrypted archive") {
            return hadPassword ? .wrongPassword : .passwordRequired
        }
        if has("Missing volume") { return .missingVolume(nil) }
        if has("Unexpected end of archive") { return .corrupted(String(localized: "Ele está incompleto ou foi cortado no final.")) }
        if has("Cannot open the file as archive") || has("Can not open the file as archive") || has("Is not archive")
            || has("Unsupported Method") {
            return .unsupportedFormat
        }
        if has("No space left") || has("not enough space") { return .diskFull }
        if has("Permission denied") || has("Access is denied") {
            return .cannotWrite(destination?.path ?? "")
        }
        if has("Data Error") || has("CRC Failed") || has("Headers Error") {
            return .corrupted(nil)
        }
        if result.status == 1 { return nil } // Warnings only.
        if let line = text.split(separator: "\n").first(where: { $0.contains("ERROR:") }) {
            return .failed(String(line).replacingOccurrences(of: "ERROR: ", with: ""))
        }
        // Fatal error with no explanation (e.g. "-ba" hides the summary): the archive itself is broken.
        return .corrupted(String(localized: "Ele pode estar danificado ou incompleto."))
    }
}
