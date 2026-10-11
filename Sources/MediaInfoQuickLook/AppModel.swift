import AppKit
import Combine
#if canImport(MediaInfoCore)
import MediaInfoCore
#endif

struct MediaRow: Identifiable {
    let id = UUID()
    let url: URL
    var metadata: MediaMetadata?
    var error: String?
    var state = "等待分析"
}

@MainActor final class AppModel: ObservableObject {
    @Published var rows: [MediaRow] = []
    @Published var selectedIDs: Set<UUID> = []
    @Published var previewID: UUID?
    @Published var search = ""
    @Published var filter = UserDefaults.standard.string(forKey: "hdrFilter") ?? "全部" {
        didSet { UserDefaults.standard.set(filter, forKey: "hdrFilter") }
    }
    @Published var minorityOnly = false
    @Published var scanning = false
    @Published var completed = 0
    @Published var message = "打开或拖入 MP4 / MOV；根据视频文件标记识别。"
    @Published var sortColumn = UserDefaults.standard.integer(forKey: "sortColumn")
    @Published var sortAscending = UserDefaults.standard.object(forKey: "sortAscending") as? Bool ?? true
    private var scanTask: Task<Void, Never>?
    private var intakeTask: Task<Void, Never>?
    private var generation = UUID()
    private let cache = MetadataCache()
    var preview: MediaRow? { rows.first { $0.id == previewID } }
    var counts: [HDRKind: Int] { Dictionary(grouping: rows.compactMap(\.metadata), by: \.hdr).mapValues(\.count) }
    var majority: HDRKind? { counts.sorted { $0.value == $1.value ? $0.key.rawValue < $1.key.rawValue : $0.value > $1.value }.first?.key }
    var visibleRows: [MediaRow] {
        let matching = rows.filter { row in
            (search.isEmpty || row.url.lastPathComponent.localizedCaseInsensitiveContains(search)) &&
            (filter == "全部" || row.metadata?.hdr.rawValue == filter || (filter == "unknown" && row.metadata?.hdr == .other)) &&
            (!minorityOnly || (row.metadata != nil && row.metadata?.hdr != majority))
        }
        return matching.sorted { a, b in
            let ac = cells(a), bc = cells(b)
            let index = min(max(sortColumn, 0), ac.count - 1)
            let comparison: ComparisonResult
            if [4, 8, 9, 10].contains(index) {
                let av = Double(ac[index].split(separator: " ").first.map(String.init) ?? "")
                let bv = Double(bc[index].split(separator: " ").first.map(String.init) ?? "")
                if av == nil && bv != nil { return false }
                if av != nil && bv == nil { return true }
                if let av, let bv { comparison = av == bv ? .orderedSame : (av < bv ? .orderedAscending : .orderedDescending) }
                else { comparison = .orderedSame }
            } else { comparison = ac[index].compare(bc[index], options: [.numeric, .caseInsensitive]) }
            if comparison == .orderedSame { return a.url.path < b.url.path }
            return sortAscending ? comparison == .orderedAscending : comparison == .orderedDescending
        }
    }
    func cells(_ row: MediaRow) -> [String] {
        let m = row.metadata
        return [row.url.lastPathComponent, m?.hdr.title ?? row.state, m?.transfer ?? "—", m?.primaries ?? "—", m?.bitDepth ?? "—", m?.chroma ?? "—", m?.codec ?? "—", m?.resolution ?? "—", m?.frameRate ?? "—", m?.bitRate ?? "—", m?.duration ?? "—", row.error ?? m?.warning ?? ""]
    }
    func openPanel() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        panel.title = "选择视频（MP4 / MOV）"
        if panel.runModal() == .OK { load(panel.urls) }
    }
    func finder() {
        do { load(try FinderSelection.selectedURLs()) }
        catch {
            cancel(); rows = []; selectedIDs = []; previewID = nil; completed = 0
            message = error.localizedDescription
        }
    }
    func load(_ urls: [URL]) {
        cancel(); rows = []; selectedIDs = []; previewID = nil; completed = 0
        var skipped: [String: Int] = [:]; var seen = Set<URL>()
        for url in urls {
            let u = url.standardizedFileURL
            guard seen.insert(u).inserted else { continue }
            guard u.isFileURL, (try? u.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { skipped["非普通文件或无法访问", default: 0] += 1; continue }
            guard ["mp4", "mov", "m4v"].contains(u.pathExtension.lowercased()) else { skipped["不支持的扩展名", default: 0] += 1; continue }
            rows.append(MediaRow(url: u))
        }
        message = skipped.isEmpty ? "根据视频文件标记识别；不代表实际拍摄曲线。" : "已跳过 " + skipped.sorted(by: { $0.key < $1.key }).map { "\($0.value) 个\($0.key)" }.joined(separator: "；")
        if rows.isEmpty { message += " 没有可分析的视频。"; return }
        if rows.count == 1 { previewID = rows[0].id }
        startScan()
    }
    func executable() -> URL? {
        let custom = UserDefaults.standard.string(forKey: "ffprobePath") ?? ""
        let paths = custom.isEmpty ? ["/opt/homebrew/bin/ffprobe", "/usr/local/bin/ffprobe", "/usr/bin/ffprobe"] : [custom]
        return paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }).map { URL(fileURLWithPath: $0) }
    }
    func startScan() {
        guard let executableURL = executable() else {
            message = "未找到 ffprobe。请在设置中选择可执行文件；可先运行 brew install ffmpeg。"
            for i in rows.indices { rows[i].state = "缺少 ffprobe"; rows[i].error = message }; return
        }
        let token = UUID(); generation = token; scanning = true; completed = 0
        let inputs = rows.map { ($0.id, $0.url) }
        let parallelism = min(4, max(2, UserDefaults.standard.object(forKey: "concurrency") as? Int ?? 3))
        NSLog("Starting metadata scan: %d files, concurrency %d", inputs.count, parallelism)
        let service = ProbeService(executableURL: executableURL)
        let cache = cache
        scanTask = Task {
            await withTaskGroup(of: (UUID, MediaMetadata?, String?).self) { group in
                var next = 0
                func enqueue(_ item: (UUID, URL)) {
                    group.addTask {
                        do {
                            try Task.checkCancellation()
                            if let hit = await cache.value(for: item.1) { return (item.0, hit, nil) }
                            let ticket = await cache.begin(for: item.1)
                            let metadata = try await service.probe(url: item.1)
                            try Task.checkCancellation()
                            await cache.store(metadata, for: item.1, ticket: ticket)
                            return (item.0, metadata, nil)
                        } catch { return (item.0, nil, error.localizedDescription) }
                    }
                }
                while next < min(parallelism, inputs.count) { enqueue(inputs[next]); next += 1 }
                for await (id, metadata, error) in group {
                    guard !Task.isCancelled, self.generation == token else { group.cancelAll(); break }
                    if let i = self.rows.firstIndex(where: { $0.id == id }) {
                        self.rows[i].metadata = metadata; self.rows[i].error = error
                        self.rows[i].state = error == nil ? "完成" : "失败"; self.completed += 1
                    }
                    if next < inputs.count { enqueue(inputs[next]); next += 1 }
                }
            }
            if self.generation == token {
                self.scanning = false
                NSLog("Metadata scan completed: %d files, %d failures", self.completed, self.rows.filter { $0.error != nil }.count)
            }
        }
    }
    func cancel() {
        generation = UUID(); scanTask?.cancel(); scanTask = nil; intakeTask?.cancel(); intakeTask = nil; scanning = false
        for i in rows.indices where rows[i].metadata == nil && rows[i].error == nil { rows[i].state = "已取消" }
    }
    func refresh() {
        cancel()
        let token = generation
        scanTask = Task {
            await cache.clear()
            guard !Task.isCancelled, generation == token else { return }
            for i in rows.indices { rows[i].metadata = nil; rows[i].error = nil; rows[i].state = "等待分析" }
            startScan()
        }
    }
    func loadDropped(_ providers: [NSItemProvider]) {
        cancel()
        let token = generation
        intakeTask = Task {
            var urls: [URL] = []
            for provider in providers {
                guard !Task.isCancelled, generation == token else { return }
                let url: URL? = await withCheckedContinuation { continuation in
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in continuation.resume(returning: url) }
                }
                if let url { urls.append(url) }
            }
            guard !Task.isCancelled, generation == token else { return }
            load(urls)
        }
    }
    func clearCache() { Task { await cache.clear(); message = "元数据缓存已清除。" } }
    func escape() { if previewID != nil && rows.count > 1 { previewID = nil } else { NSApp.keyWindow?.close() } }
    func copySelected() {
        let data = visibleRows.filter { selectedIDs.contains($0.id) }.map { MetadataExport.cells(url: $0.url, metadata: $0.metadata, error: $0.error) }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(MetadataExport.tsv(rows: [MetadataExport.headers] + data), forType: .string)
    }
    func exportCSV() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "MediaInfo.csv"; panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = visibleRows.map { MetadataExport.cells(url: $0.url, metadata: $0.metadata, error: $0.error) }
            try MetadataExport.csv(rows: [MetadataExport.headers] + data, bom: UserDefaults.standard.object(forKey: "csvBOM") as? Bool ?? true).write(to: url, atomically: true, encoding: .utf8)
            message = "已导出 \(data.count) 行。"
        } catch { message = "导出失败：\(error.localizedDescription)" }
    }
}
