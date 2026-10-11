import AppKit

@main struct ModelChecks {
    @MainActor static func main() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("refresh-regression-\(UUID().uuidString).mp4")
        try Data("not a video".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let model = AppModel()
        model.rows = [MediaRow(url: file)]
        model.refresh()
        model.cancel()
        try await Task.sleep(nanoseconds: 500_000_000)
        guard model.rows.first?.state == "已取消", !model.scanning else {
            print("FAIL: canceled refresh restarted analysis: \(model.rows.first?.state ?? "nil")")
            exit(1)
        }
        print("PASS: canceled refresh cannot restart analysis")
        func metadata(_ duration: String) throws -> MediaMetadata {
            try MediaMetadata.parse(data: Data("{\"streams\":[{\"codec_type\":\"video\",\"duration\":\"\(duration)\"}]}".utf8))
        }
        model.filter = "全部"
        let a = MediaRow(url: URL(fileURLWithPath: "/a.mp4"), metadata: try metadata("1.2"))
        let b = MediaRow(url: URL(fileURLWithPath: "/b.mp4"), metadata: try metadata("1.11"))
        model.rows = [a, b]; model.sortColumn = 10; model.sortAscending = true
        guard model.visibleRows.first?.id == b.id else { print("FAIL: decimal duration sorting must use numeric values"); exit(1) }
        print("PASS: decimal duration sorting")
        model.search = "a.mp4"
        guard model.visibleRows.count == 1 else { throw CheckFailure.failed("filename search") }
        model.search = ""; model.filter = "unknown"
        guard model.visibleRows.count == 2 else { throw CheckFailure.failed("unknown filter") }
        model.filter = "全部"
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/fixtures")
        let batch = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("batch200"), includingPropertiesForKeys: nil)
        let corrupt = root.appendingPathComponent("中文 损坏.mp4")
        model.load(batch + [corrupt, root])
        guard model.rows.count == 201 else { throw CheckFailure.failed("incremental names and folder skip") }
        var sawProgress = false
        let deadline = Date().addingTimeInterval(30)
        while model.scanning && Date() < deadline {
            if model.completed > 0 && model.completed < 201 { sawProgress = true }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        guard !model.scanning, model.completed == 201, model.rows.filter({ $0.error != nil }).count == 1, sawProgress else { throw CheckFailure.failed("201-file incremental app scan") }
        guard model.counts[.hlg] == 50, model.counts[.pq] == 50, model.counts[.sdr] == 50, model.counts[.unknown] == 50 else { throw CheckFailure.failed("HDR counts") }
        print("PASS: app model 200 files + corruption, progress, counts, folder skip")
        model.load(batch); model.cancel()
        let canceledCount = model.completed
        try await Task.sleep(nanoseconds: 200_000_000)
        guard !model.scanning, model.completed == canceledCount else { throw CheckFailure.failed("cancel race") }
        model.load(batch)
        model.load([root.appendingPathComponent("中文 PQ 10bit.mov")])
        while model.scanning { try await Task.sleep(nanoseconds: 10_000_000) }
        guard model.rows.count == 1, model.rows[0].metadata?.hdr == .pq else { throw CheckFailure.failed("stale scan overwrote selection") }
        print("PASS: cancellation and stale selection isolation")
    }
}

enum CheckFailure: Error { case failed(String) }
