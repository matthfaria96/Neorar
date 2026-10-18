import Foundation
import Testing
@testable import NeorarCore

/// Needs RARLAB's rar; runs only when NEORAR_RAR points at it (RAR compression is proprietary and not bundled).
@Suite("RAR creation (RARLAB rar)", .enabled(if: ProcessInfo.processInfo.environment["NEORAR_RAR"] != nil))
struct RarCreationTests {
    @Test func createsEncryptedSolidRarWithVolumesAndReadsItBack() async throws {
        let sandbox = try Fixtures.sandbox(["plain.rar"])
        let out = sandbox.appendingPathComponent("extraido")
        _ = try await ExtractionService.extract(sandbox.appendingPathComponent("plain.rar"),
                                                options: ExtractionOptions(destination: out), password: nil, progress: { _ in })

        var options = CompressionOptions()
        options.format = .rar
        options.password = "s3gredo çñ"
        options.encryptNames = true
        options.recoveryRecord = true
        options.volumeSize = 100_000
        let recorder = ProgressRecorder()
        let written = try await CompressionService.compress([out.appendingPathComponent("plain")],
                                                            to: sandbox.appendingPathComponent("novo.rar"),
                                                            options: options, progress: recorder.record)
        #expect(written.count >= 3)
        #expect(written.first?.lastPathComponent == "novo.part1.rar")
        #expect(recorder.last == 1)

        await #expect(throws: ArchiveError.passwordRequired) {
            try await RarEngine().list(written[0], password: nil, codePage: nil)
        }
        let listing = try await RarEngine().list(written[0], password: "s3gredo çñ", codePage: nil)
        #expect(listing.hasEncryptedHeaders && listing.isSolid && listing.isMultiVolume)
        #expect(listing.entries.contains { $0.path == "plain/Projeto/docs/relatório final.txt" })
    }

    /// Network access is unavailable inside some test runners; opt in with NEORAR_NETWORK_TESTS=1.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["NEORAR_NETWORK_TESTS"] != nil))
    func latestReleaseIsFoundOnRarlab() async throws {
        let release = try await RarInstaller.latestRelease()
        #expect(release.url.absoluteString.hasPrefix("https://www.rarlab.com/rar/rarmacos-"))
        #expect(!release.url.lastPathComponent.contains("b"))
        #expect(release.version.contains("."))
    }
}

@Suite("RAR comments", .enabled(if: ProcessInfo.processInfo.environment["NEORAR_RAR"] != nil))
struct RarCommentTests {
    @Test func rarCommentIsWrittenAndRead() async throws {
        let sandbox = try Fixtures.sandbox()
        let file = sandbox.appendingPathComponent("b.txt")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        var options = CompressionOptions()
        options.format = .rar
        options.comment = "Comentário RAR ✓"
        let output = sandbox.appendingPathComponent("b.rar")
        _ = try await CompressionService.compress([file], to: output, options: options, progress: { _ in })
        let listing = try await RarEngine().list(output, password: nil, codePage: nil)
        #expect(listing.comment == "Comentário RAR ✓")
    }
}

@Suite("RAR editing", .enabled(if: ProcessInfo.processInfo.environment["NEORAR_RAR"] != nil))
struct RarEditTests {
    @Test func addAndDeleteInsideRar() async throws {
        let sandbox = try Fixtures.sandbox(["plain.rar"])
        let archive = sandbox.appendingPathComponent("plain.rar")
        let extra = sandbox.appendingPathComponent("extra.txt")
        try "e".write(to: extra, atomically: true, encoding: .utf8)
        var listing = try await RarEngine().list(archive, password: nil, codePage: nil)
        try await ArchiveEditor.add([extra], to: archive, inside: "Projeto/docs", listing: listing, password: nil, progress: { _ in })
        listing = try await RarEngine().list(archive, password: nil, codePage: nil)
        #expect(listing.entries.contains { $0.path == "Projeto/docs/extra.txt" })
        try await ArchiveEditor.delete(["solto.txt", "Projeto/docs/relatório final.txt"], from: archive, listing: listing, password: nil)
        listing = try await RarEngine().list(archive, password: nil, codePage: nil)
        let paths = Set(listing.entries.map(\.path))
        #expect(!paths.contains("solto.txt"))
        #expect(!paths.contains("Projeto/docs/relatório final.txt"))
        #expect(paths.contains("Projeto/leia-me.txt"))
    }
}

@Suite("RAR repair", .enabled(if: ProcessInfo.processInfo.environment["NEORAR_RAR"] != nil))
struct RarRepairTests {
    @Test func corruptedRarWithRecoveryRecordIsRepaired() async throws {
        let sandbox = try Fixtures.sandbox(["plain.rar"])
        let out = sandbox.appendingPathComponent("x")
        _ = try await ExtractionService.extract(sandbox.appendingPathComponent("plain.rar"), options: ExtractionOptions(destination: out),
                                                password: nil, progress: { _ in })
        var options = CompressionOptions()
        options.format = .rar
        options.recoveryRecord = true
        let archive = sandbox.appendingPathComponent("rr.rar")
        _ = try await CompressionService.compress([out.appendingPathComponent("plain")], to: archive, options: options, progress: { _ in })
        var data = try Data(contentsOf: archive)
        for index in 60_000..<60_300 { data[index] ^= 0x5A }
        try data.write(to: archive)
        await #expect(throws: ArchiveError.self) {
            try await ExtractionService.test(archive, password: nil, progress: { _ in })
        }
        let repaired = try await ArchiveRepair.repair(archive)
        #expect(repaired.lastPathComponent == "rr (reparado).rar")
        try await ExtractionService.test(repaired, password: nil, progress: { _ in })
    }
}
