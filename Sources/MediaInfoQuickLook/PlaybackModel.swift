import AVKit
import Combine

@MainActor final class PlaybackModel: ObservableObject {
    let player = AVPlayer()
    @Published var status = "正在加载视频…"
    private var observation: NSKeyValueObservation?
    func load(_ url: URL, autoPlay: Bool = true) {
        stop()
        status = "正在加载视频…"
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        observation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                guard let self, self.player.currentItem === item else { return }
                switch item.status {
                case .readyToPlay: self.status = ""
                case .failed: self.status = "播放失败：\(item.error?.localizedDescription ?? "AVPlayer 不支持此文件")。元数据仍可查看。"
                default: self.status = "正在加载视频…"
                }
            }
        }
        setAutoPlay(autoPlay)
    }
    func setAutoPlay(_ enabled: Bool) { if enabled { player.play() } else { player.pause() } }
    func stop() { player.pause(); observation = nil; player.replaceCurrentItem(with: nil) }
}
