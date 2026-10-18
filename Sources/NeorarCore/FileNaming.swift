import Foundation

public enum FileNaming {
    private static let compoundSuffixes = [".tar.gz", ".tar.bz2", ".tar.xz", ".tar.zst", ".tar.lz", ".tar.z"]
    private static let archiveExtensions: Set<String> = [
        "rar", "zip", "7z", "tar", "gz", "tgz", "bz2", "tbz", "tbz2", "xz", "txz", "zst", "lzma", "z", "taz",
        "cab", "iso", "xar", "cpio", "cpgz", "pax", "jar", "cbz", "cbr", "cb7", "zipx", "sit", "sitx", "lzh",
        "lha", "arj", "ace", "dmg", "wim", "rpm", "deb", "exe", "msi", "001",
    ]

    private static let browsableExtensions: Set<String> = archiveExtensions.subtracting(["exe", "dmg", "msi", "001"])

    /// Whether a file looks like an archive Neorar can open, judged by its name only (cheap enough for listings).
    public static func isArchive(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if browsableExtensions.contains(ext) || ext == "001" { return true }
        return ext.firstMatch(of: /^r\d{2,3}$|^z\d{2}$/) != nil
    }

    /// "Fotos.part01.rar" → "Fotos", "backup.tar.gz" → "backup", "a.7z.001" → "a".
    public static func baseName(of archive: URL) -> String {
        let name = archive.lastPathComponent
        let lower = name.lowercased()
        if let match = name.firstMatch(of: /^(.+)\.part\d+\.rar$/.ignoresCase()) {
            return String(match.1)
        }
        for suffix in compoundSuffixes where lower.hasSuffix(suffix) {
            return String(name.dropLast(suffix.count))
        }
        var trimmed = name
        for _ in 0..<2 {
            let ext = (trimmed as NSString).pathExtension.lowercased()
            guard !ext.isEmpty, archiveExtensions.contains(ext) || ext.firstMatch(of: /^r\d{2,3}$|^z\d{2}$/) != nil else { break }
            trimmed = (trimmed as NSString).deletingPathExtension
        }
        return trimmed.isEmpty ? name : trimmed
    }

    /// Returns `directory/name`, or `directory/name 2`, `name 3`… when it is taken.
    public static func uniqueURL(in directory: URL, name: String, isDirectory: Bool) -> URL {
        let fileManager = FileManager.default
        let candidate = directory.appendingPathComponent(name, isDirectory: isDirectory)
        if !fileManager.fileExists(atPath: candidate.path) { return candidate }
        let stem: String, ext: String
        if isDirectory {
            (stem, ext) = (name, "")
        } else {
            stem = (name as NSString).deletingPathExtension
            ext = (name as NSString).pathExtension
        }
        var counter = 2
        while true {
            let next = ext.isEmpty ? "\(stem) \(counter)" : "\(stem) \(counter).\(ext)"
            let url = directory.appendingPathComponent(next, isDirectory: isDirectory)
            if !fileManager.fileExists(atPath: url.path) { return url }
            counter += 1
        }
    }

    /// Strips characters that cannot appear in a file name.
    public static func sanitize(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutDots = cleaned.drop(while: { $0 == "." })
        return withoutDots.isEmpty ? String(localized: "sem nome") : String(withoutDots)
    }
}
