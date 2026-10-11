import Foundation

public enum HDRKind: String, Codable, CaseIterable, Sendable {
    case hlg, pq, sdr, unknown, other
    public var title: String {
        switch self { case .hlg: return "HLG"; case .pq: return "PQ"; case .sdr: return "SDR（标记）"; case .unknown: return "未知"; case .other: return "其他/未知" }
    }
    public static func classify(_ transfer: String?) -> Self {
        switch transfer?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) {
        case "arib-std-b67": return .hlg
        case "smpte2084": return .pq
        case "bt709", "iec61966-2-1": return .sdr
        case nil, "", "unknown", "reserved", "unspecified": return .unknown
        default: return .other
        }
    }
}

public enum MetadataError: LocalizedError {
    case noVideo, invalidJSON, timedOut, probeFailed(String)
    public var errorDescription: String? {
        switch self {
        case .noVideo: return "文件中没有可分析的视频流。"
        case .invalidJSON: return "ffprobe 返回了无效的 JSON。"
        case .timedOut: return "分析超时。"
        case .probeFailed(let detail): return "元数据分析失败：\(detail)"
        }
    }
}

public struct MediaMetadata: Codable, Sendable {
    public var transfer, primaries, matrix, bitDepth, chroma, codec, profile, resolution, frameRate, bitRate, duration, container, fileSize, camera, warning: String
    public var rawPixelFormat: String = "未知"
    public var rawAverageFrameRate: String = "未知"
    public var rawNominalFrameRate: String = "未知"
    public var capture: CameraCapture?
    public var probeIdentity: String?
    public var hdr: HDRKind
    // Preserve original precision for cache and sorting; round only for presentation.
    public var bitRateValue: Double? { Self.quantity(bitRate) }
    public var durationValue: Double? { Self.quantity(duration) }
    public var displayBitRate: String { Self.scaled(bitRateValue, units: ["bps", "kbps", "Mbps", "Gbps", "Tbps"]) }
    public var displayDuration: String {
        durationValue.map { String(format: "%.1f s", locale: Locale(identifier: "en_US_POSIX"), $0) } ?? "未知"
    }
    public var displayFileSize: String { Self.scaled(Self.quantity(fileSize), units: ["B", "KB", "MB", "GB", "TB", "PB"]) }
    private static func quantity(_ text: String) -> Double? {
        guard let first = text.split(separator: " ").first, let value = Double(first), value.isFinite, value >= 0 else { return nil }
        return value
    }
    private static func scaled(_ value: Double?, units: [String]) -> String {
        guard var value else { return "未知" }
        var index = 0
        while value >= 999.95 && index < units.count - 1 { value /= 1_000; index += 1 }
        var number = String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), value)
        if number.hasSuffix(".0") { number.removeLast(2) }
        return "\(number) \(units[index])"
    }
    public static func parse(data: Data) throws -> Self {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw MetadataError.invalidJSON }
        let streams = root["streams"] as? [[String: Any]] ?? []
        let candidates = streams.filter { stream in
            (stream["codec_type"] as? String) == "video" && ((stream["disposition"] as? [String: Any])?["attached_pic"] as? NSNumber)?.intValue != 1
        }
        guard let video = candidates.first(where: { (($0["disposition"] as? [String: Any])?["default"] as? NSNumber)?.intValue == 1 }) ?? candidates.first else { throw MetadataError.noVideo }
        let format = root["format"] as? [String: Any] ?? [:]
        func raw(_ dict: [String: Any], _ key: String) -> String? {
            if let value = dict[key] as? String, !value.isEmpty, value != "N/A" { return value }
            if let value = dict[key] as? NSNumber { return value.stringValue }
            return nil
        }
        func v(_ key: String) -> String { raw(video, key) ?? "未知" }
        let transfer = v("color_transfer"), primaries = v("color_primaries"), hdr = HDRKind.classify(raw(video, "color_transfer"))
        let pixel = raw(video, "pix_fmt") ?? ""
        let depth: String
        if let bits = raw(video, "bits_per_raw_sample"), let n = Int(bits), n > 0 { depth = bits }
        else if ["p010le", "p010be"].contains(pixel) { depth = "10" }
        else if let match = pixel.range(of: #"(?:p|gray|gbrp)(9|10|12|14|16)(?:le|be)?$"#, options: .regularExpression) {
            depth = pixel[match].filter(\.isNumber)
        } else if ["yuv420p", "yuv422p", "yuv444p", "yuvj420p", "yuvj422p", "yuvj444p", "nv12", "nv21", "rgb24", "bgr24", "gray"].contains(pixel) { depth = "8" }
        else { depth = "未知" }
        let chroma = pixel.contains("420") || ["nv12", "nv21", "p010le", "p010be"].contains(pixel) ? "4:2:0" : pixel.contains("422") ? "4:2:2" : pixel.contains("444") ? "4:4:4" : "未知"
        let width = raw(video, "width"), height = raw(video, "height")
        func rate(_ value: String?) -> Double? {
            guard let value else { return nil }
            let parts = value.split(separator: "/")
            if parts.count == 2, let a = Double(parts[0]), let b = Double(parts[1]), b != 0, a / b > 0 { return a / b }
            if let n = Double(value), n > 0, n.isFinite { return n }
            return nil
        }
        let fps = rate(raw(video, "avg_frame_rate"))
        let tags = (format["tags"] as? [String: Any] ?? [:]).merging(video["tags"] as? [String: Any] ?? [:]) { _, new in new }
        let makeKeys = ["make", "manufacturer", "com.apple.quicktime.make"]
        let modelKeys = ["model", "com.apple.quicktime.model"]
        let normalized = Dictionary(tags.map { ($0.key.lowercased(), String(describing: $0.value)) }, uniquingKeysWith: { a, _ in a })
        let cameraParts = [makeKeys.compactMap { normalized[$0] }.first, modelKeys.compactMap { normalized[$0] }.first].compactMap { $0 }
        var result = Self(transfer: transfer, primaries: primaries, matrix: v("color_space"), bitDepth: depth, chroma: chroma, codec: v("codec_name"), profile: v("profile"), resolution: width != nil && height != nil ? "\(width!) × \(height!)" : "未知", frameRate: fps.map { String(format: "%.3f fps", locale: Locale(identifier: "en_US_POSIX"), $0) } ?? "未知", bitRate: (raw(video, "bit_rate") ?? raw(format, "bit_rate")).map { "\($0) bit/s" } ?? "未知", duration: (raw(video, "duration") ?? raw(format, "duration")).map { "\($0) s" } ?? "未知", container: raw(format, "format_name") ?? "未知", fileSize: raw(format, "size").map { "\($0) bytes" } ?? "未知", camera: cameraParts.isEmpty ? "未知" : cameraParts.joined(separator: " "), warning: [.hlg, .pq].contains(hdr) && primaries != "bt2020" ? "标签需核实：HDR transfer 与缺失或非常规 primaries。" : "", hdr: hdr)
        var capture = CameraCapture()
        capture.apply(tags: video["tags"] as? [String: Any] ?? [:], source: "ffprobe 视频流")
        capture.apply(tags: format["tags"] as? [String: Any] ?? [:], source: "ffprobe 容器")
        result.capture = capture
        result.rawPixelFormat = v("pix_fmt")
        result.rawAverageFrameRate = v("avg_frame_rate")
        result.rawNominalFrameRate = v("r_frame_rate")
        return result
    }
}
