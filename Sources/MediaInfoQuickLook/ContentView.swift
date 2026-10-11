import SwiftUI
import AVKit
#if canImport(MediaInfoCore)
import MediaInfoCore
#endif

struct ContentView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button("打开文件…", action: model.openPanel)
                Button("重新分析", action: model.refresh).disabled(model.rows.isEmpty || model.scanning)
                if model.scanning { Button("取消", action: model.cancel) }
                Spacer()
                Button("复制所选 TSV", action: model.copySelected).disabled(model.selectedIDs.isEmpty)
                Button("导出 CSV", action: model.exportCSV).disabled(model.rows.isEmpty)
            }
            if let row = model.preview {
                HStack {
                    if model.rows.count > 1 { Button("返回列表") { model.previewID = nil } }
                    Text(row.url.lastPathComponent).font(.headline).lineLimit(1)
                    Spacer()
                    if model.rows.count > 1 {
                        Picker("切换视频", selection: $model.previewID) {
                            ForEach(model.rows) { Text($0.url.lastPathComponent).tag(Optional($0.id)) }
                        }.frame(maxWidth: 330)
                    }
                }
                PreviewView(row: row).id(row.id)
            }
            // Keep the table mounted while previewing so scroll position and selection survive.
            VStack(spacing: 10) {
                HStack {
                    Text("共 \(model.rows.count) 个").bold()
                    ForEach(HDRKind.allCases, id: \.rawValue) { kind in
                        Button("\(kind.title) \(model.counts[kind, default: 0])") { model.filter = kind == .other ? "unknown" : kind.rawValue }
                    }
                    Spacer()
                }
                HStack {
                    TextField("搜索文件名", text: $model.search).textFieldStyle(.roundedBorder)
                    Picker("类型", selection: $model.filter) {
                        Text("全部").tag("全部"); Text("HLG").tag("hlg"); Text("PQ").tag("pq"); Text("SDR（标记）").tag("sdr"); Text("未知 / 其他").tag("unknown")
                    }.frame(width: 220)
                    Toggle("非主流类别", isOn: $model.minorityOnly).help("仅筛选与数量最多类别不同的已分析素材；不代表故障。同票时按固定类别顺序选择。")
                }
                MediaTable(model: model)
                Text("双击行预览 · 右键表头选择显示列 · 拖动列边界调整宽度").font(.caption).foregroundStyle(.secondary)
            }.frame(maxHeight: model.preview == nil ? .infinity : 0).opacity(model.preview == nil ? 1 : 0).clipped().accessibilityHidden(model.preview != nil)
            Divider()
            HStack {
                if model.scanning { ProgressView(value: Double(model.completed), total: Double(max(1, model.rows.count))).frame(width: 110) }
                Text("\(model.completed)/\(model.rows.count) · 失败 \(model.rows.filter { $0.error != nil }.count)").monospacedDigit()
                Text(model.message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                Spacer()
            }
        }.padding(14).frame(minWidth: 900, minHeight: 620)
        .onExitCommand(perform: model.escape)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            model.loadDropped(providers)
            return true
        }
    }

}

@MainActor final class PlaybackModel: ObservableObject {
    let player = AVPlayer()
    @Published var status = "正在加载视频…"
    private var observation: NSKeyValueObservation?
    func load(_ url: URL) {
        let item = AVPlayerItem(url: url)
        observation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                switch item.status {
                case .readyToPlay: self?.status = ""
                case .failed: self?.status = "播放失败：\(item.error?.localizedDescription ?? "AVPlayer 不支持此文件")。元数据仍可查看。"
                default: self?.status = "正在加载视频…"
                }
            }
        }
        player.replaceCurrentItem(with: item)
    }
    func stop() { player.pause(); observation = nil; player.replaceCurrentItem(with: nil) }
}
struct PreviewView: View {
    let row: MediaRow
    @StateObject private var playback = PlaybackModel()
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            NativePlayerView(player: playback.player).frame(minHeight: 220, idealHeight: 320)
            HStack {
                Button("播放 / 暂停") { if playback.player.rate == 0 { playback.player.play() } else { playback.player.pause() } }
                Button("静音 / 取消静音") { playback.player.isMuted.toggle() }
                Text(playback.status).foregroundStyle(.secondary)
            }
            Text(row.url.path).font(.caption).textSelection(.enabled)
            if let m = row.metadata {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.fixed(140), alignment: .leading), GridItem(.flexible(), alignment: .leading), GridItem(.fixed(100), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 9) {
                        ForEach(Array(fields(m).enumerated()), id: \.offset) { _, pair in
                            Text(pair.0).foregroundStyle(.secondary); Text(pair.1).textSelection(.enabled)
                        }
                    }
                }.frame(minHeight: 170)
                if !m.warning.isEmpty { Text(m.warning).font(.caption).foregroundStyle(.orange) }
            } else { Text(row.error ?? row.state).textSelection(.enabled) }
            Text("根据视频文件标记识别；标签不能证明实际拍摄曲线或 HDR 显示准确性。").font(.caption).foregroundStyle(.secondary)
        }.onAppear { playback.load(row.url) }.onDisappear { playback.stop() }
    }
    private func fields(_ m: MediaMetadata) -> [(String, String)] {
        [("HDR 分类", m.hdr.title), ("像素格式（原始）", m.rawPixelFormat), ("平均帧率（原始）", m.rawAverageFrameRate), ("标称帧率（原始）", m.rawNominalFrameRate), ("Transfer（原始）", m.transfer), ("Color primaries", m.primaries), ("Matrix", m.matrix), ("位深", m.bitDepth), ("色度采样", m.chroma), ("编码", m.codec), ("Profile", m.profile), ("分辨率", m.resolution), ("平均帧率", m.frameRate), ("码率", m.bitRate), ("时长", m.duration), ("容器", m.container), ("文件大小", m.fileSize), ("相机", m.camera)]
    }
}

// Avoid SwiftUI VideoPlayer runtime metadata failures on newer OS/older CLI SDK pairs.
struct NativePlayerView: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.showsFullScreenToggleButton = true
        view.player = player
        return view
    }
    func updateNSView(_ view: AVPlayerView, context: Context) { view.player = player }
    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) { view.player?.pause(); view.player = nil }
}
