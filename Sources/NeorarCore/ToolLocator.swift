import Foundation

/// Finds the external tools Neorar drives: the bundled 7zz, RARLAB's rar and (optionally) unar/lsar.
public enum ToolLocator {
    public static let customRarPathKey = "rarToolPath"

    public static var applicationSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Neorar", isDirectory: true)
    }

    /// Where Neorar installs RARLAB's rar when the user asks it to.
    public static var managedRarDirectory: URL { applicationSupport.appendingPathComponent("RAR", isDirectory: true) }

    public static var sevenZip: URL? {
        if let bundled = Bundle.main.url(forAuxiliaryExecutable: "7zz"), isExecutable(bundled) { return bundled }
        if let env = ProcessInfo.processInfo.environment["NEORAR_7ZZ"], isExecutable(URL(fileURLWithPath: env)) {
            return URL(fileURLWithPath: env)
        }
        return firstExecutable(["/opt/homebrew/bin/7zz", "/usr/local/bin/7zz", "/opt/homebrew/bin/7z", "/usr/local/bin/7z"])
    }

    public static var rar: URL? {
        if let custom = UserDefaults.standard.string(forKey: customRarPathKey), !custom.isEmpty,
           isExecutable(URL(fileURLWithPath: custom)) {
            return URL(fileURLWithPath: custom)
        }
        if let env = ProcessInfo.processInfo.environment["NEORAR_RAR"], isExecutable(URL(fileURLWithPath: env)) {
            return URL(fileURLWithPath: env)
        }
        return firstExecutable([
            managedRarDirectory.appendingPathComponent("rar").path,
            "/opt/homebrew/bin/rar", "/usr/local/bin/rar",
        ])
    }

    public static var unar: URL? { firstExecutable(["/opt/homebrew/bin/unar", "/usr/local/bin/unar"]) }
    public static var lsar: URL? { firstExecutable(["/opt/homebrew/bin/lsar", "/usr/local/bin/lsar"]) }
    static let tar = URL(fileURLWithPath: "/usr/bin/tar")

    static func isExecutable(_ url: URL) -> Bool {
        FileManager.default.isExecutableFile(atPath: url.path)
    }

    private static func firstExecutable(_ paths: [String]) -> URL? {
        paths.lazy.map { URL(fileURLWithPath: $0) }.first(where: isExecutable)
    }
}
