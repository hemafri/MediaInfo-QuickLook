# 0.2.1 显示优化验证

日期：2026-10-11。本机为 Apple Silicon，Command Line Tools Swift 6.1.2。

## 变更

- 单文件移除拍摄参数说明、原始平均帧率、原始 Transfer、原始像素格式、原始标称帧率、拍摄参数来源；保留快门、光圈、ISO、陀螺仪数据。
- 时长始终保留秒后一位小数。码率与文件大小按 1000 进制自动切换单位，最多一位小数，整数去掉多余 `.0`。
- 批量表格和 CSV/TSV 使用相同显示格式；CSV/TSV 去掉拍摄参数来源、说明，共 23 列，保留通用 Transfer 列用于 HDR 标签核对。
- 原始值仍保存在内部；排序不使用已舍入或已缩放的显示文本，旧缓存无需重扫。

## 本机验证

- 格式回归在修改前失败，修改后通过；覆盖单位边界、零、缺失及非有限/负值。
- 回归覆盖同样显示为 1.1 s 的两个不同原始时长，以及 900 kbps / 2 Mbps 混合单位的正向与反向排序。
- `scripts/check.sh` 全部通过：解析、缓存、导出、工具超时/取消、真实 ExifTool、自动播放、四种标签素材、200 文件与损坏文件、应用扫描、热键冲突。
- `scripts/build-app.sh release` 通过，开发签名校验通过；实际启动 0.2.1 应用。
- 真实 Nikon MOV 的界面值：23.3 Mbps、1.0 s、5.3 MB；快门 1/3200 s、f/4、ISO 168 保留。仅本机读取，未提交素材、原片截图或私有路径。
- 合成素材界面截图已更新，六项已移除，紧凑信息区与播放正常。原片核对后保留在应用内供继续使用。

## Xcode 与双架构 CI

功能提交：`d8c75760336e455121487abe6180e66bbec818f9`。[完整 CI 运行](https://github.com/hemafri/MediaInfo-QuickLook/actions/runs/38148522491)，Apple Silicon / Intel 两个 job 均为 success。

- 两种架构的 Xcode Debug 构建、XCTest（各 11 项，零失败）、Release 构建和签名校验通过。
- 两种架构的 Swift Package XCTest（各 11 项，零失败）及 `scripts/check.sh` 全部通过。
- 下载后检查 SHA-256 与 CI 记录一致，解压签名、二进制架构、版本 0.2.1 均通过。
- 本机已更新 `dist/MediaInfo-QuickLook-macOS-arm64.zip` 与 `dist/MediaInfo-QuickLook-macOS-x86_64.zip`。通用文件名 ZIP 为本机 arm64 构建。
- Intel 完整桌面交互仍未实测；本轮界面验证在本机 Apple Silicon 上完成。

| 包 | SHA-256 |
| --- | --- |

| arm64 CI ZIP | `f63835b2557059893732c64155c2af613f05838e31474d26bb7a139a5a1f80ac` |
| x86_64 CI ZIP | `4388236db35efe93e23b846bef76a3247b12fe73649ac3185b2dcf2602edd61f` |
| 本机 arm64 ZIP | `e0b2d0bbcce01860f51d448a19bf0f8c804238b8ab9f191ad9431f6c7c95ede6` |
