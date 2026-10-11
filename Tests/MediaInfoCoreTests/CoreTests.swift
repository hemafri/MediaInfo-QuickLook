import XCTest
@testable import MediaInfoCore

final class CoreTests: XCTestCase {
    func fixture(_ transfer: String = "arib-std-b67") throws -> MediaMetadata {
        try MediaMetadata.parse(data: Data("""
        {"streams":[{"codec_type":"video","color_transfer":"bt709","disposition":{"attached_pic":1}}, {"codec_type":"video","codec_name":"hevc","color_transfer":"\(transfer)","color_primaries":"bt2020","pix_fmt":"yuv420p10le","width":3840,"height":2160,"avg_frame_rate":"30000/1001"}],"format":{"duration":"12.5","size":"12345"}}
        """.utf8))
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
