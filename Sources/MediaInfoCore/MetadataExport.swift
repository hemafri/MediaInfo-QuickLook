import Foundation

public enum MetadataExport {
    public static let headers = ["文件名", "路径", "HDR 分类", "Transfer", "Primaries", "Matrix", "位深", "色度采样", "编码", "Profile", "分辨率", "帧率", "码率", "时长", "容器", "文件大小", "相机", "提示", "错误", "快门", "光圈", "ISO", "陀螺仪数据", "拍摄参数来源", "拍摄参数说明"]
    public static func cells(url: URL, metadata m: MediaMetadata?, error: String?) -> [String] {
        [url.lastPathComponent, url.path, m?.hdr.title ?? "", m?.transfer ?? "", m?.primaries ?? "", m?.matrix ?? "", m?.bitDepth ?? "", m?.chroma ?? "", m?.codec ?? "", m?.profile ?? "", m?.resolution ?? "", m?.frameRate ?? "", m?.bitRate ?? "", m?.duration ?? "", m?.container ?? "", m?.fileSize ?? "", m?.camera ?? "", m?.warning ?? "", error ?? "", m?.capture?.shutter ?? "", m?.capture?.aperture ?? "", m?.capture?.iso ?? "", m?.capture?.gyro ?? "", m?.capture?.source ?? "", m?.capture?.note ?? ""]
    }
    private static func encode(_ rows: [[String]], separator: String) -> String {
        rows.map { row in row.map { cell in
            cell.contains(separator) || cell.contains("\"") || cell.contains("\n") || cell.contains("\r") ? "\"" + cell.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : cell
        }.joined(separator: separator) }.joined(separator: "\r\n") + (rows.isEmpty ? "" : "\r\n")
    }
    public static func csv(rows: [[String]], bom: Bool = true) -> String { (bom ? "\u{FEFF}" : "") + encode(rows, separator: ",") }
    public static func tsv(rows: [[String]]) -> String { encode(rows, separator: "\t") }
}
