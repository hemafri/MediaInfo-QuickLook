// Compile with the production GlobalHotKey.swift and FinderSelection.swift; see docs/PLATFORM-VERIFICATION.md.
import AppKit
import Carbon

@main
struct PlatformProbe {
    @MainActor
    static func main() {
        _ = NSApplication.shared
        let hotKey = GlobalHotKey { print("HOTKEY_EVENT_RECEIVED") }
        do {
            try hotKey.register()
            print("PASS: Option+Space registration")
            hotKey.unregister()
            try hotKey.register()
            print("PASS: unregister and re-register")
            hotKey.unregister()
            if CommandLine.arguments.contains("--finder") {
                print("Switch to Finder and select files within 5 seconds; the probe does not change the selection.")
                RunLoop.main.run(until: Date().addingTimeInterval(5))
                let urls = try FinderSelection.selectedURLs()
                print("PASS: Finder returned \(urls.count) URLs")
                for url in urls { print(url.absoluteString) }
            }
            if CommandLine.arguments.contains("--listen") {
                try hotKey.register()
                print("Listening for Option+Space for 15 seconds; normal Space is not registered.")
                RunLoop.main.run(until: Date().addingTimeInterval(15))
                hotKey.unregister()
            }
        } catch {
            fputs("FAIL: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
