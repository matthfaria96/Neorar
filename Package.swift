// swift-tools-version: 6.2
import PackageDescription

// UnRAR translation units (mirrors LIB_OBJ + OBJECTS from RARLAB's makefile).
// The remaining .cpp files in unrar/ are #included by these and must not be compiled on their own.
let unrarSources = [
    "rar", "strlist", "strfn", "pathfn", "smallfn", "global", "file", "filefn", "filcreat",
    "archive", "arcread", "unicode", "system", "crypt", "crc", "rawread", "encname",
    "resource", "match", "timefn", "rdwrfn", "consio", "options", "errhnd", "rarvm", "secpassword",
    "rijndael", "getbits", "sha1", "sha256", "blake2s", "hash", "extinfo", "extract", "volume",
    "list", "find", "unpack", "headers", "threadpool", "rs16", "cmddata", "ui", "largepage",
    "filestr", "scantree", "dll", "qopen",
].map { "unrar/\($0).cpp" }

let package = Package(
    name: "Neorar",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Neorar", targets: ["Neorar"]),
    ],
    targets: [
        .target(
            name: "CUnrar",
            path: "Sources/CUnrar",
            sources: unrarSources + ["shim.cpp"],
            publicHeadersPath: "include",
            cxxSettings: [
                .define("RARDLL"),
                .define("RAR_SMP"),
                .define("_FILE_OFFSET_BITS", to: "64"),
                .define("_LARGEFILE_SOURCE"),
                .headerSearchPath("unrar"),
                .unsafeFlags([
                    "-Wno-logical-op-parentheses", "-Wno-switch", "-Wno-dangling-else",
                    "-Wno-unused-parameter", "-Wno-deprecated-declarations", "-Wno-shorten-64-to-32", "-Wno-nontrivial-memcall",
                ]),
                .unsafeFlags(["-O3"], .when(configuration: .release)),
            ],
            linkerSettings: [.linkedLibrary("c++")]
        ),
        .target(
            name: "CLibArchive",
            linkerSettings: [.linkedLibrary("archive")]
        ),
        .target(
            name: "NeorarCore",
            dependencies: ["CUnrar", "CLibArchive"]
        ),
        .executableTarget(
            name: "Neorar",
            dependencies: ["NeorarCore"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "NeorarCoreTests",
            dependencies: ["NeorarCore"],
            resources: [.copy("Fixtures")]
        ),
    ],
    cxxLanguageStandard: .cxx17
)
