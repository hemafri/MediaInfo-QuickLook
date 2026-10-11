import AppKit
import Carbon

public enum HotKeyError: LocalizedError {
    case registrationFailed(OSStatus)
    case eventHandlerFailed(OSStatus)
    case modifierRequired

    public var errorDescription: String? {
        switch self {
        case .registrationFailed(let status):
            return "无法注册全局快捷键（系统错误 \(status)）。该组合可能已被系统或其他应用占用，请在设置中选择其他快捷键。"
        case .eventHandlerFailed(let status):
            return "无法安装快捷键处理程序（系统错误 \(status)）。请重新启动应用，或使用菜单中的‘打开文件…’。"
        case .modifierRequired:
            return "请至少使用 Option、Control 或 Command 修饰键；普通空格保留给系统 Quick Look。"
        }
    }
}

@MainActor
final class GlobalHotKey {
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let handler: () -> Void
    private let signature: OSType = 0x4D49514C // MIQL

    init(handler: @escaping () -> Void) {
        self.handler = handler
    }

    func register(keyCode: UInt32 = 49, modifiers: UInt32 = 2048) throws {
        guard modifiers & UInt32(optionKey | controlKey | cmdKey) != 0 else {
            throw HotKeyError.modifierRequired
        }
        unregister()
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installStatus = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let context, let event else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard status == noErr, identifier.signature == 0x4D49514C, identifier.id == 1 else {
                return OSStatus(eventNotHandledErr)
            }
            let owner = Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { [weak owner] in
                guard let owner, owner.hotKey != nil else { return }
                owner.handler()
            }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        guard installStatus == noErr else {
            unregister()
            throw HotKeyError.eventHandlerFailed(installStatus)
        }
        let status = RegisterEventHotKey(keyCode, modifiers, EventHotKeyID(signature: signature, id: 1), GetApplicationEventTarget(), UInt32(kEventHotKeyExclusive), &hotKey)
        guard status == noErr else {
            unregister()
            throw HotKeyError.registrationFailed(status)
        }
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        if let eventHandler { RemoveEventHandler(eventHandler) }
        eventHandler = nil
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}
