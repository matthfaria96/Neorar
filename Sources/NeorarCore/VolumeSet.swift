import Foundation

/// Groups split archives (`.part1.rar`, `.r00`, `.7z.001`, `.z01`…) and finds the volume to open.
public struct VolumeSet: Hashable, Sendable {
    public let first: URL
    public let members: [URL]

    public static func resolve(_ url: URL) -> VolumeSet {
        let directory = url.deletingLastPathComponent()
        let name = url.lastPathComponent
        let siblings = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []

        func set(first: String, matching pattern: NSRegularExpression) -> VolumeSet {
            let members = siblings
                .filter { pattern.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) != nil }
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
                .map { directory.appendingPathComponent($0) }
            let firstURL = directory.appendingPathComponent(first)
            return VolumeSet(first: firstURL, members: members.isEmpty ? [url] : members)
        }

        // name.part01.rar
        if let match = name.firstMatch(of: /^(.*)\.part(\d+)\.rar$/.ignoresCase()) {
            let base = String(match.1)
            let digits = match.2.count
            let pattern = regex("^\(NSRegularExpression.escapedPattern(for: base))\\.part\\d+\\.rar$")
            let candidates = (1...digits).map { "\(base).part\(String(repeating: "0", count: $0 - 1))1.rar" }
            let first = candidates.first { siblings.contains($0) } ?? "\(base).part\(String(repeating: "0", count: digits - 1))1.rar"
            return set(first: first, matching: pattern)
        }
        // name.rar + name.r00, name.r01…
        if let match = name.firstMatch(of: /^(.*)\.(rar|r\d{2,3})$/.ignoresCase()) {
            let base = String(match.1)
            let hasOldStyle = siblings.contains { $0.lowercased().hasPrefix(base.lowercased() + ".r0") }
            if hasOldStyle || match.2.lowercased() != "rar" {
                let pattern = regex("^\(NSRegularExpression.escapedPattern(for: base))\\.(rar|r\\d{2,3})$")
                let first = siblings.first { $0.caseInsensitiveCompare(base + ".rar") == .orderedSame } ?? base + ".rar"
                return set(first: first, matching: pattern)
            }
        }
        // name.7z.001, name.zip.001, name.001
        if let match = name.firstMatch(of: /^(.*)\.(\d{3})$/.ignoresCase()) {
            let base = String(match.1)
            let pattern = regex("^\(NSRegularExpression.escapedPattern(for: base))\\.\\d{3}$")
            return set(first: "\(base).001", matching: pattern)
        }
        // name.zip + name.z01…
        if let match = name.firstMatch(of: /^(.*)\.(zip|z\d{2})$/.ignoresCase()) {
            let base = String(match.1)
            let hasParts = siblings.contains { $0.lowercased().hasPrefix(base.lowercased() + ".z0") }
            if hasParts {
                let pattern = regex("^\(NSRegularExpression.escapedPattern(for: base))\\.(zip|z\\d{2})$")
                let first = siblings.first { $0.caseInsensitiveCompare(base + ".zip") == .orderedSame } ?? base + ".zip"
                return set(first: first, matching: pattern)
            }
        }
        return VolumeSet(first: url, members: [url])
    }

    /// Collapses a drop of many files into one entry per archive set.
    public static func group(_ urls: [URL]) -> [VolumeSet] {
        var seen = Set<URL>()
        var result: [VolumeSet] = []
        for url in urls {
            let volumeSet = resolve(url)
            if seen.insert(volumeSet.first.standardizedFileURL).inserted { result.append(volumeSet) }
        }
        return result
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // Patterns are built from escaped literals, so compilation cannot fail.
        try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }
}
