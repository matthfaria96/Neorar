import Foundation

/// In-place editing of existing archives: add files (optionally inside a folder of the archive) and delete entries.
/// 7Z, ZIP and plain TAR go through the bundled 7-Zip; RAR needs RARLAB's own `rar`.
public enum ArchiveEditor {
    public enum Tool: Sendable { case sevenZip, rar }

    public static let rarNotice = "Editar arquivos RAR exige o rar oficial da RARLAB (o formato é proprietário). Ative-o em Ajustes › RAR."

    /// Whether (and with which tool) an archive can be edited in place.
    public static func tool(for archive: URL, listing: ArchiveListing) -> Result<Tool, ArchiveError> {
        if listing.isMultiVolume {
            return .failure(.failed(String(localized: "Arquivos divididos em partes não podem ser editados.")))
        }
        switch listing.format {
        case .rar:
            return ToolLocator.rar != nil ? .success(.rar) : .failure(.failed(rarNotice))
        case .sevenZip, .zip, .tar:
            return .success(.sevenZip)
        default:
            return .failure(.failed(String(localized: "Arquivos \(listing.format.displayName) não podem ser alterados no lugar. Extraia, altere e comprima de novo.")))
        }
    }

    // MARK: - Add

    /// Adds `items` under `folder` ("" = root). Entries with the same path are replaced.
    public static func add(_ items: [URL], to archive: URL, inside folder: String, listing: ArchiveListing,
                           password: String?, progress: @escaping ProgressHandler) async throws {
        guard !items.isEmpty else { return }
        let tool = try tool(for: archive, listing: listing).get()
        let folder = ArchiveEntry.normalize(folder)

        switch tool {
        case .rar:
            guard let rar = ToolLocator.rar else { throw ArchiveError.toolMissing("rar") }
            var arguments = ["a", "-ep1", "-idc", "-y", "-o+"]
            if !folder.isEmpty { arguments.append("-ap\(folder)") }
            var input: Data?
            if let password, !password.isEmpty {
                arguments.append(listing.hasEncryptedHeaders ? "-hp" : "-p")
                input = Data("\(password)\n\(password)\n".utf8)
            }
            arguments += ["--", archive.path] + items.map(\.path)
            let result = try await ProcessRunner.run(rar, arguments: arguments, stdin: input, onOutput: percent(progress))
            try checkRar(result)

        case .sevenZip:
            guard let sevenZip = ToolLocator.sevenZip else { throw ArchiveError.toolMissing("7zz") }
            var arguments = ["a", "-y", "-bsp1", "-bso0", "-bse2", "-sccUTF-8", "-mmt=on"]
            var input: Data?
            if let password, !password.isEmpty, listing.isEncrypted {
                arguments.append("-p")
                if listing.format == .zip { arguments.append("-mem=AES256") }
                if listing.hasEncryptedHeaders { arguments.append("-mhe=on") }
                input = Data("\(password)\n\(password)\n".utf8)
            }
            // Root additions use absolute paths (7-Zip stores the last component).
            // Additions inside a folder are staged as clones so the relative path becomes the archive path.
            var staging: URL?
            var cwd: URL?
            var sources = items.map(\.path)
            if !folder.isEmpty {
                let root = try stagingDirectory(near: items[0])
                let target = root.appendingPathComponent(folder, isDirectory: true)
                try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
                for item in items {
                    try FileManager.default.copyItem(at: item, to: target.appendingPathComponent(item.lastPathComponent))
                }
                staging = root
                cwd = root
                sources = [folder]
            }
            defer { staging.map { try? FileManager.default.removeItem(at: $0) } }
            arguments += ["--", archive.path] + sources
            let result = try await ProcessRunner.run(sevenZip, arguments: arguments, currentDirectory: cwd, stdin: input,
                                                     onOutput: percent(progress))
            if result.status > 1 {
                throw SevenZipEngine.classify(result, hadPassword: password != nil, destination: archive.deletingLastPathComponent())
                    ?? .failed(String(localized: "O 7-Zip terminou com o código \(result.status)."))
            }
        }
        progress(ExtractProgress(fraction: 1))
    }

    // MARK: - Delete

    /// Deletes `paths` (folders include everything below them).
    public static func delete(_ paths: Set<String>, from archive: URL, listing: ArchiveListing, password: String?) async throws {
        let matcher = SelectionMatcher(paths)
        let doomed = listing.entries.filter { matcher.matches($0.path) }.map(\.path)
        guard !doomed.isEmpty else { return }
        if doomed.count == listing.entries.count {
            throw ArchiveError.failed(String(localized: "Não é possível excluir todos os itens: o arquivo ficaria vazio. Mova o arquivo para o Lixo."))
        }
        let tool = try tool(for: archive, listing: listing).get()
        let listFile = FileManager.default.temporaryDirectory.appendingPathComponent("neorar-delete-\(UUID().uuidString).txt")
        try (doomed.joined(separator: "\n") + "\n").write(to: listFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: listFile) }
        let input = password.map { Data("\($0)\n\($0)\n".utf8) }

        switch tool {
        case .rar:
            guard let rar = ToolLocator.rar else { throw ArchiveError.toolMissing("rar") }
            var arguments = ["d", "-idc", "-y", "-scfl"]
            if password != nil { arguments.append("-p") }
            arguments += ["--", archive.path, "@\(listFile.path)"]
            try checkRar(try await ProcessRunner.run(rar, arguments: arguments, stdin: input))
        case .sevenZip:
            guard let sevenZip = ToolLocator.sevenZip else { throw ArchiveError.toolMissing("7zz") }
            // No "--": 7-Zip would take "@listfile" literally. Archive paths are absolute.
            let arguments = ["d", "-y", "-bso0", "-bse2", "-sccUTF-8", "-scsUTF-8", "-spd", archive.path, "@\(listFile.path)"]
            let result = try await ProcessRunner.run(sevenZip, arguments: arguments, stdin: input)
            if result.status > 1 {
                throw SevenZipEngine.classify(result, hadPassword: password != nil, destination: archive.deletingLastPathComponent())
                    ?? .failed(String(localized: "O 7-Zip terminou com o código \(result.status)."))
            }
        }
    }

    // MARK: - Helpers

    private static func percent(_ progress: @escaping ProgressHandler) -> @Sendable (Data) -> Void {
        { chunk in
            if let value = PercentParser.lastPercent(in: chunk) { progress(ExtractProgress(fraction: Double(value) / 100)) }
        }
    }

    /// A scratch folder on the same volume as `item`, so copies are instant APFS clones.
    private static func stagingDirectory(near item: URL) throws -> URL {
        let base = (try? FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                                 appropriateFor: item, create: true))
            ?? FileManager.default.temporaryDirectory
        let root = base.appendingPathComponent("neorar-add-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private static func checkRar(_ result: ProcessResult) throws {
        switch result.status {
        case 0, 1: return
        case 3: throw ArchiveError.corrupted(nil)
        case 5, 9: throw ArchiveError.cannotWrite("")
        case 11: throw ArchiveError.wrongPassword
        case 255: throw ArchiveError.cancelled
        default:
            let line = result.stdoutText.split(separator: "\n").last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
            throw ArchiveError.failed(String(localized: "O rar falhou (código \(result.status))") + (line.map { ": \($0)" } ?? "."))
        }
    }
}
