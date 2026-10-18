import Foundation
@testable import NeorarCore

enum Fixtures {
    static func url(_ name: String) -> URL {
        Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil)!
    }

    /// Copies fixtures into a fresh temporary folder so tests can extract and trash freely.
    static func sandbox(_ names: [String] = []) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("neorar-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for name in names {
            try FileManager.default.copyItem(at: url(name), to: directory.appendingPathComponent(name))
        }
        return directory
    }

    static func contents(of directory: URL) -> [String] {
        let root = directory.resolvingSymlinksInPath().path
        let enumerator = FileManager.default.enumerator(atPath: root)
        var paths: [String] = []
        while let path = enumerator?.nextObject() as? String {
            paths.append(path.precomposedStringWithCanonicalMapping)
        }
        return paths.sorted()
    }

    /// Points the 7-Zip engine at the vendored binary when running outside the app bundle.
    static func useVendored7zz() {
        let vendored = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Vendor/7zz")
        setenv("NEORAR_7ZZ", vendored.path, 1)
    }
}
