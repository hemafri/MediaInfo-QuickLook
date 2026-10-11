import Foundation
import AVFoundation

@main struct IntegrationCheck {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw NSError(domain: "IntegrationCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    static func main() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/fixtures")
        let probe = ProbeService(executableURL: URL(fileURLWithPath: ProcessInfo.processInfo.environment["FFPROBE"] ?? "/opt/homebrew/bin/ffprobe"))
        let fixtures: [(String, HDRKind, String)] = [("中文 HLG 10bit.mp4", .hlg, "10"), ("中文 PQ 10bit.mov", .pq, "10"), ("中文 SDR 8bit.mp4", .sdr, "8"), ("中文 未标记.mov", .unknown, "8")]
        var records: [MediaMetadata] = []
        for (name, kind, bits) in fixtures {
            let result = try await probe.probe(url: root.appendingPathComponent(name))
            try require(result.hdr == kind && result.bitDepth == bits, "Incorrect metadata: \(name)")
            records.append(result)
            print("PASS fixture: \(name) | \(result.hdr.title) | transfer=\(result.transfer) | depth=\(result.bitDepth) | fps=\(result.frameRate)")
        }
        let batch = root.appendingPathComponent("batch200")
        try FileManager.default.createDirectory(at: batch, withIntermediateDirectories: true)
        var urls: [URL] = []
        for index in 0..<200 {
            let source = root.appendingPathComponent(fixtures[index % fixtures.count].0)
            let target = batch.appendingPathComponent("素材 \(index).\(source.pathExtension)")
            if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
            try FileManager.default.copyItem(at: source, to: target)
            urls.append(target)
        }
        urls.append(root.appendingPathComponent("中文 损坏.mp4"))
        let start = Date()
        var successes = 0, failures = 0
        var counts: [HDRKind: Int] = [:]
        await withTaskGroup(of: HDRKind?.self) { group in
            var next = 0
            func enqueue(_ url: URL) {
                group.addTask { do { return try await probe.probe(url: url).hdr } catch { return nil } }
            }
            for _ in 0..<3 { enqueue(urls[next]); next += 1 }
            while let result = await group.next() {
                if let kind = result { successes += 1; counts[kind, default: 0] += 1 } else { failures += 1 }
                if next < urls.count { enqueue(urls[next]); next += 1 }
            }
        }
        try require(successes == 200 && failures == 1, "Batch must isolate corrupt input")
        for kind in [HDRKind.hlg, .pq, .sdr, .unknown] { try require(counts[kind] == 50, "Batch classification mismatch") }
        print(String(format: "PASS batch: 200 real file copies + 1 corrupted; 200 successful, 1 isolated failure, concurrency limit 3, %.3f seconds", Date().timeIntervalSince(start)))
        let cache = MetadataCache(), cachedURL = urls[0]
        await cache.store(records[0], for: cachedURL)
        let hit = await cache.value(for: cachedURL)
        try require(hit?.hdr == .hlg, "Cache miss")
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: 5)], ofItemAtPath: cachedURL.path)
        let miss = await cache.value(for: cachedURL)
        try require(miss == nil, "Cache failed to invalidate")
        print("PASS real fixture cache mtime invalidation")
        let cancelled = Task { try await probe.probe(url: root.appendingPathComponent(fixtures[0].0)) }
        cancelled.cancel()
        do { _ = try await cancelled.value; throw NSError(domain: "Cancellation ignored", code: 1) } catch is CancellationError {}
        print("PASS real ffprobe immediate cancellation (active stubborn-process cancellation covered by standalone checks)")
        for (name, _, _) in fixtures {
            let url = root.appendingPathComponent(name)
            let asset = AVURLAsset(url: url)
            let playable = try await asset.load(.isPlayable)
            try require(playable, "AVFoundation asset is not playable: \(name)")
            let tracks = try await asset.loadTracks(withMediaType: .video)
            try require(!tracks.isEmpty, "Missing AVFoundation video track")
            let duration = try await asset.load(.duration)
            try require(duration.seconds > 0, "Invalid playback duration")
            let item = AVPlayerItem(asset: asset)
            let player = AVPlayer(playerItem: item)
            player.isMuted = true
            player.play()
            let deadline = Date().addingTimeInterval(5)
            while item.status == .unknown && Date() < deadline { try await Task.sleep(nanoseconds: 50_000_000) }
            try require(item.status == .readyToPlay, "AVPlayerItem not ready: \(name) \(String(describing: item.error))")
            try await Task.sleep(nanoseconds: 150_000_000)
            let advanced = player.currentTime().seconds > 0
            player.pause()
            try require(advanced, "Player clock did not advance: \(name)")
            print("PASS AVFoundation: \(name), readyToPlay and playback clock advanced; no visible HDR assertion")
        }
        print("ALL SYNTHETIC INTEGRATION CHECKS PASSED")
    }
}
