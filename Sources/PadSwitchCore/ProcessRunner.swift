import Foundation

public struct ProcessResult: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public var stdoutTrimmed: String { stdout.trimmingCharacters(in: .whitespacesAndNewlines) }
    public var stderrTrimmed: String { stderr.trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// 外部コマンド(ssh 等)をタイムアウト付きで実行する。
public enum ProcessRunner {
    public static func run(
        _ executable: String,
        _ arguments: [String],
        stdin: Data? = nil,
        timeout: TimeInterval = 20
    ) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try runSync(executable, arguments, stdin: stdin, timeout: timeout))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func runSync(
        _ executable: String,
        _ arguments: [String],
        stdin: Data?,
        timeout: TimeInterval
    ) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let inPipe = Pipe()
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardInput = inPipe
        process.standardOutput = outPipe
        process.standardError = errPipe

        try process.run()

        final class Flag: @unchecked Sendable { var value = false }
        let timedOut = Flag()
        let watchdog = DispatchWorkItem {
            timedOut.value = true
            process.terminate()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)

        DispatchQueue.global().async {
            if let stdin {
                try? inPipe.fileHandleForWriting.write(contentsOf: stdin)
            }
            try? inPipe.fileHandleForWriting.close()
        }

        var outData = Data()
        var errData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            outData = (try? outPipe.fileHandleForReading.readToEnd()) ?? Data()
            group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
            errData = (try? errPipe.fileHandleForReading.readToEnd()) ?? Data()
            group.leave()
        }

        process.waitUntilExit()
        group.wait()
        watchdog.cancel()

        if timedOut.value {
            throw PadError.timeout("コマンドがタイムアウトしました: \((executable as NSString).lastPathComponent)")
        }
        return ProcessResult(
            exitCode: process.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? ""
        )
    }
}
