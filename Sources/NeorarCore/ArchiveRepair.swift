import Foundation

/// Repairs damaged archives into a new file next to the original ("Nome (reparado).ext"); the original is kept.
/// RAR uses RARLAB's `rar r` (best with a recovery record); ZIP uses the system `zip -FF`.
public enum ArchiveRepair {
    public enum Method: Sendable { case rar, zip }

    static let zipTool = URL(fileURLWithPath: "/usr/bin/zip")

    public static func method(for archive: URL) -> Result<Method, ArchiveError> {
        switch ArchiveFormat.sniff(VolumeSet.resolve(archive).first) {
        case .rar:
            return ToolLocator.rar != nil ? .success(.rar)
                : .failure(.failed(String(localized: "Reparar RAR exige o rar oficial da RARLAB. Ative-o em Ajustes › RAR.")))
        case .zip:
            return .success(.zip)
        case let format:
            let name = format == .other ? String(localized: "este formato") : String(localized: "arquivos \(format.displayName)")
            return .failure(.failed(String(localized: "Não há reparo para \(name). Use Extrair: o Neorar recupera tudo o que ainda estiver legível.")))
        }
    }

    /// Returns the repaired archive.
    public static func repair(_ archive: URL) async throws -> URL {
        let source = VolumeSet.resolve(archive).first
        let directory = source.deletingLastPathComponent()
        let base = FileNaming.baseName(of: source)
        let ext = ArchiveFormat.sniff(source) == .rar ? "rar" : "zip"
        let target = FileNaming.uniqueURL(in: directory, name: base + " " + String(localized: "(reparado)") + ".\(ext)", isDirectory: false)

        switch try method(for: archive).get() {
        case .rar:
            guard let rar = ToolLocator.rar else { throw ArchiveError.toolMissing("rar") }
            let started = Date()
            let result = try await ProcessRunner.run(rar, arguments: ["r", "-y", "-idc", "--", source.lastPathComponent],
                                                     currentDirectory: directory)
            // rar writes "fixed.<name>" (or "rebuilt.<name>" without a recovery record) in the working folder.
            let produced = ["fixed.", "rebuilt."].map { directory.appendingPathComponent($0 + source.lastPathComponent) }
                .first { url in
                    let date = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? nil
                    return (date ?? .distantPast) >= started.addingTimeInterval(-2)
                }
            guard let produced, result.status <= 1 || FileManager.default.fileExists(atPath: produced.path) else {
                throw ArchiveError.failed(String(localized: "O rar não conseguiu reparar o arquivo (código \(result.status))."))
            }
            try FileManager.default.moveItem(at: produced, to: target)

        case .zip:
            // -FF scans for every local header; "y" answers "is this a single-disk archive?".
            let result = try await ProcessRunner.run(zipTool, arguments: ["-FF", source.path, "--out", target.path],
                                                     currentDirectory: directory, stdin: Data("y\n".utf8))
            guard FileManager.default.fileExists(atPath: target.path) else {
                let line = (result.stderrText + result.stdoutText).split(separator: "\n").last.map(String.init)
                throw ArchiveError.failed(String(localized: "Não foi possível reparar o ZIP") + (line.map { ": \($0)" } ?? "."))
            }
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: target.path)
        return target
    }
}
