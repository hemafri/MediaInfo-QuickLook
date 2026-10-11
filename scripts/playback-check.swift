import AVKit
import SwiftUI

@main struct PlaybackChecks {
    @MainActor static func main() async throws {
        let model = PlaybackModel()
        let url = URL(fileURLWithPath: ".build/playback-validation.mp4")
        model.load(url)
        try await Task.sleep(nanoseconds: 1_000_000_000)
        guard model.player.currentTime().seconds > 0.1 else {
            print("FAIL: entering preview must automatically advance the video clock by default")
            exit(1)
        }
        model.stop()
        guard model.player.currentItem == nil, model.player.rate == 0 else { fatalError("stop must release playback") }
        model.load(url, autoPlay: false)
        try await Task.sleep(nanoseconds: 500_000_000)
        guard model.player.rate == 0, model.player.currentTime().seconds < 0.01 else { fatalError("disabled autoplay must remain paused") }
        model.setAutoPlay(true)
        try await Task.sleep(nanoseconds: 350_000_000)
        guard model.player.currentTime().seconds > 0.1 else { fatalError("enabling autoplay must start current preview") }
        model.setAutoPlay(false)
        let paused = model.player.currentTime().seconds
        try await Task.sleep(nanoseconds: 150_000_000)
        guard model.player.rate == 0, abs(model.player.currentTime().seconds - paused) < 0.03 else { fatalError("disabling autoplay must pause") }
        model.load(url)
        model.load(url, autoPlay: false)
        try await Task.sleep(nanoseconds: 350_000_000)
        guard model.player.rate == 0, model.player.currentTime().seconds < 0.01 else { fatalError("old ready callback must not start replacement") }
        model.stop()
        print("PASS: default autoplay, opt-out, live toggle, stop, and rapid preview replacement")
    }
}
