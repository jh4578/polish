import AppKit
import Carbon
import ApplicationServices

/// Simulates keystrokes and moves text through the clipboard.
/// Requires Accessibility permission (System Settings → Privacy & Security → Accessibility).
enum TextCapture {

    enum Selection {
        case text(String)   // a non-empty selection was read
        case none           // AX confirms the focused element has no selection
        case unknown        // AX can't read this app — caller should fall back to ⌘C
    }

    /// Reads the selection via Accessibility, distinguishing "empty selection"
    /// (fast path, no fallback needed) from "attribute unsupported" — the latter
    /// happens in Chrome/Electron/WeChat and needs a clipboard fallback.
    static func selectionViaAX() -> Selection {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused else { return .unknown }
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element as! AXUIElement, kAXSelectedTextAttribute as CFString, &value)
        if err == .success, let text = value as? String {
            return text.isEmpty ? .none : .text(text)
        }
        return .unknown
    }

    static func sendKeyCombo(_ keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        down?.flags = flags
        down?.post(tap: .cghidEventTap)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        up?.flags = flags
        up?.post(tap: .cghidEventTap)
    }

    static func copy()  { sendKeyCombo(CGKeyCode(kVK_ANSI_C), flags: .maskCommand) }
    static func paste() { sendKeyCombo(CGKeyCode(kVK_ANSI_V), flags: .maskCommand) }
    static func undo()  { sendKeyCombo(CGKeyCode(kVK_ANSI_Z), flags: .maskCommand) }

    /// Snapshot of clipboard contents so it can be restored later.
    static func snapshotClipboard() -> [NSPasteboardItem] {
        (NSPasteboard.general.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }
    }

    static func restoreClipboard(_ items: [NSPasteboardItem]) {
        let pb = NSPasteboard.general
        pb.clearContents()
        if !items.isEmpty {
            pb.writeObjects(items)
        }
    }

    /// Simulates ⌘C and waits for the clipboard to change; returns the selected text (nil if no selection).
    static func captureSelection(timeout: TimeInterval = 1.5, completion: @escaping (String?) -> Void) {
        let pb = NSPasteboard.general
        let startCount = pb.changeCount

        // Small delay so the hotkey's own modifiers are released before ⌘C goes out.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            copy()

            let deadline = Date().addingTimeInterval(timeout)
            func poll() {
                if pb.changeCount != startCount {
                    completion(pb.string(forType: .string))
                } else if Date() > deadline {
                    completion(nil)
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { poll() }
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { poll() }
        }
    }

    /// Puts text on the clipboard and simulates ⌘V into the frontmost app.
    static func pasteText(_ text: String, into app: NSRunningApplication?, completion: @escaping () -> Void) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)

        app?.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            paste()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { completion() }
        }
    }
}
