import AppKit
import Carbon

@main struct HotkeyConflictCheck {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let modifiers = UInt32(optionKey | controlKey | cmdKey | shiftKey)
        if CommandLine.arguments.contains("--holder") {
            var ref: EventHotKeyRef?
            let result = RegisterEventHotKey(100, modifiers, EventHotKeyID(signature: 0x54455354, id: 1), GetApplicationEventTarget(), UInt32(kEventHotKeyExclusive), &ref)
            guard result == noErr else { exit(2) }
            print("READY"); fflush(stdout)
            RunLoop.main.run(until: Date().addingTimeInterval(5))
            if let ref { UnregisterEventHotKey(ref) }
            return
        }
        let holder = Process(); let pipe = Pipe()
        holder.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]); holder.arguments = ["--holder"]; holder.standardOutput = pipe
        try holder.run()
        defer { if holder.isRunning { holder.terminate() }; holder.waitUntilExit() }
        guard String(data: pipe.fileHandleForReading.readData(ofLength: 6), encoding: .utf8) == "READY\n" else { exit(3) }
        let hotkey = GlobalHotKey {}
        do {
            try hotkey.register(keyCode: 100, modifiers: modifiers)
            hotkey.unregister()
            print("FAIL: registration silently succeeded while another process exclusively owns shortcut")
            exit(1)
        } catch HotKeyError.registrationFailed { print("PASS: exclusive conflict is reported") }
        do { try hotkey.register(keyCode: 49, modifiers: 0); exit(4) }
        catch HotKeyError.modifierRequired { print("PASS: bare Space cannot be registered") }
    }
}
