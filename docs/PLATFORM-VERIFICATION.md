# macOS integration verification

Verified on the development Mac on 2026-10-11. These checks do not constitute the complete stage-0 acceptance gate in HANDOFF.md.

## Checks actually run

The production `GlobalHotKey.swift` and `FinderSelection.swift` compiled together with the probe in Swift 5 language mode, targeting macOS 13 on Apple Silicon:

```sh
swiftc -swift-version 5 -target arm64-apple-macosx13.0 \
  Sources/MediaInfoQuickLook/GlobalHotKey.swift \
  Sources/MediaInfoQuickLook/FinderSelection.swift \
  scripts/platform-probe.swift -o /tmp/mediainfo-platform-probe
/tmp/mediainfo-platform-probe
plutil -lint Resources/Info.plist Resources/MediaInfoQuickLook.entitlements
```

Observed output:

```text
PASS: Option+Space registration
PASS: unregister and re-register
Resources/Info.plist: OK
Resources/MediaInfoQuickLook.entitlements: OK
```

This demonstrates successful Carbon registration and re-registration after releasing the combination in this environment. It does not demonstrate delivery of a physical keypress or absence of conflicts on another Mac. `unregister()` invokes Carbon cleanup; the re-registration is its practical check. Intel compilation and operation on macOS 13 itself were not tested.

The full `scripts/check.sh` subsequently passed on this development Mac. It runs the Swift package build, standalone core checks, generated-media integration checks, application-model checks, the two-process hotkey conflict check, and plist validation. These successful checks do not replace the outstanding interactive acceptance cases below.

`scripts/hotkey-conflict-check.swift` starts a separate process that exclusively holds a test shortcut and verifies that production registration reports a conflict. The initial nonexclusive production registration incorrectly succeeded in this test. Changing registration to pass `UInt32(kEventHotKeyExclusive)` fixed the failure; the conflict check and bare-Space rejection both now pass. This is a real cross-process conflict test, not a mocked return code.

The generated Xcode project passed plist syntax, object/source-reference, shared-scheme XML, and deterministic-regeneration checks. `xcodebuild -list -project MediaInfoQuickLook.xcodeproj` was attempted but failed because the active developer directory is `/Library/Developer/CommandLineTools`, not a full Xcode installation. Xcode app builds and its XCTest scheme remain unverified.

## Interactive observations

- Computer-use automation sent ordinary Space in Finder while the application was running and confirmed the system's native Quick Look. The disabled-shortcut and quit-state variants have not yet been checked.
- The single-file HLG application UI successfully displayed and played the sample through `NativePlayerView`, the native AVPlayer view wrapper. The earlier SwiftUI `VideoPlayer` crashed at runtime while demangling a superclass in this older-SDK/newer-OS environment; replacing that wrapper resolved the observed playback crash. Successful playback does not establish correct HDR display output or Sony/Nikon camera compatibility.
- A synthetic Option+Space sent through computer-use automation entered native full-screen Quick Look. Synthetic input is not evidence of physical global-hotkey delivery, so this does not establish whether the application's physical Option+Space callback works. A physical-keyboard test has been requested from the user and remains pending. Finder selection and TCC permission flows also remain unverified.

## Implementation facts

- The application uses Carbon `RegisterEventHotKey` with `UInt32(kEventHotKeyExclusive)`, not an event tap or keyboard interception. Plain Space registration is rejected; a shortcut needs Option, Control, or Command. Default key code 49 with modifier 2048 is Option+Space.
- Registration failure reports the OSStatus and suggests changing a possibly occupied combination. Failure is not proof that a conflict is its cause.
- Finder must be frontmost before and after the AppleScript call. The script also checks Finder's frontmost state before inspecting `selection`. Empty selection and automation denial have distinct actionable messages with an open-file fallback.
- Finder returns a structured Apple-event list of POSIX paths. No shell command or string delimiter is used, so newlines, spaces, and non-ASCII characters in names are preserved. The array preserves Finder's returned order; click-selection order is not guaranteed.
- File type and folder filtering belong to the application ingestion layer, not the Finder transport.
- The entitlement enables Apple Events under hardened runtime. App Sandbox is deliberately not enabled. This permits the separately implemented external ffprobe process; entitlement presence alone does not prove signed-distribution compatibility.

## Remaining interactive checks

After compiling the probe, `/tmp/mediainfo-platform-probe --listen` listens for 15 seconds. Physically press Option+Space and expect `HOTKEY_EVENT_RECEIVED`. The probe does not synthesize keystrokes.

`/tmp/mediainfo-platform-probe --finder` waits five seconds for you to bring Finder forward and select files, then prints the returned file URLs. It never changes Finder selection. Test single and multiple selection, filenames containing Chinese, spaces and newlines, folders, no selection, and switching to another application. Use only non-sensitive sample names if retaining output logs.

The bare command-line probe has a different TCC identity from the final app. Test first grant, denial, and re-enabling Automation permission using the built `.app` with its usage description, entitlements, and final signing identity. Granting the probe access is not evidence the app has access.

Still pending acceptance:

- Finder real selection reading and first-run, denied, restored Automation permissions.
- Physical hotkey event delivery and configured alternative shortcuts. Deliberate exclusive registration conflict is now covered by the passing two-process check.
- System Quick Look with ordinary Space after closing the enhanced preview, after disabling the shortcut, and after quitting. The app-running observation above covers only that state.
- HDR display accuracy, real Sony/Nikon camera samples, and the full Developer ID signed/notarized release. Local ffprobe integration checks and the observed AVPlayer sample playback are narrower evidence.
- Full Xcode builds and XCTest execution using the generated shared scheme.

Stage 0 remains incomplete until real Finder selection, the Automation permission lifecycle, and physical shortcut activation are verified. Later-stage implementation and passing automated checks do not waive that acceptance gate.

Do not reset TCC or alter the user's Finder selection to automate these checks. Use the application's open-file or drag-and-drop entry point when Finder automation is unavailable.

## Later live UI observations

After the user unlocked the desktop, Release GUI checks passed for PQ filtering, frame-rate sorting, double-click preview, Escape back to the table, selection/filter preservation, and horizontal scroll restoration (0.92206 before/after). A real save-panel CSV export was read back and contained BOM, header, and exactly the selected filter's one PQ record.

The user identified Codex as the Option+Space conflict and explicitly requested changing Codex, preserving this application's default. The computer-control tool refuses access to Codex itself for safety reasons. Official manual shortcut-setting steps were provided; no alternate preference/file route was used to bypass that refusal. Physical Finder hotkey/TCC acceptance remains pending that external change.
