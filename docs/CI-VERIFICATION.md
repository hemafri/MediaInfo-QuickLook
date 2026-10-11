# GitHub macOS CI 验证记录

本页保留 0.1.0 首次 CI 的历史证据；0.2.0 最新执行记录及安装包校验和见 [预览与相机参数验证](PREVIEW-CAMERA-VERIFICATION.md)。

日期：2026-10-11。验证提交：`eb1c4af690c77cb2ea60a44244f0f8e7c46b85f5`。

[完整运行及下载产物](https://github.com/hemafri/MediaInfo-QuickLook/actions/runs/38140707415)。工作流定义在 `.github/workflows/macos.yml`，代码推送和 PR 自动运行，文档变更不重复触发。

本次工作流最终状态：**success**，Apple Silicon 与 Intel 两个 job 均成功。

## Apple Silicon 实际执行

- macOS 15.7.9（24G830），arm64，Xcode 16.4（16F6），Swift 6.1.2。
- 已提交 Xcode 工程重新生成后无差异。
- Xcode Debug build + XCTest：8 个测试，0 失败。
- Xcode Release build：成功，嵌入 Core framework 的应用通过 `codesign --verify --deep --strict`。
- Swift Package XCTest：8 个测试，0 失败。
- `scripts/check.sh`：核心断言、合成 HLG/PQ/SDR/未知、200 文件 + 单条损坏、应用增量扫描与取消、热键跨进程冲突检查全部通过。
- 四种合成视频 AVFoundation `readyToPlay` 且播放时钟推进。
- Release 开发 ZIP 构建、签名检查与 Actions artifact 上传成功。

## Intel 实际执行

- macOS 15.7.9（24G830），x86_64，Xcode 16.4（16F6），Swift 6.1.2。
- Xcode Debug/XCTest：8 个测试、0 失败；Release 构建及签名验证成功。
- Swift Package XCTest：8 个测试、0 失败。
- 与 arm64 相同的核心、媒体集成、应用模型及热键冲突检查全部通过；四类 AVFoundation 播放时钟均推进。
- 200 个有效文件 + 1 个损坏文件：200 成功、1 独立失败；并发 3，Intel 3.918 秒、arm64 2.736 秒。这是合成小文件和不同 runner 的结果，不用于比较用户硬件性能。
- Release ZIP 生成与上传成功。Intel 的完整应用窗口和 Finder 交互尚未实测。

## 下载后的包校验

两套产物下载到本机后，SHA-256 与 CI 记录一致；解压后的 `codesign --verify --deep --strict` 均通过，`lipo -archs` 分别确认为 arm64、x86_64。

| 本地交付包 | SHA-256 |
| --- | --- |
| `dist/MediaInfo-QuickLook-macOS-arm64.zip` | `83515e1efee2abafd2eb7d2ae6ad52c0e6bac3767f617f15657c1b298ab0a3d9` |
| `dist/MediaInfo-QuickLook-macOS-x86_64.zip` | `32681970e98342151130227cdf8dcae71f2c2c5810a7f6f5d60d82f1dd61f327` |

原来的 `dist/MediaInfo-QuickLook-macOS.zip` 保留为本机已实际打开的开发包；上述两个带架构名的文件来自 CI，相同产品源码，工具链环境见上。

## 证据与范围

每个架构保存 `environment.txt`、Xcode/Swift 测试日志、`CoreTests.xcresult`、集成日志、打包日志与 ZIP SHA-256。Actions 保留 14 天；之后可按相同提交重新运行。本地下载的证据在 `.build/ci-evidence/38140707415/`，不提交带 runner 路径的整份日志。

Xcode 日志包含非失败警告：没有 AppIntents 依赖所以跳过其 metadata 提取；已签名 framework 不再执行 strip。应用构建、测试及签名校验均成功，不将日志称为零警告。

CI runner 不验证物理 Finder 快捷键、Automation 弹窗、实际 HDR 色彩输出或 Sony/Nikon 原片。其 ad-hoc 包未经 Developer ID 公证，且不含 ffprobe；不构成正式分发验收。最低目标 macOS 13 仍未在对应系统实机运行。
