import Foundation
import Testing
@testable import NeorarCore

@Suite("Extraction, compression and 7-Zip", .serialized)
struct ServiceTests {
    init() { Fixtures.useVendored7zz() }

    @Test func smartFolderWrapsMultipleRoots() async throws {
        let sandbox = try Fixtures.sandbox(["plain.rar"])
        var options = ExtractionOptions(destination: sandbox)
        options.folderPolicy = .smart
        let result = try await ExtractionService.extract(sandbox.appendingPathComponent("plain.rar"), options: options,
                                                         password: nil, progress: { _ in })
        #expect(result.createdFolder?.lastPathComponent == "plain")
        #expect(FileManager.default.fileExists(atPath: sandbox.appendingPathComponent("plain/Projeto/leia-me.txt").path))
        #expect(FileManager.default.fileExists(atPath: sandbox.appendingPathComponent("plain/solto.txt").path))
        // No staging folder is left behind.
        #expect(try FileManager.default.contentsOfDirectory(atPath: sandbox.path).allSatisfy { !$0.hasPrefix(".neorar-") })
    }

    @Test func smartFolderSkipsSingleRootAndRenamesConflicts() async throws {
        let sandbox = try Fixtures.sandbox(["encrypted.rar"])
        try FileManager.default.createDirectory(at: sandbox.appendingPathComponent("Projeto"), withIntermediateDirectories: true)
        let options = ExtractionOptions(destination: sandbox)
        let result = try await ExtractionService.extract(sandbox.appendingPathComponent("encrypted.rar"), options: options,
                                                         password: "senha123", progress: { _ in })
        #expect(result.createdFolder == nil)
        #expect(result.items.map(\.lastPathComponent) == ["Projeto 2"])
    }

    @Test func extractionRequiresPasswordUpFront() async throws {
        let sandbox = try Fixtures.sandbox(["encrypted.rar"])
        await #expect(throws: ArchiveError.passwordRequired) {
            try await ExtractionService.extract(sandbox.appendingPathComponent("encrypted.rar"),
                                                options: ExtractionOptions(destination: sandbox), password: nil, progress: { _ in })
        }
    }

    @Test func selectionIsPlacedWithoutParents() async throws {
        let sandbox = try Fixtures.sandbox(["plain.rar"])
        var options = ExtractionOptions(destination: sandbox.appendingPathComponent("out"))
        options.selection = ["Projeto/docs/relatório final.txt"]
        let result = try await ExtractionService.extract(sandbox.appendingPathComponent("plain.rar"), options: options,
                                                         password: nil, progress: { _ in })
        #expect(result.items.map(\.lastPathComponent) == ["relatório final.txt"])
        #expect(Fixtures.contents(of: sandbox.appendingPathComponent("out")) == ["relatório final.txt"])
    }

    @Test func trashesAllVolumesAfterExtraction() async throws {
        let sandbox = try Fixtures.sandbox(["volumes.part1.rar", "volumes.part2.rar", "volumes.part3.rar"])
        var options = ExtractionOptions(destination: sandbox)
        options.trashArchiveAfter = true
        _ = try await ExtractionService.extract(sandbox.appendingPathComponent("volumes.part2.rar"), options: options,
                                                password: nil, progress: { _ in })
        #expect(Fixtures.contents(of: sandbox).allSatisfy { !$0.hasSuffix(".rar") })
        #expect(FileManager.default.fileExists(atPath: sandbox.appendingPathComponent("Projeto/docs/dados.bin").path))
    }

    @Test(arguments: [CompressionFormat.sevenZip, .zip, .tarGz, .tarXz, .tarBz2])
    func compressAndExtractRoundTrip(format: CompressionFormat) async throws {
        let sandbox = try Fixtures.sandbox(["plain.rar"])
        let source = sandbox.appendingPathComponent("src")
        try FileManager.default.createDirectory(at: source.appendingPathComponent("Pasta/sub"), withIntermediateDirectories: true)
        try "um".write(to: source.appendingPathComponent("Pasta/ação.txt"), atomically: true, encoding: .utf8)
        try "dois".write(to: source.appendingPathComponent("Pasta/sub/b.txt"), atomically: true, encoding: .utf8)
        try "lixo".write(to: source.appendingPathComponent("Pasta/.DS_Store"), atomically: true, encoding: .utf8)

        var options = CompressionOptions()
        options.format = format
        if format.supportsPassword { options.password = "s3gredo" }
        let output = sandbox.appendingPathComponent("saida.\(format.fileExtension)")
        let written = try await CompressionService.compress([source.appendingPathComponent("Pasta")], to: output,
                                                            options: options, progress: { _ in })
        #expect(written == [output])

        let (listing, _) = try await Engines.list(output, password: options.password, codePage: nil)
        let paths = Set(listing.entries.map(\.path))
        #expect(paths.contains("Pasta/ação.txt"))
        #expect(paths.contains("Pasta/sub/b.txt"))
        #expect(!paths.contains("Pasta/.DS_Store"))
        if format == .sevenZip { #expect(listing.hasEncryptedHeaders) }

        let out = sandbox.appendingPathComponent("out")
        var extraction = ExtractionOptions(destination: out)
        extraction.folderPolicy = .never
        _ = try await ExtractionService.extract(output, options: extraction, password: options.password, progress: { _ in })
        #expect(try String(contentsOf: out.appendingPathComponent("Pasta/ação.txt"), encoding: .utf8) == "um")
    }

    @Test func sevenZipWrongPasswordIsDetected() async throws {
        let sandbox = try Fixtures.sandbox()
        let file = sandbox.appendingPathComponent("a.txt")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        var options = CompressionOptions()
        options.format = .zip
        options.password = "certa"
        let output = sandbox.appendingPathComponent("a.zip")
        _ = try await CompressionService.compress([file], to: output, options: options, progress: { _ in })
        let out = sandbox.appendingPathComponent("out")
        await #expect(throws: ArchiveError.wrongPassword) {
            try await ExtractionService.extract(output, options: ExtractionOptions(destination: out), password: "errada", progress: { _ in })
        }
    }

    @Test func sevenZipOpensRarToo() async throws {
        let listing = try await SevenZipEngine().list(Fixtures.url("plain.rar"), password: nil, codePage: nil)
        #expect(listing.entries.contains { $0.path == "Projeto/docs/relatório final.txt" })
    }

    @Test func notAnArchiveIsUnsupported() async throws {
        let sandbox = try Fixtures.sandbox()
        let file = sandbox.appendingPathComponent("texto.zip")
        try "não sou zip".write(to: file, atomically: true, encoding: .utf8)
        await #expect(throws: ArchiveError.unsupportedFormat) {
            try await SevenZipEngine().list(file, password: nil, codePage: nil)
        }
    }
}

@Suite("Helpers")
struct HelperTests {
    @Test func volumeSets() throws {
        let sandbox = try Fixtures.sandbox()
        for name in ["a.part1.rar", "a.part2.rar", "a.part10.rar", "b.rar", "b.r00", "b.r01", "c.7z.001", "c.7z.002", "d.rar"] {
            FileManager.default.createFile(atPath: sandbox.appendingPathComponent(name).path, contents: Data())
        }
        func resolve(_ name: String) -> VolumeSet { VolumeSet.resolve(sandbox.appendingPathComponent(name)) }
        #expect(resolve("a.part2.rar").first.lastPathComponent == "a.part1.rar")
        #expect(resolve("a.part2.rar").members.map(\.lastPathComponent) == ["a.part1.rar", "a.part2.rar", "a.part10.rar"])
        #expect(resolve("b.r01").first.lastPathComponent == "b.rar")
        #expect(resolve("b.rar").members.count == 3)
        #expect(resolve("c.7z.002").first.lastPathComponent == "c.7z.001")
        #expect(resolve("d.rar").members.count == 1)

        let grouped = VolumeSet.group(["a.part1.rar", "a.part2.rar", "b.r00", "b.rar", "d.rar"].map { sandbox.appendingPathComponent($0) })
        #expect(grouped.map(\.first.lastPathComponent) == ["a.part1.rar", "b.rar", "d.rar"])
    }

    @Test(arguments: [
        ("Fotos.part01.rar", "Fotos"), ("backup.tar.gz", "backup"), ("a.7z.001", "a"),
        ("Relatório.zip", "Relatório"), ("v1.2.rar", "v1.2"), ("fotos.r00", "fotos"),
    ])
    func baseNames(input: String, expected: String) {
        #expect(FileNaming.baseName(of: URL(fileURLWithPath: "/tmp/\(input)")) == expected)
    }

    @Test func percentParser() {
        #expect(PercentParser.lastPercent(in: Data("  0%\u{8}\u{8}\u{8}\u{8} 40% 4 + x\u{8}\u{8} 86%".utf8)) == 86)
        #expect(PercentParser.lastPercent(in: Data("nada".utf8)) == nil)
    }

    @Test func technicalListingParser() {
        let text = """
        Path = pasta/a.txt
        Folder = -
        Size = 12
        Packed Size = 10
        Modified = 2026-10-16 08:42:27.430514788
        Encrypted = +

        Path = pasta
        Folder = +
        Size = 0
        Packed Size = 0
        Modified = 2026-10-16 08:42:27

        """
        let entries = SevenZipEngine.parseTechnicalListing(text)
        #expect(entries.count == 2)
        #expect(entries[0].path == "pasta/a.txt" && entries[0].size == 12 && entries[0].isEncrypted)
        #expect(entries[1].isDirectory)
    }

    @Test func topLevelSelections() {
        #expect(ExtractionService.topLevelSelections(["a", "a/b", "a/b/c", "d/e"]) == ["a", "d/e"])
    }
}

@Suite("Conflict planning")
struct ConflictTests {
    @Test func plannedNamesFollowFolderPolicy() async throws {
        let sandbox = try Fixtures.sandbox(["plain.rar", "encrypted.rar"])
        let plain = sandbox.appendingPathComponent("plain.rar")
        let (listing, _) = try await ExtractionService.prepare(plain, password: nil, codePage: nil)
        var options = ExtractionOptions(destination: sandbox)
        #expect(ExtractionService.plannedNames(for: plain, listing: listing, options: options) == ["plain"])
        options.folderPolicy = .never
        #expect(Set(ExtractionService.plannedNames(for: plain, listing: listing, options: options)) == ["Projeto", "solto.txt"])
        #expect(ExtractionService.conflicts(for: plain, listing: listing, options: options).isEmpty)
        FileManager.default.createFile(atPath: sandbox.appendingPathComponent("solto.txt").path, contents: Data())
        #expect(ExtractionService.conflicts(for: plain, listing: listing, options: options) == ["solto.txt"])
        options.selection = ["Projeto/docs/dados.bin"]
        #expect(ExtractionService.plannedNames(for: plain, listing: listing, options: options) == ["dados.bin"])
    }
}

@Suite("Archive comments", .serialized)
struct CommentTests {
    init() { Fixtures.useVendored7zz() }

    @Test func zipCommentRoundTrip() async throws {
        let sandbox = try Fixtures.sandbox()
        let file = sandbox.appendingPathComponent("a.txt")
        try "conteúdo".write(to: file, atomically: true, encoding: .utf8)
        var options = CompressionOptions()
        options.format = .zip
        options.comment = "Olá! Comentário com acentos\nsegunda linha"
        let output = sandbox.appendingPathComponent("a.zip")
        _ = try await CompressionService.compress([file], to: output, options: options, progress: { _ in })
        #expect(ZipComment.read(output) == options.comment)

        let (listing, _) = try await Engines.list(output, password: nil, codePage: nil)
        #expect(listing.comment == options.comment)
        // The archive must still be valid after rewriting the end record.
        try await ExtractionService.test(output, password: nil, progress: { _ in })
        ZipCommentCheck.replace(output)
        #expect(ZipComment.read(output) == "curto")
    }

    @Test func archivesWithoutCommentReportNil() async throws {
        let listing = try await RarEngine().list(Fixtures.url("plain.rar"), password: nil, codePage: nil)
        #expect(listing.comment == nil)
    }
}

enum ZipCommentCheck {
    static func replace(_ url: URL) {
        try? ZipComment.write("curto", to: url)
    }
}

@Suite("Archive editing", .serialized)
struct EditTests {
    init() { Fixtures.useVendored7zz() }

    private func makeArchive(_ format: CompressionFormat, in sandbox: URL, password: String? = nil) async throws -> URL {
        let source = sandbox.appendingPathComponent("src/Pasta/sub")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try "um".write(to: sandbox.appendingPathComponent("src/Pasta/a.txt"), atomically: true, encoding: .utf8)
        try "dois".write(to: source.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        var options = CompressionOptions()
        options.format = format
        options.password = password
        let output = sandbox.appendingPathComponent("arq.\(format.fileExtension)")
        _ = try await CompressionService.compress([sandbox.appendingPathComponent("src/Pasta")], to: output, options: options, progress: { _ in })
        return output
    }

    @Test(arguments: [CompressionFormat.sevenZip, .zip])
    func addAtRootAndInsideFolderThenDelete(format: CompressionFormat) async throws {
        let sandbox = try Fixtures.sandbox()
        let archive = try await makeArchive(format, in: sandbox)
        let extra = sandbox.appendingPathComponent("novo ç.txt")
        try "três".write(to: extra, atomically: true, encoding: .utf8)

        var (listing, _) = try await Engines.list(archive, password: nil, codePage: nil)
        try await ArchiveEditor.add([extra], to: archive, inside: "", listing: listing, password: nil, progress: { _ in })
        try await ArchiveEditor.add([extra], to: archive, inside: "Pasta/sub", listing: listing, password: nil, progress: { _ in })
        (listing, _) = try await Engines.list(archive, password: nil, codePage: nil)
        let paths = Set(listing.entries.map(\.path))
        #expect(paths.contains("novo ç.txt"))
        #expect(paths.contains("Pasta/sub/novo ç.txt"))
        #expect(paths.contains("Pasta/a.txt"))

        try await ArchiveEditor.delete(["Pasta/sub"], from: archive, listing: listing, password: nil)
        (listing, _) = try await Engines.list(archive, password: nil, codePage: nil)
        let after = Set(listing.entries.map(\.path))
        #expect(!after.contains("Pasta/sub/b.txt"))
        #expect(!after.contains("Pasta/sub/novo ç.txt"))
        #expect(after.contains("Pasta/a.txt"))
        try await ExtractionService.test(archive, password: nil, progress: { _ in })
    }

    @Test func encryptedSevenZipKeepsEncryptionWhenAdding() async throws {
        let sandbox = try Fixtures.sandbox()
        let archive = try await makeArchive(.sevenZip, in: sandbox, password: "pw")
        let extra = sandbox.appendingPathComponent("x.txt")
        try "x".write(to: extra, atomically: true, encoding: .utf8)
        var (listing, _) = try await Engines.list(archive, password: "pw", codePage: nil)
        try await ArchiveEditor.add([extra], to: archive, inside: "", listing: listing, password: "pw", progress: { _ in })
        await #expect(throws: ArchiveError.passwordRequired) {
            try await Engines.list(archive, password: nil, codePage: nil)
        }
        (listing, _) = try await Engines.list(archive, password: "pw", codePage: nil)
        #expect(listing.entries.contains { $0.path == "x.txt" && $0.isEncrypted })
    }

    @Test func compressedTarballsAreNotEditable() async throws {
        let sandbox = try Fixtures.sandbox()
        let archive = try await makeArchive(.tarGz, in: sandbox)
        let (listing, _) = try await Engines.list(archive, password: nil, codePage: nil)
        guard case .failure = ArchiveEditor.tool(for: archive, listing: listing) else {
            Issue.record("tar.gz não deveria ser editável")
            return
        }
    }
}

@Suite("7-Zip selective extraction", .serialized)
struct SevenZipSelectionTests {
    init() { Fixtures.useVendored7zz() }

    @Test func selectionFromSevenZipArchive() async throws {
        let sandbox = try Fixtures.sandbox()
        let source = sandbox.appendingPathComponent("Pasta/sub")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try "um".write(to: sandbox.appendingPathComponent("Pasta/a.txt"), atomically: true, encoding: .utf8)
        try "dois".write(to: source.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        var options = CompressionOptions()
        options.format = .sevenZip
        let archive = sandbox.appendingPathComponent("s.7z")
        _ = try await CompressionService.compress([sandbox.appendingPathComponent("Pasta")], to: archive, options: options, progress: { _ in })
        var extraction = ExtractionOptions(destination: sandbox.appendingPathComponent("out"))
        extraction.selection = ["Pasta/sub"]
        let result = try await ExtractionService.extract(archive, options: extraction, password: nil, progress: { _ in })
        #expect(result.items.map(\.lastPathComponent) == ["sub"])
        #expect(Fixtures.contents(of: sandbox.appendingPathComponent("out")) == ["sub", "sub/b.txt"])
    }

    @Test func headerEncryptedSevenZipAsksForPassword() async throws {
        let sandbox = try Fixtures.sandbox()
        let file = sandbox.appendingPathComponent("a.txt")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        var options = CompressionOptions()
        options.format = .sevenZip
        options.password = "pw"
        let archive = sandbox.appendingPathComponent("e.7z")
        _ = try await CompressionService.compress([file], to: archive, options: options, progress: { _ in })
        await #expect(throws: ArchiveError.passwordRequired) {
            try await Engines.list(archive, password: nil, codePage: nil)
        }
    }
}

@Suite("Repair", .serialized)
struct RepairTests {
    init() { Fixtures.useVendored7zz() }

    @Test func truncatedZipIsRepaired() async throws {
        let sandbox = try Fixtures.sandbox()
        let folder = sandbox.appendingPathComponent("Pasta")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try String(repeating: "Neorar ", count: 4000).write(to: folder.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "b".write(to: folder.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        var options = CompressionOptions()
        options.format = .zip
        let archive = sandbox.appendingPathComponent("dados.zip")
        _ = try await CompressionService.compress([folder], to: archive, options: options, progress: { _ in })
        // Chop off the central directory.
        let data = try Data(contentsOf: archive)
        try data.prefix(data.count - 60).write(to: archive)
        await #expect(throws: ArchiveError.self) {
            try await ExtractionService.test(archive, password: nil, progress: { _ in })
        }
        let repaired = try await ArchiveRepair.repair(archive)
        #expect(repaired.lastPathComponent == "dados (reparado).zip")
        try await ExtractionService.test(repaired, password: nil, progress: { _ in })
        let (listing, _) = try await Engines.list(repaired, password: nil, codePage: nil)
        #expect(listing.entries.contains { $0.path == "Pasta/a.txt" })
    }

    @Test func sevenZipHasNoRepair() async throws {
        guard case .failure = ArchiveRepair.method(for: Fixtures.url("plain.rar").deletingPathExtension().appendingPathExtension("7z")) else {
            Issue.record("7z não deveria ter reparo")
            return
        }
    }
}
