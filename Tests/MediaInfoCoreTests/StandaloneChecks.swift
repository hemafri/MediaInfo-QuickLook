#if CORE_STANDALONE_CHECKS
import Foundation

@main struct StandaloneChecks {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fatalError(message) }
    }
    static func main() async throws {
        require(HDRKind.classify(nil) == .unknown, "Missing transfer")
        require(HDRKind.classify("unknown") == .unknown, "Unknown transfer")
        require(HDRKind.classify("reserved") == .unknown, "Reserved transfer")
        require(HDRKind.classify("log100") == .other, "Log must remain other")
        require(HDRKind.classify("bt709") == .sdr, "SDR")
        require(HDRKind.classify("iec61966-2-1") == .sdr, "sRGB")
        require(HDRKind.classify("smpte2084") == .pq, "PQ")
        let m = try MediaMetadata.parse(data: Data(#"{"streams":[{"codec_type":"video","color_transfer":"bt709","disposition":{"attached_pic":1}},{"codec_type":"video","color_transfer":"arib-std-b67","pix_fmt":"yuv420p10le","avg_frame_rate":"30000/1001","width":3840,"height":2160}]}"#.utf8))
        require(m.hdr == .hlg && m.bitDepth == "10" && m.chroma == "4:2:0" && m.frameRate == "29.970 fps", "Stream parsing")
        let p010 = try MediaMetadata.parse(data: Data(#"{"streams":[{"codec_type":"video","pix_fmt":"p010le"}]}"#.utf8))
        require(p010.bitDepth == "10", "p010 is 10-bit")
        let unknown = try MediaMetadata.parse(data: Data(#"{"streams":[{"codec_type":"video","color_primaries":"bt2020","pix_fmt":"yuv420p10le"}]}"#.utf8))
        require(unknown.hdr == .unknown, "Do not infer HDR")
        do { _ = try MediaMetadata.parse(data: Data(#"{"streams":[{"codec_type":"audio"}]}"#.utf8)); fatalError("Expected noVideo") } catch MetadataError.noVideo {}
        require(MetadataExport.csv(rows: [["a,b", "c\"d", "中文\nx"]], bom: false) == "\"a,b\",\"c\"\"d\",\"中文\nx\"\r\n", "CSV escaping")
        require(MetadataExport.tsv(rows: [["a\tb", "x\ny"]]) == "\"a\tb\"\t\"x\ny\"\r\n", "TSV escaping")
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("中文 ' \" ; $(touch nope) " + UUID().uuidString)
        try Data("a".utf8).write(to: path)
        defer { try? FileManager.default.removeItem(at: path) }
        let cache = MetadataCache()
        await cache.store(m, for: path)
        let hit = await cache.value(for: path)
        require(hit?.hdr == .hlg, "Cache hit")
        let disk = await MetadataCache().value(for: path)
        require(disk?.hdr == .hlg, "Cache persistence")
        try Data("changed".utf8).write(to: path)
        let invalid = await cache.value(for: path)
        require(invalid == nil, "Cache size invalidation")
        await cache.store(m, for: path)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: 10)], ofItemAtPath: path.path)
        let modified = await cache.value(for: path)
        require(modified == nil, "Cache mtime invalidation")
        let ticket = await cache.begin(for: path)
        await cache.clear()
        await cache.store(m, for: path, ticket: ticket)
        let cleared = await cache.value(for: path)
        require(cleared == nil, "Clear must reject old cache tickets")
        let changedTicket = await cache.begin(for: path)
        try Data("second change".utf8).write(to: path)
        await cache.store(m, for: path, ticket: changedTicket)
        let stale = await cache.value(for: path)
        require(stale == nil, "Mutation must reject old cache tickets")
        let script = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: script) }
        try Data("#!/bin/sh\ntrap '' TERM\nwhile :; do :; done\n".utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        let start = Date()
        do { _ = try await ProbeService(executableURL: script, timeout: 0.15).probe(url: path); fatalError("Expected timeout") } catch MetadataError.timedOut {}
        require(Date().timeIntervalSince(start) < 3, "Timeout did not reap promptly")
        let task = Task { try await ProbeService(executableURL: script).probe(url: path) }
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        do { _ = try await task.value; fatalError("Expected cancellation") } catch is CancellationError {}
        try Data("#!/bin/sh\n/usr/bin/awk 'BEGIN { for (i=0;i<100000;i++) print \"error line\" }' >&2\nprintf '%s' '{\"streams\":[{\"codec_type\":\"video\",\"color_transfer\":\"smpte2084\"}]}'\n".utf8).write(to: script)
        let probe = try await ProbeService(executableURL: script).probe(url: path)
        require(probe.hdr == .pq, "Large stderr deadlocked")
        try Data("#!/bin/sh\nprintf 'changed' >> \"$8\"\nprintf '%s' '{\"streams\":[{\"codec_type\":\"video\"}]}'\n".utf8).write(to: script)
        do { _ = try await ProbeService(executableURL: script).probe(url: path); fatalError("Must reject file changed during analysis") } catch MetadataError.probeFailed {}
        print("PASS: classifications, JSON main video, unknown, rational rate, CSV/TSV, cache persistence/size/mtime, process timeout/cancellation/large stderr")
    }
}
#endif
