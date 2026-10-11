import Foundation

/// Exposure values are file tags, potentially a sample of timed metadata, not measurements.
public struct CameraCapture: Codable, Sendable {
    public var shutter = "未知"
    public var aperture = "未知"
    public var iso = "未知"
    public var gyro = "未检出（不能排除）"
    public var source = ""
    public var note = ""
    public init() {}

    private static func key(_ raw: String) -> String {
        let tag = raw.split(separator: ":").last.map(String.init) ?? raw
        return tag.lowercased().replacingOccurrences(of: "com.apple.quicktime.", with: "").filter { $0.isLetter || $0.isNumber }
    }
    private static func text(_ value: Any) -> String? {
        let result: String
        if let s = value as? String { result = s.trimmingCharacters(in: .whitespacesAndNewlines) }
        else if let n = value as? NSNumber { result = n.stringValue }
        else if let values = value as? [Any] { result = values.compactMap(text).joined(separator: " ") }
        else { return nil }
        return result.isEmpty || ["unknown", "n/a", "null", "undefined"].contains(result.lowercased()) ? nil : result
    }
    private static func positive(_ value: String) -> Double? {
        let parts = value.split(separator: "/")
        let n: Double?
        if parts.count == 2, let a = Double(parts[0]), let b = Double(parts[1]), b != 0 { n = a / b }
        else { n = Double(value) }
        guard let n, n.isFinite, n > 0 else { return nil }
        return n
    }
    private static func number(_ n: Double) -> String { String(format: "%.6g", locale: Locale(identifier: "en_US_POSIX"), n) }
    private static func exposure(_ value: String) -> String? {
        let raw = value.lowercased().replacingOccurrences(of: " sec", with: "").replacingOccurrences(of: " s", with: "")
        guard let n = positive(raw) else { return nil }
        if n < 1 {
            let reciprocal = 1 / n
            if abs(reciprocal.rounded() - reciprocal) < 0.001 { return "1/\(number(reciprocal.rounded())) s" }
        }
        return "\(number(n)) s"
    }
    private static func hasSamples(_ raw: String) -> Bool {
        // ExifTool prints a byte-count summary for binary sensor payloads by default.
        if let range = raw.range(of: #"(?i)binary data [1-9][0-9]* bytes"#, options: .regularExpression), !range.isEmpty { return true }
        let values = raw.split { $0.isWhitespace || $0 == "," || $0 == ";" || $0 == "[" || $0 == "]" }
        return values.count >= 3 && values.allSatisfy { Double($0)?.isFinite == true }
    }
    /// Only specific gyro sample tags or an explicit presence flag count as evidence.
    /// An rtmd/gpmd stream, stabilization mode, or accelerometer alone is insufficient.
    public mutating func apply(tags: [String: Any], source label: String) {
        let entries = tags.sorted { $0.key < $1.key }.compactMap { k, v -> (String, String)? in
            guard let value = Self.text(v) else { return nil }; return (Self.key(k), value)
        }
        func values(_ keys: [String], transform: (String) -> String?) -> String? {
            for key in keys {
                let found = Array(Set(entries.filter { $0.0 == key }.compactMap { transform($0.1) })).sorted()
                if !found.isEmpty { return found.count == 1 ? found[0] : "变化：" + found.prefix(5).joined(separator: " / ") + (found.count > 5 ? " …" : "") }
            }
            return nil
        }
        var found = false
        if shutter == "未知", let v = values(["exposuretime", "shutterspeed"], transform: Self.exposure) { shutter = v; found = true }
        if aperture == "未知", let v = values(["fnumber", "aperture"], transform: { raw in
            Self.positive(raw.lowercased().replacingOccurrences(of: "f/", with: "")).map { "f/" + Self.number($0) }
        }) { aperture = v; found = true }
        if iso == "未知", let v = values(["iso", "isospeedratings", "isospeed"], transform: { Self.positive($0).map(Self.number) }) { iso = v; found = true }
        let sampleKeys = ["gyroscope", "angularvelocity", "gyroypr", "gyroscopedata"]
        if entries.contains(where: { sampleKeys.contains($0.0) && Self.hasSamples($0.1) }) {
            gyro = "有（检测到陀螺仪数据）"; found = true
        } else if gyro == "未检出（不能排除）", let flag = entries.first(where: { ["hasgyro", "hasgyroscope", "gyropresent"].contains($0.0) })?.1.lowercased() {
            if ["1", "true", "yes"].contains(flag) { gyro = "有（文件标记）"; found = true }
            else if ["0", "false", "no"].contains(flag) { gyro = "无（文件标记）"; found = true }
        }
        if found { source = source.isEmpty ? label : source + "；" + label }
    }
}
