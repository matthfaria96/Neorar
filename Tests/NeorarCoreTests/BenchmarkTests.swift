import Foundation
import Testing
@testable import NeorarCore

/// Manual benchmark: NEORAR_BENCH=/path/to/archive.rar swift test -c release --filter Benchmark
@Suite("Benchmark", .enabled(if: ProcessInfo.processInfo.environment["NEORAR_BENCH"] != nil))
struct BenchmarkTests {
    @Test func extractRar() async throws {
        let archive = URL(fileURLWithPath: ProcessInfo.processInfo.environment["NEORAR_BENCH"]!)
        let out = try Fixtures.sandbox()
        let clock = ContinuousClock()
        let listStart = clock.now
        let listing = try await RarEngine().list(archive, password: nil, codePage: nil)
        let listTime = clock.now - listStart
        let start = clock.now
        try await RarEngine().extract(archive, to: out, paths: nil, password: nil, codePage: nil,
                                      totalBytes: listing.totalSize, progress: { _ in })
        let elapsed = clock.now - start
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        print("BENCH list=\(listTime) extract=\(elapsed) throughput=\(Int(Double(listing.totalSize) / seconds / 1_048_576)) MB/s")
        try? FileManager.default.removeItem(at: out)
    }
}
