import Foundation
import Darwin

public struct ProbeService: Sendable {
    public let executableURL: URL
    public let timeout: TimeInterval
    public let cameraExecutableURL: URL?
    public init(executableURL: URL, timeout: TimeInterval = 20, cameraExecutableURL: URL? = nil) {
        self.executableURL = executableURL; self.timeout = timeout; self.cameraExecutableURL = cameraExecutableURL
    }
    /// Cache context changes when either configured tool is installed/replaced/changed.
    public var cacheIdentity: String {
        [executableURL, cameraExecutableURL].map { url in
            guard let url else { return "none" }
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate?.timeIntervalSince1970 ?? 0
            return "\(url.path):\(date)"
        }.joined(separator: "|")
    }
    private func execute(_ executable: URL, arguments: [String]) async throws -> Data {
        let execution = ProbeExecution(executable: executable, arguments: arguments, timeout: timeout)
        return try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            let data = try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async { continuation.resume(with: Result { try execution.run() }) }
            }
            try Task.checkCancellation()
            return data
        }, onCancel: { execution.cancel() })
    }
    public func probe(url: URL) async throws -> MediaMetadata {
        let original = try URL(fileURLWithPath: url.path).resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let data = try await execute(executableURL, arguments: ["-v", "error", "-show_streams", "-show_format", "-of", "json", "-i", url.path])
        var result = try MediaMetadata.parse(data: data)
        var capture = result.capture ?? CameraCapture()
        if let cameraExecutableURL {
            do {
                // Printed ExposureTime/FNumber values avoid interpreting raw EXIF APEX units.
                // Family 4 groups retain separate timed samples instead of silently overwriting them.
                let extra = try await execute(cameraExecutableURL, arguments: ["-j", "-G1:4", "-s", "-a", "-ee", "-ExposureTime", "-ShutterSpeed", "-FNumber", "-Aperture", "-ISO", "-Make", "-Model", "-Gyroscope", "-AngularVelocity", "-GyroYPR", "--", url.path])
                guard let records = try JSONSerialization.jsonObject(with: extra) as? [[String: Any]], let tags = records.first else { throw MetadataError.invalidJSON }
                if let error = tags["ExifTool:Error"] as? String ?? tags["Error"] as? String { throw MetadataError.probeFailed(error) }
                capture.apply(tags: tags, source: "ExifTool（含可识别的时序元数据）")
                capture.note = "拍摄参数可能随时间变化；仅显示工具识别到的值。未检出陀螺仪不等于没有私有陀螺仪数据。"
                if result.camera == "未知" {
                    let make = tags.sorted { $0.key < $1.key }.first { $0.key.split(separator: ":").last == "Make" }?.value as? String
                    let model = tags.sorted { $0.key < $1.key }.first { $0.key.split(separator: ":").last == "Model" }?.value as? String
                    let parts = [make, model].compactMap { $0 }
                    if !parts.isEmpty { result.camera = parts.joined(separator: " ") }
                }
            } catch is CancellationError { throw CancellationError() }
            catch {
                capture.note = "相机扩展元数据读取未完成：\(error.localizedDescription)；基础视频参数仍可用。"
            }
        } else {
            capture.note = "未配置 ExifTool，仅检查公开视频标签；厂商私有拍摄参数与陀螺仪可能无法识别。"
        }
        try Task.checkCancellation()
        let latest = try URL(fileURLWithPath: url.path).resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        guard original.fileSize == latest.fileSize, original.contentModificationDate == latest.contentModificationDate else {
            throw MetadataError.probeFailed("文件在分析期间发生变化，请重新分析。")
        }
        result.capture = capture
        result.probeIdentity = cacheIdentity
        return result
    }
}

/// Synchronizes launch/cancellation so cancellation cannot lose a race with Process.run().
private final class ProbeExecution: @unchecked Sendable {
    private let lock = NSLock()
    private let process = Process()
    private var cancelled = false
    private var timedOut = false
    private let timeout: TimeInterval
    init(executable: URL, arguments: [String], timeout: TimeInterval) {
        self.timeout = timeout
        process.executableURL = executable
        process.arguments = arguments
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
