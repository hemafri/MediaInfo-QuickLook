# 2026-10-11 开发版测试结果

最新 0.2.0 功能与验证见 [预览及拍摄参数记录](PREVIEW-CAMERA-VERIFICATION.md)。本报告保留初始版本的执行历史，区分实际执行、静态检查和待验证项。交付为可运行开发版；交接文档中的全部验收门槛尚未全部通过。

## 环境与构建

- 本机 Apple Silicon arm64，macOS 27.0.1 (26A434)，Apple Swift 6.1.2；工程最低目标 macOS 13。
- 已执行 `swift build` Debug、`scripts/build-app.sh debug`、`scripts/build-app.sh release`，全部构建成功。
- 实际 `.app` 已启动，菜单栏应用、窗口、原生批量表格、单文件参数和 HLG 播放画面已观察。
- `codesign --verify --deep --strict` 通过，本地 ad-hoc + hardened runtime + Automation entitlement。ZIP 为 arm64，不含 ffprobe。
- 已生成并检查 Xcode app/Core framework/XCTest targets、共享 scheme、Debug/Release、依赖与源码引用；`plutil` 通过，生成结果确定。
- **未执行成功的项目**：`xcodebuild -version/-list` 被环境拒绝（只有 Command Line Tools）；`swift test` 报 `no such module XCTest`。这仅描述本机初次验证；后续 GitHub CI 已补齐 Xcode/XCTest 证据，见 [CI 验证记录](CI-VERIFICATION.md)。
- 系统签名身份列表未发现 Developer ID Application。没有使用其他用途的分发证书；未执行公证、staple 或异机 Gatekeeper 验证。

## 自动化执行结果

统一命令：`scripts/check.sh`，2026-10-11 继续工作时完整复跑成功。GitHub CI 的 arm64 和 x86_64 也均通过 Xcode Debug/Release、XCTest（各 8 项、0 失败）、Swift Package XCTest 和相同媒体集成检查，见 [CI 验证记录](CI-VERIFICATION.md)。

| 验证 | 实际结果 |
| --- | --- |
| transfer 分类、nil/unknown/reserved、其他值 | 通过；缺失标签即使 10bit/BT.2020 也不归为 SDR/HDR |
| ffprobe JSON、封面流排除、平均帧率、有理数、像素格式 | 通过；保留原始 transfer/pix_fmt/平均与标称帧率 |
| CSV / TSV | 逗号、制表符、引号、换行和中文转义通过 |
| 缓存 | 跨实例持久化、大小/mtime 失效、文件变化 ticket 拒绝、清除 epoch 拒绝通过 |
| 子进程 | 大 stderr 不堵塞、超时、忽略 SIGTERM 的进程取消后被 SIGKILL 并回收通过 |
| 实际 MP4/MOV | HLG/PQ 10bit、SDR 8bit、缺失 transfer 样本解析通过 |
| 200 文件 + 1 损坏 | 200 成功、1 独立失败；并发 3；本机后续完整运行 1.415 秒，各有效类型 50 个 |
| AVFoundation | 四种样本均 readyToPlay，播放时钟推进；不据此声称视觉 HDR 正确 |
| 应用扫描模型 | 先显示 201 个文件名、增量进度、错误隔离、统计、目录跳过通过 |
| 应用状态回归 | 取消刷新不重启、取消扫描、快速重选不被旧结果覆盖、数值小数排序、文件名搜索、未知筛选通过 |
| 热键冲突 | 两个真实进程竞争同一组合，独占持有方存在时正确报错；普通 Space 无法注册 |
| 工程配置 | Info.plist、entitlements、project.pbxproj 语法通过 |

批量计时只是约 0.3 秒、320×180 合成文件在本机本地磁盘的结果，不代表 200 个相机长片段、网络卷或外接硬盘性能。检查程序清理应用元数据缓存，不修改用户视频。

## 实际界面观察

通过桌面自动化读取了真实运行窗口与截图：

- 打开文件面板读取中文及空格路径；批量窗口同时显示 HLG 视频和损坏 MP4。
- HLG 行显示 `arib-std-b67 / bt2020 / 10 / 4:2:0 / hevc / 320×180 / 29.970 fps`。
- 损坏文件显示 ffprobe 的 `moov atom not found`，其他文件成功。
- 单文件原生 AVPlayerView 显示合成 HLG 色条并播放到后续帧，结构化参数完整出现。
- 应用运行期间在 Finder 按普通 Space，出现系统原生“快速查看”窗口及 HDR 标识。
- 自动化注入 Option+Space 时进入 Finder 原生全屏预览；这不证明物理全局热键回调成功或失败。随后用户实际按键验证通过，见下述人工确认。
- 曾被系统锁屏阻断；用户解锁后继续完成：PQ 分类筛选、帧率表头排序、双击 PQ 预览、Esc 返回并保留选择/筛选/横向滚动位置（滚动条值返回前后同为 0.92206）。
- 通过真实保存面板导出筛选后的 CSV；Python csv 读取确认 UTF-8 BOM、19 列表头、恰好 1 个 PQ 数据行和 smpte2084。
- Release 进程冒烟测试：单文件预览与五文件列表分别持续运行，无启动崩溃。`scripts/runtime-smoke.py` 不将进程存活冒充像素验证。
- 用户确认 Option+Space 与 Codex 快捷键冲突，并明确要求修改 Codex、保留本工具组合。工具安全限制禁止操作 Codex 自身，已提供官方设置步骤，用户确认已修改 Codex 快捷键；本工具继续使用 Option+Space。
- 用户实际在 Finder 单选视频并按 Option+Space，确认出现 Automation 授权框，允许后打开增强预览。随后多选两个视频再次实际按键，确认进入同一个批量窗口并显示“共 2 个”。桌面自动化随后读取真实窗口，核对 HLG 与未知两行、2/2 完成、0 失败。物理按键及首次允许依据为用户确认，列表内容另有直接界面读取证据。
- 实际拖放、表格软件粘贴、列偏好重启恢复及完整快捷键矩阵仍需交互验收。

2026-10-11 继续验收：Esc 关闭增强窗口后，在 Finder 选中 HLG 文件按普通 Space，再次读取到系统“快速查看”窗口和 HDR 标识。随后桌面工具连接超时，停用热键与退出状态尚未取得新证据。

真实应用窗口截图已保存至 [单文件预览](screenshots/single-hlg.png) 与 [批量窗口](screenshots/batch.png)，仅包含合成测试素材与本项目路径，没有截取其他应用窗口。批量截图及界面读取确认双选组合是 HLG MP4 + 未标记 MOV。

## 本次发现并修复

1. **SwiftUI VideoPlayer 实机崩溃**：编译通过但进入预览时 SIGABRT；运行日志 `failed to demangle superclass of VideoPlayerView ... AVPlayerView`。改为直接包装 AppKit AVPlayerView 后，同一合成 HLG 实际窗口播放成功。没有把编译成功当作运行成功。
2. **刷新取消竞态**：先调用 refresh，再取消，旧任务仍启动分析；独立断言先失败。刷新任务纳入生命周期，清缓存后检查 generation/cancellation，回归通过；拖入文件的异步解析也增加同类保护。
3. **缓存变更竞态**：分析前生成 ticket，写入前验证文件大小/mtime和缓存 epoch，拒绝变更期间或清缓存后的旧结果；ProbeService 同时检查分析期间文件变化。
4. **小数列排序**：字符串 numeric compare 将 1.2 排在 1.11 前；回归先失败。位深/帧率/码率/时长改为真实数值排序，未知置后。
5. **热键“假成功”**：SDK 说明非独占注册在其他独占持有者存在时可成功但收不到事件；双进程测试先失败。改为 `kEventHotKeyExclusive` 后冲突正确报错。依据为本机 CarbonEvents.h 文档，不依靠猜测。

## 未通过完整验收的外部条件

- Finder 首次允许与物理热键单/多选已通过；拒绝、重新允许，以及退出/停用后的 Quick Look 行为仍需验证。
- 本机缺少完整 Xcode；GitHub CI 已补齐 Xcode/XCTest 验证，详见 CI 验证记录。
- 用户随后确认原片验证通过；0.2.0 另对一段 Nikon Z6 III MOV 做了实际拍摄参数提取，私有陀螺仪识别边界见新报告。
- 用户随后确认 HDR 显示准确性验证通过；这是用户实测确认，未附仪器校准记录。
- 需要外接盘/权限拒绝/大文件及持续批量操作的交互验证。
- 正式分发需要 Developer ID Application 身份与公证权限；当前不具备。

具体步骤见 [ACCEPTANCE.md](ACCEPTANCE.md)。技术证据细节见 [CORE-VERIFICATION.md](CORE-VERIFICATION.md) 和 [PLATFORM-VERIFICATION.md](PLATFORM-VERIFICATION.md)。
