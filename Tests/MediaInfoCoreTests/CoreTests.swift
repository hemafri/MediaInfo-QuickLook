import XCTest
@testable import MediaInfoCore

final class CoreTests: XCTestCase {
    func fixture(_ transfer: String = "arib-std-b67") throws -> MediaMetadata {
        try MediaMetadata.parse(data: Data("""
        {"streams":[{"codec_type":"video","color_transfer":"bt709","disposition":{"attached_pic":1}}, {"codec_type":"video","codec_name":"hevc","color_transfer":"\(transfer)","color_primaries":"bt2020","pix_fmt":"yuv420p10le","width":3840,"height":2160,"avg_frame_rate":"30000/1001"}],"format":{"duration":"12.5","size":"12345"}}
        """.utf8))
    }
    func testCameraTagsAndGyroEvidence() throws {
        let m = try MediaMetadata.parse(data: Data(#"{"streams":[{"codec_type":"video","tags":{"ExposureTime":"1/50","FNumber":"2.8","ISO":"800"}}],"format":{"tags":{"ISO":"100"}}}"#.utf8))
        XCTAssertEqual(m.capture?.shutter, "1/50 s")
        XCTAssertEqual(m.capture?.aperture, "f/2.8")
        XCTAssertEqual(m.capture?.iso, "800")
        XCTAssertEqual(m.capture?.gyro, "未检出（不能排除）")
        var capture = CameraCapture()
        capture.apply(tags: ["handler_name": "rtmd", "Accelerometer": "1 2 3", "GyroMode": "On", "Gyroscope": "Off"], source: "test")
        XCTAssertEqual(capture.gyro, "未检出（不能排除）")
        capture.apply(tags: ["QuickTime:AngularVelocity": "0 0 0"], source: "ExifTool")
        XCTAssertEqual(capture.gyro, "有（检测到陀螺仪数据）")
    }
    func testCameraTimedChangesAndInvalidFields() {
        var capture = CameraCapture()
        capture.apply(tags: ["Track1:ExposureTime": "0.008", "Track1:FNumber": "f/4", "Track1:ISO": 640, "Track1:Copy1:ISO": 800], source: "ExifTool")
        XCTAssertEqual(capture.shutter, "1/125 s")
        XCTAssertEqual(capture.aperture, "f/4")
        XCTAssertEqual(capture.iso, "变化：640 / 800")
        var invalid = CameraCapture()
        invalid.apply(tags: ["ExposureTime": "1/0", "FNumber": -2, "ISO": "nan", "Gyroscope": "", "HasGyro": false], source: "test")
        XCTAssertEqual(invalid.shutter, "未知")
        XCTAssertEqual(invalid.aperture, "未知")
        XCTAssertEqual(invalid.iso, "未知")
        XCTAssertEqual(invalid.gyro, "无（文件标记）")
    }
    func testReadableMediaQuantitiesInExport() throws {
        let m = try MediaMetadata.parse(data: Data(#"{"streams":[{"codec_type":"video","bit_rate":"23333130","duration":"1.001"}],"format":{"size":"5305014"}}"#.utf8))
        let cells = MetadataExport.cells(url: URL(fileURLWithPath: "/sample.mov"), metadata: m, error: nil)
        XCTAssertEqual(cells[12], "23.3 Mbps")
        XCTAssertEqual(cells[13], "1.0 s")
        XCTAssertEqual(cells[15], "5.3 MB")
        XCTAssertEqual(cells.count, MetadataExport.headers.count)
        var values = m
        values.bitRate = "999999 bit/s"; values.fileSize = "0 bytes"; values.duration = "12.56 s"
        XCTAssertEqual(values.displayBitRate, "1 Mbps")
        XCTAssertEqual(values.displayFileSize, "0 B")
        XCTAssertEqual(values.displayDuration, "12.6 s")
        values.bitRate = "nan bit/s"; values.fileSize = "-1 bytes"; values.duration = "未知"
        XCTAssertEqual(values.displayBitRate, "未知")
        XCTAssertEqual(values.displayFileSize, "未知")
        XCTAssertEqual(values.displayDuration, "未知")
    }
    func testClassificationUsesOnlyKnownTransferTags() {
        XCTAssertEqual(HDRKind.classify("arib-std-b67"), .hlg)
        XCTAssertEqual(HDRKind.classify("smpte2084"), .pq)
        XCTAssertEqual(HDRKind.classify("bt709"), .sdr)
        XCTAssertEqual(HDRKind.classify("iec61966-2-1"), .sdr)
        for value in [nil, "", "unknown", "reserved"] { XCTAssertEqual(HDRKind.classify(value), .unknown) }
        XCTAssertEqual(HDRKind.classify("log100"), .other)
    }
    func testMainVideoExcludesCoverAndParsesRationalRate() throws {
        let m = try fixture()
        XCTAssertEqual(m.hdr, .hlg)
        XCTAssertEqual(m.bitDepth, "10")
        XCTAssertEqual(m.chroma, "4:2:0")
        XCTAssertEqual(m.frameRate, "29.970 fps")
        XCTAssertEqual(m.resolution, "3840 × 2160")
    }
    func testMissingTransferIsNotInferredFromTenBitBT2020() throws {
        let m = try MediaMetadata.parse(data: Data(#"{"streams":[{"codec_type":"video","pix_fmt":"yuv420p10le","color_primaries":"bt2020"}]}"#.utf8))
        XCTAssertEqual(m.hdr, .unknown)
    }
    func testP010BitDepth() throws {
        let m = try MediaMetadata.parse(data: Data(#"{"streams":[{"codec_type":"video","pix_fmt":"p010le"}]}"#.utf8))
        XCTAssertEqual(m.bitDepth, "10")
    }
    func testNoVideoThrows() { XCTAssertThrowsError(try MediaMetadata.parse(data: Data(#"{"streams":[{"codec_type":"audio"}]}"#.utf8))) }
    func testCSVAndTSVEscapeCells() {
        XCTAssertEqual(MetadataExport.csv(rows: [["a,b", "c\"d", "中文\nx"]], bom: false), "\"a,b\",\"c\"\"d\",\"中文\nx\"\r\n")
        XCTAssertEqual(MetadataExport.tsv(rows: [["a\tb", "x\ny"]]), "\"a\tb\"\t\"x\ny\"\r\n")
    }
    func testCacheInvalidatesChangedFileAndPersists() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("a".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let cache = MetadataCache()
        await cache.store(try fixture(), for: url)
        let cached = await cache.value(for: url)
        XCTAssertEqual(cached?.hdr, .hlg)
        let reloaded = await MetadataCache().value(for: url)
        XCTAssertEqual(reloaded?.hdr, .hlg)
        try Data("changed".utf8).write(to: url)
        let invalid = await cache.value(for: url)
        XCTAssertNil(invalid)
    }
    func testProbeTimeoutAndCancellationReapStubbornProcess() async throws {
        let script = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("#!/bin/sh\ntrap '' TERM\nwhile :; do :; done\n".utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        defer { try? FileManager.default.removeItem(at: script) }
        let start = Date()
        do { _ = try await ProbeService(executableURL: script, timeout: 0.15).probe(url: script); XCTFail("Must time out") } catch {}
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
        let task = Task { try await ProbeService(executableURL: script).probe(url: script) }
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        do { _ = try await task.value; XCTFail("Must cancel") } catch is CancellationError {} catch { XCTFail("Wrong error: \(error)") }
    }
}
