import Foundation

@main struct CameraChecks {
    static func check(_ condition: @autoclosure () -> Bool, _ description: String) {
        guard condition() else { fatalError(description) }
    }
    static func main() async throws {
        let data = Data(#"{"streams":[{"codec_type":"video","tags":{"ExposureTime":"1/50","FNumber":"2.8","ISO":"800"}}],"format":{"tags":{"ISO":"100"}}}"#.utf8)
        let metadata = try MediaMetadata.parse(data: data)
        check(metadata.capture?.shutter == "1/50 s" && metadata.capture?.aperture == "f/2.8" && metadata.capture?.iso == "800", "Exposure tags and stream precedence")
        var capture = CameraCapture()
        capture.apply(tags: ["QuickTime:handler_name": "rtmd", "Accelerometer": "1 2 3", "GyroMode": "on"], source: "test")
        check(capture.gyro == "未检出（不能排除）", "Do not infer gyro from generic telemetry or stabilization")
        capture.apply(tags: ["Gyroscope": "Off"], source: "test")
        check(capture.gyro == "未检出（不能排除）", "A mode string is not gyro sample data")
        capture.apply(tags: ["Track1:AngularVelocity": "0 0 0", "Track1:ISO": 640, "Track1:Copy1:ISO": 800, "Nikon:ExposureTime": "0.008", "Nikon:FNumber": 4], source: "ExifTool")
        check(capture.gyro == "有（检测到陀螺仪数据）", "Stationary gyro readings are still samples")
        check(capture.iso == "变化：640 / 800" && capture.shutter == "1/125 s" && capture.aperture == "f/4", "Timed changes and printed Nikon values")
        var invalid = CameraCapture()
        invalid.apply(tags: ["ExposureTime": "1/0", "FNumber": -2, "ISO": "nan", "Gyroscope": "", "HasGyro": false], source: "test")
        check(invalid.shutter == "未知" && invalid.aperture == "未知" && invalid.iso == "未知", "Invalid numeric tags must remain unknown")
        check(invalid.gyro == "无（文件标记）", "Explicit no-gyro flag distinguished from lack of evidence")
        let fields = MetadataExport.cells(url: URL(fileURLWithPath: "/test.mp4"), metadata: metadata, error: nil)
        check(fields.count == MetadataExport.headers.count && fields[19] == "1/50 s" && fields[20] == "f/2.8" && fields[21] == "800", "Exports retain camera fields")
        let decoded = try JSONDecoder().decode(MediaMetadata.self, from: JSONEncoder().encode(metadata))
        check(decoded.capture?.shutter == "1/50 s", "Camera tags survive cache encoding")
        let ffprobe = URL(fileURLWithPath: ProcessInfo.processInfo.environment["FFPROBE"] ?? "/opt/homebrew/bin/ffprobe")
        let exiftoolPath = ProcessInfo.processInfo.environment["EXIFTOOL"] ?? "/opt/homebrew/bin/exiftool"
        if FileManager.default.isExecutableFile(atPath: exiftoolPath) {
            let url = URL(fileURLWithPath: ".build/camera-tags.mp4")
            let service = ProbeService(executableURL: ffprobe, cameraExecutableURL: URL(fileURLWithPath: exiftoolPath))
            let m = try await service.probe(url: url)
            check(m.capture?.shutter == "1/125 s" && m.capture?.aperture == "f/4" && m.capture?.iso == "640", "Real ExifTool must enrich XMP tags absent from ffprobe scalar fields")
            check(m.capture?.gyro == "未检出（不能排除）", "Untagged gyro must remain undetermined")
            check(m.probeIdentity == service.cacheIdentity, "Tool identity accompanies cached metadata")
            check(service.cacheIdentity != ProbeService(executableURL: ffprobe).cacheIdentity, "Installing supplemental tool invalidates old scan context")
            let failed = try await ProbeService(executableURL: ffprobe, cameraExecutableURL: URL(fileURLWithPath: "/nonexistent/exiftool")).probe(url: url)
            check(failed.codec != "未知" && failed.capture?.note.contains("未完成") == true, "ExifTool failure must preserve basic video results")
            if let path = ProcessInfo.processInfo.environment["CAMERA_SAMPLE"] {
                let real = try await service.probe(url: URL(fileURLWithPath: path))
                print("REAL SAMPLE: \(real.camera), shutter=\(real.capture!.shutter), aperture=\(real.capture!.aperture), ISO=\(real.capture!.iso), gyro=\(real.capture!.gyro)")
            }
            print("PASS: real ExifTool enrichment, safe failure, cache context")
        } else { print("SKIP: real ExifTool integration (tool unavailable)") }
        print("PASS: exposure parsing, gyro evidence, timed variation, invalid values, export and cache encoding")
    }
}
