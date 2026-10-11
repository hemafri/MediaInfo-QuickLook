# Core and synthetic media verification

Executed locally on 2026-10-11. Environment: arm64 macOS 27.0.1 (26A434), Apple Swift 6.1.2, Homebrew ffmpeg/ffprobe 8.1.2.

## Reproduce

```sh
scripts/make-fixtures.sh
swiftc -D CORE_STANDALONE_CHECKS -parse-as-library Sources/MediaInfoCore/*.swift Tests/MediaInfoCoreTests/StandaloneChecks.swift -o .build/core-checks
.build/core-checks
swiftc -parse-as-library Sources/MediaInfoCore/*.swift scripts/integration-check.swift -o .build/integration-check
.build/integration-check
```

The scripts default to `/opt/homebrew/bin/ffmpeg` and `/opt/homebrew/bin/ffprobe`. Override with `FFMPEG` and `FFPROBE` environment variables. Generated media and 200 physical copies live under `.build/fixtures`, not in the source tree. Running the scripts replaces only these generated fixtures. The standalone test clears the application's metadata cache while testing cache epoch invalidation.

`swift test` was attempted and is blocked by the current Command Line Tools environment: `no such module 'XCTest'`. The checked-in XCTest suite remains available for a full Xcode toolchain. The successful results below were executed using the independent Swift executable harness, not claimed as an XCTest run.

## Actual results

| Synthetic source | Transfer observed by ffprobe | Classification | Depth | Average rate |
| --- | --- | --- | --- | --- |
| 中文 HLG 10bit.mp4 | arib-std-b67 | HLG | 10 | 29.970 fps |
| 中文 PQ 10bit.mov | smpte2084 | PQ | 10 | 24.000 fps |
| 中文 SDR 8bit.mp4 | bt709 | SDR（标记） | 8 | 25.000 fps |
| 中文 未标记.mov | absent | 未知 | 8 | 30.000 fps |

All four are 320×180, roughly 0.3 seconds. HLG/PQ use software HEVC Main 10; SDR/untagged use H.264. The encoder-specific x265/x264 transfer parameters are explicit because the initial command using only generic ffmpeg color flags did not preserve the intended transfer values in this local encoder build. Tests caught this, and the fixture generator was corrected before the passing run.

- Real batch: **200 successful files, 1 isolated corrupt-file failure**, concurrency limit **3**, **1.468 seconds** in the final measured run. Each of HLG, PQ, SDR and unknown counted 50. This measures these tiny synthetic local files, not camera footage or external-drive performance.
- Real ProbeService: Chinese/space filenames parsed; corrupt MP4 produces a per-file failure; immediate cancellation returns CancellationError.
- Process lifecycle: separate executable fixtures ignore SIGTERM; timeout and active cancellation terminate promptly using SIGKILL and waitUntilExit. A successful process writes more than 1 MB of stderr while stdout carries JSON; concurrent draining avoids pipe deadlock.
- Parser: known tags, nil/unknown/reserved, other transfer, ten-bit BT.2020 without transfer, attached-picture exclusion, missing video error, rational average FPS, and p010 10-bit inference pass. Raw pixel format, average-frame-rate rational and nominal-frame-rate rational are retained separately; nominal rate is not presented as measured average rate.
- Export: embedded comma/tab, quotes and newlines survive CSV/TSV escaping.
- Cache: persistence across instances, file-size and mtime invalidation pass. A ticket captured before analysis is rejected after file mutation or cache clear. ProbeService separately rejects a file whose size/mtime changes during analysis.
- AVFoundation: all four actual assets are playable, expose video tracks and positive durations; AVPlayerItem reaches readyToPlay and the playback clock advances. This is a real API playback-readiness test without a displayed player window.

## Limits

These tests do not establish correct visible HDR rendering, HDR display output, real Sony/Nikon camera metadata, Finder Automation authorization, global shortcut behavior, 200-row UI responsiveness, or signing/notarization. They do not recover shooting curves from private camera metadata. Classification describes the encoded file's transfer tag only.

Cache fingerprints use the requested path, size and modification-time contract. A modification deliberately preserving size and mtime is outside that contract. Production asynchronous callers must capture `await cache.begin(for: url)` before analysis and pass the resulting ticket to `await cache.store(metadata, for: url, ticket: ticket)`; the convenience no-ticket overload is for synchronously constructed metadata.
