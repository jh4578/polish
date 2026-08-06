import AppKit

/// A small window that records a new hotkey: press the desired combination,
/// Esc cancels. The captured combo is persisted and reported via `onChange`.
final class HotKeyRecorderController: NSObject, NSWindowDelegate {
    static let shared = HotKeyRecorderController()

    private var window: NSWindow?
    private var monitor: Any?
    private var comboLabel: NSTextField!
    private var hintLabel: NSTextField!
    private var onChange: ((HotKeyConfig) -> Void)?

    func show(onChange: @escaping (HotKeyConfig) -> Void) {
        self.onChange = onChange

        if window == nil {
            buildWindow()
        }
        comboLabel.stringValue = HotKeyConfig.current.displayString
        hintLabel.stringValue = "按下新的快捷键组合（Esc 取消）"
        hintLabel.textColor = .secondaryLabelColor

        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        startMonitor()
    }

    private func buildWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 130),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "更改快捷键"
        window.isReleasedWhenClosed = false
        window.delegate = self

        comboLabel = NSTextField(labelWithString: "")
        comboLabel.font = .monospacedSystemFont(ofSize: 28, weight: .medium)
        comboLabel.alignment = .center

        hintLabel = NSTextField(labelWithString: "")
        hintLabel.font = .systemFont(ofSize: 12)
        hintLabel.alignment = .center

        let stack = NSStackView(views: [comboLabel, hintLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])
        window.contentView = content
        self.window = window
    }

    private func startMonitor() {
        stopMonitor()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }

            // Esc with no modifiers cancels.
            let mods = HotKeyConfig.carbonModifiers(from: event.modifierFlags)
            if event.keyCode == 53 && mods == 0 {
                self.window?.close()
                return nil
            }

            // Require at least one of ⌘ / ⌥ / ⌃ so plain typing can't be captured.
            let hasRealModifier = event.modifierFlags.contains(.command)
                || event.modifierFlags.contains(.option)
                || event.modifierFlags.contains(.control)
            guard hasRealModifier else {
                self.hintLabel.stringValue = "需包含 ⌘、⌥ 或 ⌃ 中至少一个"
                self.hintLabel.textColor = .systemRed
                return nil
            }

            let config = HotKeyConfig(keyCode: UInt32(event.keyCode), carbonModifiers: mods)
            HotKeyConfig.current = config
            self.comboLabel.stringValue = config.displayString
            self.onChange?(config)
            self.window?.close()
            return nil
        }
    }

    private func stopMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    func windowWillClose(_ notification: Notification) {
        stopMonitor()
    }
}
