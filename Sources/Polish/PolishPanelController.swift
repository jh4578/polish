import AppKit

/// Borderless panels can't become key by default; this one can, so the
/// input field receives typing without activating our app.
private final class InputPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// A minimal floating input box: appears near the mouse on hotkey press,
/// takes an instruction (Enter alone = polish), calls Codex, and pastes the
/// result over the original selection. Stays open for follow-up instructions.
final class PolishPanelController: NSObject, NSTextFieldDelegate {

    private var panel: NSPanel?
    private var inputField: NSTextField!

    private var targetApp: NSRunningApplication?
    private var savedClipboard: [NSPasteboardItem] = []
    private var currentText: String = ""       // latest version of the text being worked on
    private var hasPastedOnce = false
    private var isGenerating = false

    // MARK: - Entry point

    func trigger() {
        if panel != nil {
            closePanel()
            return
        }

        guard AXIsProcessTrusted() else {
            showAccessibilityAlert()
            return
        }

        targetApp = NSWorkspace.shared.frontmostApplication
        savedClipboard = TextCapture.snapshotClipboard()
        hasPastedOnce = false

        // Read the current selection. AX is instant when the app supports it;
        // otherwise fall back to a short ⌘C capture so instant mode still works
        // in apps that don't expose selection to Accessibility (Chrome, WeChat…).
        switch TextCapture.selectionViaAX() {
        case .text(let s):
            currentText = s.trimmingCharacters(in: .newlines)
            proceed()
        case .none:
            currentText = ""
            proceed()
        case .unknown:
            TextCapture.captureSelection(timeout: 0.4) { [weak self] sel in
                guard let self else { return }
                self.currentText = sel?.trimmingCharacters(in: .newlines) ?? ""
                self.proceed()
            }
        }
    }

    /// Routes to instant polish or the panel based on selection + settings.
    private func proceed() {
        // Instant mode only applies when there's a selection to polish directly.
        // With nothing selected, always show the panel so the user can type.
        if !Settings.showPanel && !currentText.isEmpty {
            instantPolish()
        } else {
            showPanel()
        }
    }

    private func showAccessibilityAlert() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "需要辅助功能权限"
        alert.informativeText = """
        Polish 需要辅助功能权限才能读取选中文字和自动替换。

        请在 系统设置 → 隐私与安全性 → 辅助功能 中勾选 Polish。
        如果列表里已有 Polish 但仍不工作，请先取消勾选再重新勾选（或用 − 删除后重新添加 /Applications/Polish.app）。
        """
        alert.addButton(withTitle: "打开设置")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Instant mode (panel disabled in Settings)

    private func instantPolish() {
        guard !currentText.isEmpty else {
            ProgressHUD.shared.show("未检测到选中文字", spinning: false)
            ProgressHUD.shared.dismiss(after: 1.5)
            TextCapture.restoreClipboard(savedClipboard)
            savedClipboard = []
            return
        }

        ProgressHUD.shared.show("润色中…", spinning: true)
        CodexClient.shared.rewrite(instruction: Settings.polishInstruction,
                                   text: currentText, threadId: nil) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let reply):
                TextCapture.pasteText(reply.text, into: self.targetApp) { [weak self] in
                    guard let self else { return }
                    ProgressHUD.shared.show("已替换 ✓", spinning: false)
                    ProgressHUD.shared.dismiss(after: 1.2)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        TextCapture.restoreClipboard(self.savedClipboard)
                        self.savedClipboard = []
                    }
                }
            case .failure(let error):
                ProgressHUD.shared.show("出错：\(error.localizedDescription)", spinning: false)
                ProgressHUD.shared.dismiss(after: 3)
                TextCapture.restoreClipboard(self.savedClipboard)
                self.savedClipboard = []
            }
        }
    }

    // MARK: - Panel UI (a single input box, nothing else)

    private func showPanel() {
        let width: CGFloat = 420

        let panel = InputPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 52),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.applyLightAppearance()

        // Wispr-style rounded light-glass pill with a soft rim and shadow.
        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 16
        effect.layer?.borderWidth = 1
        effect.layer?.borderColor = Brand.rim.cgColor
        panel.contentView = effect

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold))
        icon.contentTintColor = Brand.iconTint
        icon.translatesAutoresizingMaskIntoConstraints = false

        inputField = NSTextField()
        inputField.placeholderString = placeholderForIdle()
        inputField.font = .systemFont(ofSize: 15)
        inputField.isBordered = false
        inputField.drawsBackground = false
        inputField.focusRingType = .none
        inputField.delegate = self
        inputField.target = self
        inputField.action = #selector(submit)
        inputField.translatesAutoresizingMaskIntoConstraints = false

        effect.addSubview(icon)
        effect.addSubview(inputField)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 16),
            icon.centerYAnchor.constraint(equalTo: effect.centerYAnchor),
            inputField.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            inputField.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -16),
            inputField.centerYAnchor.constraint(equalTo: effect.centerYAnchor),
        ])

        position(panel, width: width)
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(inputField)
    }

    private func placeholderForIdle() -> String {
        if currentText.isEmpty && !hasPastedOnce {
            return L("输入文字，回车润色", "Type text, Enter to polish")   // nothing selected
        }
        return hasPastedOnce
            ? L("继续输入要求修改，或按 Esc 关闭", "Refine further, or Esc to close")
            : L("回车润色，或输入要求", "Enter to polish, or type an instruction")
    }

    /// Below the mouse so the box doesn't cover the selected line;
    /// flips above when too close to the bottom of the screen.
    private func position(_ panel: NSPanel, width: CGFloat) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let height = panel.frame.height

        var origin = NSPoint(x: mouse.x - width / 2, y: mouse.y - 70 - height)
        if let visible = screen?.visibleFrame {
            if origin.y < visible.minY + 8 {
                origin.y = mouse.y + 70
            }
            origin.x = max(visible.minX + 8, min(origin.x, visible.maxX - width - 8))
            origin.y = min(origin.y, visible.maxY - height - 8)
        }
        panel.setFrameOrigin(origin)
    }

    // MARK: - Generate & paste

    @objc private func submit() {
        guard !isGenerating else { return }
        let input = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        // What to polish, and how:
        // - Nothing selected, first round → the typed text IS the content to polish.
        // - Has a selection, or any follow-up round → the typed text is an instruction
        //   applied to the current text (empty = default polish).
        let textToPolish: String
        let instruction: String?
        let typeMode: Bool     // nothing was selected: paste result then close (one step)
        if currentText.isEmpty && !hasPastedOnce {
            guard !input.isEmpty else { return }   // nothing typed yet — ignore Enter
            textToPolish = input
            instruction = nil
            typeMode = true
        } else {
            textToPolish = currentText
            instruction = input.isEmpty ? nil : input
            typeMode = false
        }

        isGenerating = true
        inputField.isEnabled = false
        inputField.stringValue = ""
        inputField.placeholderString = L("生成中…", "Working…")

        CodexClient.shared.rewrite(instruction: instruction,
                                   text: textToPolish,
                                   threadId: nil) { [weak self] result in
            guard let self, self.panel != nil else { return }
            self.isGenerating = false
            self.inputField.isEnabled = true

            switch result {
            case .success(let reply):
                self.pasteResult(reply.text, closeAfter: typeMode)
            case .failure(let error):
                self.inputField.placeholderString = L("出错：", "Error: ") + error.localizedDescription
                self.panel?.makeFirstResponder(self.inputField)
            }
        }
    }

    private func pasteResult(_ output: String, closeAfter: Bool) {
        guard let panel else { return }

        // The panel owns keyboard focus; hide it so ⌘V reaches the target app.
        panel.orderOut(nil)

        let doPaste = { [weak self] in
            guard let self else { return }
            TextCapture.pasteText(output, into: self.targetApp) { [weak self] in
                guard let self else { return }
                if closeAfter {
                    self.closePanel()   // type-mode: done in one step
                    return
                }
                guard let panel = self.panel else { return }
                self.currentText = output
                self.hasPastedOnce = true
                self.inputField.stringValue = ""
                self.inputField.placeholderString = self.placeholderForIdle()
                panel.makeKeyAndOrderFront(nil)
                panel.makeFirstResponder(self.inputField)
            }
        }

        if hasPastedOnce {
            // Follow-up round: undo the previous paste (restores & reselects the old
            // text in most apps), then paste the new version over it.
            targetApp?.activate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                TextCapture.undo()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: doPaste)
            }
        } else {
            doPaste()
        }
    }

    // MARK: - Close / Esc

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            closePanel()
            return true
        }
        return false
    }

    private func closePanel() {
        panel?.orderOut(nil)
        panel = nil

        // Give the clipboard back to the user unless generation is mid-flight.
        if !isGenerating {
            TextCapture.restoreClipboard(savedClipboard)
            savedClipboard = []
        }
        targetApp?.activate()
        targetApp = nil
    }
}
