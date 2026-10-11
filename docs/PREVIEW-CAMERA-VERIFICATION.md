# 0.2.0 预览与相机参数验证

日期：2026-10-11。功能提交：`e72b6cc`。

## 行为

播放器使用预览区剩余高度；下方信息区为预览可用高度的 20%，即原先约半高区域的 2/5，最小 68pt。内容滚动显示，曝光与陀螺仪字段放在最上方。

自动播放默认开启，设置使用 `autoPlayPreview` 持久化。切换设置影响当前预览；加载新视频时使用保存偏好。旧视频状态回调不能触发新视频自动播放，退出预览释放播放器。

相机字段先读取 ffprobe 视频流与容器标签，再使用可选 ExifTool 补充。ExifTool 安装于本机 Homebrew，本次版本 13.55。使用参数数组、JSON 输出及 `-ee`，不写原视频。每个工具分别 20 秒超时，补充读取失败不使基本参数失效。工具路径/mtime 参与缓存上下文，缓存 schema 改为 v3；旧 v2 文件不再读取。

## 本机实际执行

- `scripts/check.sh` 完整通过，包括原有 200 文件批量、单条损坏隔离、取消/超时/缓存/热键冲突等回归。
- 自动播放回归在旧版先失败，修改后默认播放、关闭后暂停、实时开关、stop 释放和快速切换均通过真实 AVPlayer 时钟验证。
- Camera capture 回归在旧版缺失字段时先失败；新字段解析与视频流优先级、十进制曝光时间、时序多值、无效值、缓存编码、导出列对应均通过。
- 陀螺仪测试区分实际三轴读数（包括全零）、明确标记、一般 telemetry、防抖模式、空字段。额外模式字符串误判先复现，再修复；`Gyroscope=Off` 不被当作陀螺仪采样。
- 在合成 MP4 副本中写入已知 XMP 标签（仅测试副本），真实 ExifTool 读取为 1/125 s、f/4、ISO 640；应用读取一致。工具不存在时，基本视频参数保留并提供扩展失败说明。
- Release 构建及 ad-hoc 签名校验通过。真实 UI 查看原片及合成片，播放器高度扩大，拍摄字段位于首屏，其他元数据可滚动。
- 设置页关闭自动播放后重启应用，4 秒合成片停留 `00:00:00.000`；设置勾选状态仍关闭。重新开启并加载新片，进度达到片尾。验证后恢复默认开启。
- 设置页布局原先发生横向裁切，调整为独立滚动布局后全部控件可见。

## 用户原片与 HDR 验证

用户明确确认真实相机素材与 HDR 显示准确性已验证。本记录将其作为用户验收证据；不宣称做过仪器校准，也不外推到其他机型和显示设备。

本轮用户提供的一段 MOV 由 ExifTool 标识为 `NIKON CORPORATION / NIKON Z6_3`。实际进程读取与真实应用窗口一致：

| 字段 | 结果 |
| --- | --- |
| 快门 | 1/3200 s |
| 光圈 | f/4 |
| ISO | 168（文件原始解析值，未四舍五入到常见 ISO 档位） |
| 陀螺仪 | 未检出（不能排除私有数据） |

此处核对的是文件元数据与应用显示一致；用户没有给出该片的独立拍摄设置记录用于交叉核对。原片、原片画面截图和绝对路径未提交仓库或上传 CI。

## 支持边界

ExifTool 支持的具体字段是判断依据：[Sony rtmd 定义](https://github.com/exiftool/exiftool/blob/master/lib/Image/ExifTool/Sony.pm)、[QuickTime 时序元数据与 AngularVelocity](https://github.com/exiftool/exiftool/blob/master/lib/Image/ExifTool/QuickTimeStream.pl)、[GoPro Gyroscope](https://github.com/exiftool/exiftool/blob/master/lib/Image/ExifTool/GoPro.pm)。存在 rtmd/gpmd 不能证明存在陀螺仪；无法解析厂商私有格式时保留未检出状态。时序字段显示识别到的值，不保证逐帧覆盖全片。

CSV/TSV 保留原来 19 列，并在末尾追加快门、光圈、ISO、陀螺仪、来源、说明，共 25 列。

演示截图只使用合成测试素材：[单文件预览](screenshots/single-preview.png)、[设置](screenshots/settings.png)。

## 双架构 CI 与交付包

[GitHub Actions 完整执行](https://github.com/hemafri/MediaInfo-QuickLook/actions/runs/38142382316) 最终状态 success。arm64 和 x86_64 均在 macOS 15.7.9 / Xcode 16.4 上完成：

- Xcode Debug/XCTest 各 10 项、0 失败；Xcode Release 构建成功。
- Swift Package XCTest 各 10 项、0 失败。
- 真实 ExifTool 补充读取、失败降级、自动播放/关闭/切换测试及原有完整回归通过。
- 两种架构均生成开发 ZIP；下载后 SHA-256 与 CI 记录一致，解压签名、架构及 0.2.0 版本校验通过。

| 包 | SHA-256 |
| --- | --- |
| `dist/MediaInfo-QuickLook-macOS-arm64.zip` | `524f67b80c6439eb1f0c2a37988b5d2820db9ab531ca0a9092ebe45a11ed6d7b` |
| `dist/MediaInfo-QuickLook-macOS-x86_64.zip` | `2cca8db0a81a69f8159bff67f0f4ba714e61884e0c2a703015f5de9890547a6b` |

`dist/MediaInfo-QuickLook-macOS.zip` 为本机实际运行的 0.2.0 arm64 开发包；带架构后缀的包来自上述 CI。均为 ad-hoc、未公证，不内置 ffprobe/ExifTool。
