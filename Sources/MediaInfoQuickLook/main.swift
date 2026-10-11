import AppKit
import SwiftUI
import Carbon

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, ObservableObject {
    let model = AppModel()
    private var statusItem: NSStatusItem!
    private var window: NSWindow?
    private var settingsWindow: NSWindow?
    private var hotKey: GlobalHotKey?
    @Published var hotkeyStatus = ""
    @Published var hotkeyConflict = false
    @Published var enabled = UserDefaults.standard.object(forKey: "hotkeyEnabled") as? Bool ?? true
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupMainMenu()
        hotKey = GlobalHotKey { [weak self] in
            guard let self else { return }
            self.model.finder(); self.showWindow()
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "film.stack", accessibilityDescription: "MediaInfo QuickLook")
        configureHotkey(); rebuildMenu()
        if hotkeyConflict { showSettings() }
        if CommandLine.arguments.contains("--show") { showWindow() }
        if let index = CommandLine.arguments.firstIndex(of: "--open"), index + 1 < CommandLine.arguments.count {
            model.load(CommandLine.arguments.dropFirst(index + 1).map { URL(fileURLWithPath: $0) }); showWindow()
        }
    }
    func setupMainMenu() {
        let menu = NSMenu(); let appItem = NSMenuItem(); let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于 MediaInfo QuickLook", action: #selector(about), keyEquivalent: "")
        appMenu.addItem(withTitle: "设置…", action: #selector(showSettings), keyEquivalent: ",")
        appMenu.addItem(.separator()); appMenu.addItem(withTitle: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu; menu.addItem(appItem)
        let file = NSMenuItem(); file.title = "文件"; let fileMenu = NSMenu(title: "文件")
        fileMenu.addItem(withTitle: "打开文件…", action: #selector(openFiles), keyEquivalent: "o"); file.submenu = fileMenu; menu.addItem(file)
        let edit = NSMenuItem(); edit.title = "编辑"; let editMenu = NSMenu(title: "编辑")
        for (title, selector, key) in [("剪切", "cut:", "x"), ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
            editMenu.addItem(withTitle: title, action: Selector(selector), keyEquivalent: key)
        }
        edit.submenu = editMenu; menu.addItem(edit); NSApp.mainMenu = menu
    }
    func rebuildMenu() {
        let menu = NSMenu()
        let title = NSMenuItem(title: "MediaInfo QuickLook", action: nil, keyEquivalent: ""); menu.addItem(title)
        menu.addItem(withTitle: "打开窗口", action: #selector(showWindow), keyEquivalent: "")
        menu.addItem(withTitle: "打开文件…", action: #selector(openFiles), keyEquivalent: "")
        let toggle = NSMenuItem(title: enabled ? "停用快捷键 / 暂停增强预览" : "启用快捷键", action: #selector(toggleHotkey), keyEquivalent: ""); menu.addItem(toggle)
        menu.addItem(withTitle: "设置 / 自定义快捷键…", action: #selector(showSettings), keyEquivalent: "")
        if !hotkeyStatus.isEmpty { let item = NSMenuItem(title: hotkeyStatus, action: nil, keyEquivalent: ""); menu.addItem(item) }
        menu.addItem(.separator()); menu.addItem(withTitle: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) { item.target = self }
        statusItem.menu = menu
    }
    func configureHotkey() {
        hotKey?.unregister(); hotkeyConflict = false; UserDefaults.standard.set(enabled, forKey: "hotkeyEnabled")
        guard enabled else { hotkeyStatus = "快捷键已停用"; if statusItem != nil { rebuildMenu() }; return }
        let key = UInt32(UserDefaults.standard.object(forKey: "hotkeyCode") as? Int ?? 49)
        let modifiers = UInt32(UserDefaults.standard.object(forKey: "hotkeyModifiers") as? Int ?? Int(optionKey))
        do { try hotKey?.register(keyCode: key, modifiers: modifiers); hotkeyStatus = "快捷键已启用" }
        catch { hotkeyConflict = true; hotkeyStatus = error.localizedDescription; model.message = hotkeyStatus }
        if statusItem != nil { rebuildMenu() }
    }
    @objc func toggleHotkey() { enabled.toggle(); configureHotkey() }
    @objc func showWindow() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            w.title = "MediaInfo QuickLook"; w.contentView = NSHostingView(rootView: ContentView(model: model))
            w.isReleasedWhenClosed = false; w.delegate = self; w.center(); w.setFrameAutosaveName("MediaInfoMainWindow"); window = w
        }
        NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil)
    }
    @objc func openFiles() { showWindow(); model.openPanel() }
    @objc func showSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 470), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "MediaInfo QuickLook 设置"; w.contentView = NSHostingView(rootView: SettingsView(delegate: self))
            w.isReleasedWhenClosed = false; w.center(); settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true); settingsWindow?.makeKeyAndOrderFront(nil)
    }
    @objc func about() { NSApp.orderFrontStandardAboutPanel(nil) }
    func windowWillClose(_ notification: Notification) { if (notification.object as? NSWindow) === window { model.cancel(); model.previewID = nil } }
    func applicationWillTerminate(_ notification: Notification) { hotKey?.unregister(); model.cancel() }
    func application(_ sender: NSApplication, openFiles filenames: [String]) { model.load(filenames.map { URL(fileURLWithPath: $0) }); showWindow() }
}

struct SettingsView: View {
    @ObservedObject var delegate: AppDelegate
    @AppStorage("ffprobePath") private var path = ""
    @AppStorage("hotkeyCode") private var keyCode = 49
    @AppStorage("hotkeyModifiers") private var modifiers = 2048
    @AppStorage("concurrency") private var concurrency = 3
    @AppStorage("csvBOM") private var bom = true
    var body: some View {
        Form {
            Text("分析全部在本机完成，不上传素材。").font(.headline)
            HStack {
                TextField("ffprobe 路径", text: $path, prompt: Text("自动查找 Homebrew"))
                Button("选择…") {
                    let p = NSOpenPanel(); p.canChooseDirectories = false
                    if p.runModal() == .OK { path = p.url?.path ?? "" }
                }
            }
            Text("未安装时：brew install ffmpeg。也可选择可信来源的 ffprobe 可执行文件；应用不内置该依赖。").font(.caption).foregroundStyle(.secondary)
            Picker("并发分析", selection: $concurrency) { ForEach(2...4, id: \.self) { Text("\($0)").tag($0) } }
            HStack {
                Picker("修饰键", selection: $modifiers) {
                    Text("⌥ Option").tag(2048); Text("⌃⌥ Control Option").tag(6144); Text("⌘⌥ Command Option").tag(2304); Text("⌃⇧ Control Shift").tag(4608)
                }
                Picker("按键", selection: $keyCode) {
                    Text("Space").tag(49); Text("H").tag(4); Text("M").tag(46); Text("P").tag(35); Text("F6").tag(97); Text("F7").tag(98); Text("F8").tag(100)
                }
                Button("应用快捷键") { delegate.enabled = true; delegate.configureHotkey() }
            }
            Text(delegate.hotkeyStatus).font(.caption)
            Text("Option+Space 也是 Finder 全屏预览组合；若被系统保留或未生效，请改用 Control+Option+Space。").font(.caption).foregroundStyle(.secondary)
            Toggle("CSV 添加 UTF-8 BOM（Excel 中文兼容）", isOn: $bom)
            Button("清除元数据缓存", action: delegate.model.clearCache)
            Divider()
            Text("首次从 Finder 使用热键时，请允许控制 Finder。若拒绝：系统设置 → 隐私与安全性 → 自动化 → MediaInfo QuickLook → Finder。也可直接打开或拖放文件。").font(.callout)
            Button("打开自动化权限设置") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!) }
            Text("本工具不注册单独的 Space，也不接管系统 Quick Look。HDR 分类依据编码流标签；Sony/Nikon 私有 Log 曲线可能无法识别。").font(.caption).foregroundStyle(.secondary)
        }.padding(22).frame(width: 610)
    }
}
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
