import Foundation
import Testing
@testable import NeorarCore

@Suite("RAR engine (UnRAR in-process)")
struct RarEngineTests {
    @Test func listsPlainArchive() async throws {
        let listing = try await RarEngine().list(Fixtures.url("plain.rar"), password: nil, codePage: nil)
        let paths = Set(listing.entries.map(\.path))
        #expect(paths.contains("Projeto/leia-me.txt"))
        #expect(paths.contains("Projeto/docs/relatório final.txt"))
        #expect(paths.contains("solto.txt"))
        #expect(listing.entries.first { $0.path == "Projeto/docs" }?.isDirectory == true)
        #expect(listing.entries.first { $0.path == "Projeto/docs/dados.bin" }?.size == 250_000)
        #expect(!listing.isEncrypted)
        #expect(listing.entries.allSatisfy { $0.modified != nil })
    }

    @Test func extractsEverythingWithProgress() async throws {
        let out = try Fixtures.sandbox()
        let recorder = ProgressRecorder()
        let listing = try await RarEngine().list(Fixtures.url("plain.rar"), password: nil, codePage: nil)
        try await RarEngine().extract(Fixtures.url("plain.rar"), to: out, paths: nil, password: nil, codePage: nil,
                                      totalBytes: listing.totalSize, progress: recorder.record)
        let text = try String(contentsOf: out.appendingPathComponent("Projeto/leia-me.txt"), encoding: .utf8)
        #expect(text == "Olá, Neorar!\n")
        #expect(FileManager.default.fileExists(atPath: out.appendingPathComponent("Projeto/docs/relatório final.txt").path))
        #expect(recorder.last == 1)
    }

    @Test func extractsOnlySelection() async throws {
        let out = try Fixtures.sandbox()
        try await RarEngine().extract(Fixtures.url("plain.rar"), to: out, paths: ["Projeto/docs"], password: nil,
                                      codePage: nil, totalBytes: 0, progress: { _ in })
        let files = Fixtures.contents(of: out)
        #expect(files.contains("Projeto/docs/dados.bin"))
        #expect(!files.contains("Projeto/leia-me.txt"))
        #expect(!files.contains("solto.txt"))
    }

    @Test func encryptedFilesNeedPassword() async throws {
        let archive = Fixtures.url("encrypted.rar")
        let listing = try await RarEngine().list(archive, password: nil, codePage: nil)
        #expect(listing.isEncrypted)
        #expect(!listing.hasEncryptedHeaders)

        let out = try Fixtures.sandbox()
        await #expect(throws: ArchiveError.passwordRequired) {
            try await RarEngine().extract(archive, to: out, paths: nil, password: nil, codePage: nil, totalBytes: 0, progress: { _ in })
        }
        await #expect(throws: ArchiveError.wrongPassword) {
            try await RarEngine().extract(archive, to: out, paths: nil, password: "errada", codePage: nil, totalBytes: 0, progress: { _ in })
        }
        try await RarEngine().extract(archive, to: out, paths: nil, password: "senha123", codePage: nil, totalBytes: 0, progress: { _ in })
        #expect(try String(contentsOf: out.appendingPathComponent("Projeto/leia-me.txt"), encoding: .utf8) == "Olá, Neorar!\n")
    }

    @Test func encryptedHeadersNeedPasswordToList() async throws {
        let archive = Fixtures.url("encrypted-headers.rar")
        await #expect(throws: ArchiveError.passwordRequired) {
            try await RarEngine().list(archive, password: nil, codePage: nil)
        }
        await #expect(throws: ArchiveError.wrongPassword) {
            try await RarEngine().list(archive, password: "errada", codePage: nil)
        }
        let listing = try await RarEngine().list(archive, password: "senha123", codePage: nil)
        #expect(listing.hasEncryptedHeaders)
        #expect(listing.entries.contains { $0.path == "Projeto/leia-me.txt" })
    }

    @Test func multiVolumeListsOnceAndExtracts() async throws {
        let sandbox = try Fixtures.sandbox(["volumes.part1.rar", "volumes.part2.rar", "volumes.part3.rar"])
        let archive = sandbox.appendingPathComponent("volumes.part1.rar")
        let listing = try await RarEngine().list(archive, password: nil, codePage: nil)
        #expect(listing.isMultiVolume)
        #expect(listing.entries.filter { $0.path == "Projeto/docs/dados.bin" }.count == 1)

        let out = sandbox.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try await RarEngine().extract(archive, to: out, paths: nil, password: nil, codePage: nil, totalBytes: 0, progress: { _ in })
        let size = try FileManager.default.attributesOfItem(atPath: out.appendingPathComponent("Projeto/docs/dados.bin").path)[.size] as? Int
        #expect(size == 250_000)
    }

    @Test func missingVolumeIsReported() async throws {
        let sandbox = try Fixtures.sandbox(["volumes.part1.rar", "volumes.part3.rar"])
        let out = sandbox.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        do {
            try await RarEngine().extract(sandbox.appendingPathComponent("volumes.part1.rar"), to: out, paths: nil,
                                          password: nil, codePage: nil, totalBytes: 0, progress: { _ in })
            Issue.record("Esperava erro de volume ausente")
        } catch let error as ArchiveError {
            guard case .missingVolume(let name) = error else { Issue.record("Erro inesperado: \(error)"); return }
            #expect(name?.hasSuffix("volumes.part2.rar") == true)
        }
    }

    @Test func cancellationStopsExtraction() async throws {
        let out = try Fixtures.sandbox()
        let task = Task {
            try await RarEngine().extract(Fixtures.url("plain.rar"), to: out, paths: nil, password: nil, codePage: nil,
                                          totalBytes: 0, progress: { _ in })
        }
        task.cancel()
        let result = await task.result
        if case .failure(let error) = result { #expect(error as? ArchiveError == .cancelled) }
    }
}

final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Double] = []
    var last: Double? { lock.withLock { values.last } }
    var record: ProgressHandler {
        { [self] progress in lock.withLock { values.append(progress.fraction) } }
    }
}

@Suite("Integrity test")
struct IntegrityTests {
    init() { Fixtures.useVendored7zz() }

    @Test func goodArchivesPass() async throws {
        try await ExtractionService.test(Fixtures.url("plain.rar"), password: nil, progress: { _ in })
        try await ExtractionService.test(Fixtures.url("encrypted.rar"), password: "senha123", progress: { _ in })
    }

    @Test func corruptedRarFails() async throws {
        let sandbox = try Fixtures.sandbox(["plain.rar"])
        let file = sandbox.appendingPathComponent("plain.rar")
        var data = try Data(contentsOf: file)
        for index in stride(from: 5_000, to: 6_000, by: 7) { data[index] ^= 0xFF }
        try data.write(to: file)
        await #expect(throws: ArchiveError.self) {
            try await ExtractionService.test(file, password: nil, progress: { _ in })
        }
    }

    @Test func wrongPasswordFailsTest() async throws {
        await #expect(throws: ArchiveError.wrongPassword) {
            try await ExtractionService.test(Fixtures.url("encrypted.rar"), password: "errada", progress: { _ in })
        }
    }
}
