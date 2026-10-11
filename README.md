# MediaInfo QuickLook

原生 macOS 菜单栏视频检查工具，面向 Finder 中的 MP4 / MOV 素材。根据**视频流 transfer 标签**识别 HLG、PQ、SDR（标记）、未知/其他；不猜测 Sony S-Log、Nikon N-Log 或实际拍摄历史。系统 `Space` Quick Look 保留原样。

当前交付：**0.1.0 开发版**，已有实际运行的 Apple Silicon `.app`。不是已公证的正式发行版。功能和测试边界见 [测试结果](docs/TEST-RESULTS.md) 与 [验收清单](docs/ACCEPTANCE.md)。

## 安装与首次使用

最低目标 macOS 13；本次实际测试为 macOS 27.0.1 / Apple Silicon。其他系统与 Intel 构建尚未实测。

1. 解压 `dist/MediaInfo-QuickLook-macOS.zip`，将 `MediaInfo QuickLook.app` 拖到“应用程序”。也可直接运行 `dist` 中的应用。
2. 安装可信来源的 `ffprobe`。已有 Homebrew 时运行 `brew install ffmpeg`。应用自动查找 `/opt/homebrew/bin/ffprobe`、`/usr/local/bin/ffprobe`；其他位置在菜单栏 → 设置中选择。**没有内置 ffprobe，也不会替你下载或执行安装器。**
3. 启动后点击菜单栏胶片图标 → 打开窗口；选择“打开文件…”或把视频拖入窗口。
4. 从 Finder 触发：保持 Finder 在前台并选择视频，按 `Option+Space`。首次允许应用控制 Finder；若拒绝，可继续使用打开文件或拖放入口。权限设置位于“系统设置 → 隐私与安全性 → 自动化 → MediaInfo QuickLook → Finder”。
5. 设置中可修改修饰键/按键组合、ffprobe 路径、2–4 并发与 CSV BOM；点击“应用快捷键”完成注册。菜单栏可停用热键、暂停增强预览或退出。

`Option+Space` 同时是 Finder 的原生全屏预览组合。Carbon 注册能报告注册层面的冲突，但不能证明所有应用内或系统保留组合都能被替代；若仍进入系统全屏预览，请改用 `Control+Option+Space` 等组合。普通 `Space` 从未注册或拦截。本地 ad-hoc 开发签名在重新构建、移动后可能需要重新授权；不能以开发签名替代 Developer ID 公证。

## 使用

- **单文件**：原生 AVPlayerView 播放、暂停、静音和进度拖动；展示 transfer、primaries、matrix、位深、色度采样、编码、profile、宽高、帧率、码率、时长、容器、文件大小、相机字段（存在时）。保留原始 pix_fmt 与平均/标称帧率。播放失败不会阻止元数据展示。
- **批量**：先显示文件名，再增量填充元数据；每个文件独立失败。点表头排序（数值列按数值排序），搜索文件名，按 HDR 分类筛选，查看各类数量。“非主流类别”只表示与数量最多类别不同，不等于故障；并列时按固定类别顺序选择参考类别。
- 双击行预览，返回列表保留排序、筛选、选择和滚动位置。单文件页有切换视频菜单。`Esc` 从批量中的单文件页返回列表，再次按关闭窗口；单独打开一项时直接关闭。
- 右键表头选择显示列，拖动列边界调整宽度；列宽、列显隐、排序、HDR 筛选和窗口位置持久化。
- “复制所选 TSV”复制当前筛选结果中选中的行；“导出 CSV”导出当前筛选/排序后的所有可见行，包含表头。CSV 默认 UTF-8 BOM，设置中可关闭。路径、引号、逗号、换行均进行转义。
- “取消”或关闭窗口取消剩余分析并终止 ffprobe；“重新分析”清缓存并重扫当前选集。设置中可单独清缓存。
- 支持 MP4/MOV/M4V；混选目录、图片和其他扩展名会汇总跳过。损坏视频作为失败行保留。

元数据和缓存均保存在本机，不上传任何文件；不改写视频或视频时间戳。缓存位于 `~/Library/Application Support/MediaInfoQuickLook/metadata-cache-v2.json`，包含已分析路径与参数，键使用规范化路径、文件大小与修改时间；文件变更会失效。

## 构建

源码使用 Swift 5 语言模式，Swift 5.9+ 工具链。UI 为 SwiftUI + AppKit，播放为 AVFoundation/AVKit，热键为 Carbon 注册式 API，Finder 为结构化 Apple Events。应用**不启用 App Sandbox**，使用 hardened runtime 与 Automation entitlement；不存在“任意 ffprobe 可在沙盒中直接运行”的假设。

### 完整 Xcode

直接打开 `MediaInfoQuickLook.xcodeproj`，选择共享 scheme `MediaInfoQuickLook`，Run。工程包含 app、Core framework、XCTest targets 和 Debug/Release 配置。

```sh
xcodebuild -project MediaInfoQuickLook.xcodeproj -scheme MediaInfoQuickLook -configuration Debug -derivedDataPath DerivedData build
xcodebuild -project MediaInfoQuickLook.xcodeproj -scheme MediaInfoQuickLook -destination 'platform=macOS' test
```

工程已提交，无需 XcodeGen 或第三方生成工具。新增源码后可运行 `python3 scripts/generate-xcode-project.py` 重新生成，输出确定且仅依赖 Python 标准库。Xcode 生成的产品名为 `MediaInfoQuickLook.app`，显示名为 MediaInfo QuickLook。

### 只有 Command Line Tools

```sh
scripts/build-app.sh debug
scripts/build-app.sh release
open 'dist/MediaInfo QuickLook.app' --args --show
```

产物为 `dist/MediaInfo QuickLook.app` 和 `dist/MediaInfo-QuickLook-macOS.zip`。默认使用本地 ad-hoc 签名。脚本按当前架构构建；本次交付 ZIP 为 arm64。无完整 Xcode 时仍可构建运行应用，但 `swift test` 可能因没有 XCTest SDK 失败。

## 测试

```sh
scripts/check.sh
# 完整 Xcode 工具链还可运行：
swift test
```

`check.sh` 实际编译并运行独立 Swift 断言程序，生成 HLG/PQ/SDR/未知测试视频、200 个文件副本及损坏文件，验证解析、导出、缓存、超时/取消、AVPlayer 播放时钟与应用扫描模型。需要 ffmpeg/ffprobe；`FFMPEG`、`FFPROBE` 可覆盖测试二进制路径。合成素材位于 `.build/fixtures`；测试会更新这一区域，并清理应用元数据缓存，不修改用户素材。合成测试不能代替 Sony/Nikon 原片与 HDR 显示验收。

详细执行证据：[核心测试](docs/CORE-VERIFICATION.md)、[系统集成](docs/PLATFORM-VERIFICATION.md)、[本次交付结果](docs/TEST-RESULTS.md)。

## 发布准备

本次 ZIP 不包含第三方 ffprobe，避免对未核验构建进行再分发。若未来内置，需审查实际 ffprobe 构建配置、许可证、对应源码/声明以及签名，而不是仅凭工具名称推断许可。

拥有 Developer ID 证书后，可通过 `CODE_SIGN_IDENTITY='Developer ID Application: …' scripts/build-app.sh release` 签名，再执行 `xcrun notarytool submit dist/MediaInfo-QuickLook-macOS.zip --keychain-profile <profile> --wait`；成功后 `xcrun stapler staple 'dist/MediaInfo QuickLook.app'` 并重新生成 ZIP。本次未具备可用发布证书，**未执行公证**。不要将本地签名验证误写成 Gatekeeper 发行验证。
