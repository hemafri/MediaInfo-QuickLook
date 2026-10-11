import AppKit
import Carbon

enum FinderSelectionError: LocalizedError {
    case finderNotFrontmost
    case noSelection
    case automationDenied
    case scriptFailed(String)
    case invalidResult

    var errorDescription: String? {
        switch self {
        case .finderNotFrontmost:
            return "请先在 Finder 中选中视频并保持 Finder 位于前台，再按快捷键。也可以使用‘打开文件…’或拖入视频。"
        case .noSelection:
            return "Finder 中没有选中文件。请先选中视频，或使用‘打开文件…’。"
        case .automationDenied:
            return "未获得 Finder 自动化权限。请在‘系统设置 → 隐私与安全性 → 自动化’中允许 MediaInfo QuickLook 控制 Finder，然后重试。也可以直接使用‘打开文件…’或拖入视频，无需此权限。"
        case .scriptFailed(let message):
            return "读取 Finder 选择失败：\(message)。可以改用‘打开文件…’或拖入视频。"
        case .invalidResult:
            return "Finder 返回的文件路径无法解析，请重新选择文件，或使用‘打开文件…’。"
        }
    }
}

@MainActor
enum FinderSelection {
    /// Preserves the order returned by Finder; Finder does not promise click-selection order.
    static func selectedURLs() throws -> [URL] {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" else {
            throw FinderSelectionError.finderNotFrontmost
        }
        // Return an Apple-event list, never a joined string: filenames may contain newlines.
        let source = """
        tell application "Finder"
            if not frontmost then error "Finder is no longer frontmost" number -2700
            set selectedItems to selection
            set selectedPaths to {}
            repeat with selectedItem in selectedItems
                set end of selectedPaths to POSIX path of (selectedItem as alias)
            end repeat
            return selectedPaths
        end tell
        """
        guard let script = NSAppleScript(source: source) else {
            throw FinderSelectionError.invalidResult
        }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            let number = (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue
            if number == -1743 { throw FinderSelectionError.automationDenied }
            if number == -2700 { throw FinderSelectionError.finderNotFrontmost }
            throw FinderSelectionError.scriptFailed(error[NSAppleScript.errorMessage] as? String ?? "未知 Apple Events 错误 \(number ?? 0)")
        }
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" else {
            throw FinderSelectionError.finderNotFrontmost
        }
        guard result.descriptorType == typeAEList else { throw FinderSelectionError.invalidResult }
        guard result.numberOfItems > 0 else { throw FinderSelectionError.noSelection }
        return try (1...result.numberOfItems).map { index in
            guard let path = result.atIndex(index)?.stringValue, path.hasPrefix("/"), !path.contains("\0") else {
                throw FinderSelectionError.invalidResult
            }
            return URL(fileURLWithPath: path)
        }
    }
}
