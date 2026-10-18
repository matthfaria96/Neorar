import Foundation

/// Downloads RARLAB's official command-line `rar` for the user. RAR compression is proprietary,
/// so Neorar never ships it; the user installs it from RARLAB under RARLAB's own (shareware) license.
public enum RarInstaller {
    static let downloadPage = URL(string: "https://www.rarlab.com/download.htm")!

    public struct Release: Sendable {
        public let version: String
        public let url: URL
    }

    public static func latestRelease() async throws -> Release {
        let (data, _) = try await URLSession.shared.data(from: downloadPage)
        let html = String(decoding: data, as: UTF8.self)
        #if arch(arm64)
        let arch = "arm"
        #else
        let arch = "x64"
        #endif
        // Stable builds only: beta archives carry a "b" suffix (rarmacos-arm-730b1).
        let releases = html.matches(of: /rar\/rarmacos-(arm|x64)-(\d+)\.tar\.gz/)
            .filter { $0.1 == arch }
            .compactMap { match -> (Int, String)? in Int(match.2).map { ($0, String(match.0)) } }
        guard let best = releases.max(by: { $0.0 < $1.0 }) else {
            throw ArchiveError.failed(String(localized: "Não encontrei o rar para macOS na página da RARLAB."))
        }
        let digits = String(best.0)
        let version = digits.count > 1 ? "\(digits.prefix(digits.count - 2)).\(digits.suffix(2))" : digits
        return Release(version: version, url: URL(string: "https://www.rarlab.com/\(best.1)")!)
    }

    /// Installs into ~/Library/Application Support/Neorar/RAR and returns the `rar` executable.
    public static func install(_ release: Release) async throws -> URL {
        let fileManager = FileManager.default
        let (download, response) = try await URLSession.shared.download(from: release.url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ArchiveError.failed(String(localized: "Falha ao baixar o rar da RARLAB."))
        }
        let work = fileManager.temporaryDirectory.appendingPathComponent("neorar-rar-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: work) }

        let archive = work.appendingPathComponent("rar.tar.gz")
        try fileManager.moveItem(at: download, to: archive)
        let untar = try await ProcessRunner.run(ToolLocator.tar, arguments: ["-xzf", archive.path, "-C", work.path])
        guard untar.status == 0 else { throw ArchiveError.failed(String(localized: "O pacote baixado está danificado.")) }

        let unpacked = work.appendingPathComponent("rar", isDirectory: true)
        let destination = ToolLocator.managedRarDirectory
        try? fileManager.removeItem(at: destination)
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.moveItem(at: unpacked, to: destination)

        let executable = destination.appendingPathComponent("rar")
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        _ = try? await ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/xattr"),
                                         arguments: ["-dr", "com.apple.quarantine", destination.path])
        guard await installedVersion(at: executable) != nil else {
            throw ArchiveError.failed(String(localized: "O rar foi baixado, mas não pôde ser executado."))
        }
        return executable
    }

    /// First line of `rar`'s banner, e.g. "RAR 7.23 … Trial version".
    public static func installedVersion(at url: URL) async -> String? {
        guard let result = try? await ProcessRunner.run(url, arguments: ["-iver"]) else { return nil }
        let text = (result.stdoutText + result.stderrText).trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty, text.first?.isNumber == true { return text }
        // Older builds lack -iver; fall back to the banner.
        guard let banner = try? await ProcessRunner.run(url, arguments: []) else { return nil }
        return banner.stdoutText.split(separator: "\n").first(where: { $0.hasPrefix("RAR ") })
            .map { $0.split(separator: " ").prefix(2).joined(separator: " ") }
    }

    public static var licenseFile: URL { ToolLocator.managedRarDirectory.appendingPathComponent("license.txt") }
}
