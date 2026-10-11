import Foundation
import Darwin

public struct ProbeService: Sendable {
    public let executableURL: URL
    public let timeout: TimeInterval
    public init(executableURL: URL, timeout: TimeInterval = 20) { self.executableURL = executableURL; self.timeout = timeout }
    public func probe(url: URL) async throws -> MediaMetadata {
        let original = try URL(fileURLWithPath: url.path).resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let execution = ProbeExecution(executable: executableURL, input: url, timeout: timeout)
        return try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            let data = try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async { continuation.resume(with: Result { try execution.run() }) }
            }
            try Task.checkCancellation()
            let latest = try URL(fileURLWithPath: url.path).resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            guard original.fileSize == latest.fileSize, original.contentModificationDate == latest.contentModificationDate else {
                throw MetadataError.probeFailed("文件在分析期间发生变化，请重新分析。")
            }
            return try MediaMetadata.parse(data: data)
        }, onCancel: { execution.cancel() })
    }
}

/// Synchronizes launch/cancellation so cancellation cannot lose a race with Process.run().
private final class ProbeExecution: @unchecked Sendable {
    private let lock = NSLock()
    private let process = Process()
    private var cancelled = false
    private var timedOut = false
    private let timeout: TimeInterval
    init(executable: URL, input: URL, timeout: TimeInterval) {
        self.timeout = timeout
        process.executableURL = executable
        process.arguments = ["-v", "error", "-show_streams", "-show_format", "-of", "json", "-i", input.path]
        process.standardInput = FileHandle.nullDevice
    }
    func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
    }
    private func expire() {
        lock.lock(); defer { lock.unlock() }
        guard process.isRunning else { return }
        timedOut = true
        kill(process.processIdentifier, SIGKILL)
    }
    func run() throws -> Data {
        let stdout = Pipe(), stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        lock.lock()
        if cancelled { lock.unlock(); throw CancellationError() }
        do { try process.run() } catch { lock.unlock(); throw error }
        lock.unlock()
        let timer = DispatchWorkItem { [weak self] in self?.expire() }
        DispatchQueue.global().asyncAfter(deadline: .now() + max(0.01, timeout), execute: timer)
        let output = PipeReader(stdout.fileHandleForReading)
        let errors = PipeReader(stderr.fileHandleForReading)
        output.start(); errors.start()
        process.waitUntilExit() // Always reap, including cancellation and timeout.
        timer.cancel()
        let data = output.finish(), errorData = errors.finish()
        lock.lock()
        let wasCancelled = cancelled, wasTimedOut = timedOut
        lock.unlock()
        if wasCancelled { throw CancellationError() }
        if wasTimedOut { throw MetadataError.timedOut }
        guard process.terminationStatus == 0 else {
            throw MetadataError.probeFailed(String(decoding: errorData.prefix(8192), as: UTF8.self))
        }
        return data
    }
}

private final class PipeReader: @unchecked Sendable {
    let handle: FileHandle
    let done = DispatchGroup()
    private var data = Data()
    init(_ handle: FileHandle) { self.handle = handle }
    func start() {
        done.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            self.data = self.handle.readDataToEndOfFile()
            try? self.handle.close()
            self.done.leave()
        }
    }
    func finish() -> Data { done.wait(); return data }
}
