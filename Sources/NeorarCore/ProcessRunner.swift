import Foundation

public struct ProcessResult: Sendable {
    public let status: Int32
    public let stdout: Data
    public let stderr: Data
    public var stdoutText: String { String(decoding: stdout, as: UTF8.self) }
    public var stderrText: String { String(decoding: stderr, as: UTF8.self) }
}

/// Runs a command-line tool, streaming output and honoring task cancellation.
enum ProcessRunner {
    static func run(
        _ executable: URL,
        arguments: [String],
        currentDirectory: URL? = nil,
        stdin input: Data? = nil,
        environment: [String: String]? = nil,
        onOutput: (@Sendable (Data) -> Void)? = nil
    ) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let currentDirectory { process.currentDirectoryURL = currentDirectory }
        var env = ProcessInfo.processInfo.environment
        env["LC_ALL"] = "en_US.UTF-8"
        env["LANG"] = "en_US.UTF-8"
        environment?.forEach { env[$0.key] = $0.value }
        process.environment = env

        let outPipe = Pipe(), errPipe = Pipe(), inPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = inPipe

        let collector = OutputCollector()
        let group = DispatchGroup()
        for (pipe, isOut) in [(outPipe, true), (errPipe, false)] {
            group.enter()
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                    group.leave()
                    return
                }
                collector.append(chunk, toStdout: isOut)
                onOutput?(chunk)
            }
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ProcessResult, Error>) in
                process.terminationHandler = { finished in
                    group.notify(queue: .global()) {
                        let (out, err) = collector.snapshot()
                        continuation.resume(returning: ProcessResult(status: finished.terminationStatus, stdout: out, stderr: err))
                    }
                }
                do {
                    try process.run()
                } catch {
                    outPipe.fileHandleForReading.readabilityHandler = nil
                    errPipe.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(throwing: ArchiveError.toolMissing(executable.lastPathComponent))
                    return
                }
                let writer = inPipe.fileHandleForWriting
                if let input { try? writer.write(contentsOf: input) }
                try? writer.close()
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }
}

private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var out = Data()
    private var err = Data()

    func append(_ data: Data, toStdout: Bool) {
        lock.lock(); defer { lock.unlock() }
        if toStdout { out.append(data) } else { err.append(data) }
    }

    func snapshot() -> (Data, Data) {
        lock.lock(); defer { lock.unlock() }
        return (out, err)
    }
}

/// Extracts the last "NN%" token from console output that redraws itself with backspaces.
struct PercentParser: Sendable {
    static func lastPercent(in chunk: Data) -> Int? {
        let bytes = [UInt8](chunk)
        var result: Int?
        var index = 0
        while index < bytes.count {
            if bytes[index] == UInt8(ascii: "%") {
                var start = index
                while start > 0, (48...57).contains(bytes[start - 1]) { start -= 1 }
                if start < index, index - start <= 3,
                   let value = Int(String(decoding: bytes[start..<index], as: UTF8.self)), value <= 100 {
                    result = value
                }
            }
            index += 1
        }
        return result
    }
}
