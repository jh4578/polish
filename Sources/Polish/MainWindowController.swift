import AppKit
import ServiceManagement

/// NSTextView with a greyed-out placeholder when empty.
final class PlaceholderTextView: NSTextView {
    var placeholderString: String = "" { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholderString.isEmpty else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.placeholderTextColor,
            .font: font ?? .systemFont(ofSize: 13),
        ]
        placeholderString.draw(at: NSPoint(x: textContainerInset.width + 5,
                                           y: textContainerInset.height), withAttributes: attrs)
    }
    override func didChangeText() { super.didChangeText(); needsDisplay = true }
}

/// The app's visible main window, styled after Wispr Flow: dark-first, rounded
/// cards, electric-cyan accent. Built-in try-it box (polish / translate), status
/// card, settings. Opened on launch and on Dock-icon click; closing it leaves the
/// app running in the menu bar.
final class MainWindowController: NSObject, NSWindowDelegate {
    static let shared = MainWindowController()

    static let translateInstruction =
        "Translate the text: if it is mainly Chinese, render it as natural, idiomatic English; " +
        "otherwise render it as natural, idiomatic Chinese. Output ONLY the translation."

    private let winWidth: CGFloat = 500

    private var window: NSWindow?
    private var statusStack: NSStackView!
    private var inputView: PlaceholderTextView!
    private var outputView: PlaceholderTextView!
    private var polishButton: NSButton!
    private var translateButton: NSButton!
    private var copyButton: NSButton!
    private var launchCheckbox: NSButton!
    private var isBusy = false

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(languageChanged),
                                               name: .languageChanged, object: nil)
    }

    func show() {
        if window == nil { build() }
        refreshStatus()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    @objc private func languageChanged() {
        guard window != nil else { return }
        build()          // rebuild content with new strings
        refreshStatus()
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Build

    private func build() {
        let window = self.window ?? NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: winWidth, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "Polish"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.applyLightAppearance()
        if self.window == nil { window.center() }

        let bg = NSView()
        bg.wantsLayer = true
        bg.layer?.backgroundColor = Brand.windowFill.cgColor

        let stack = NSStackView(views: [
            headerView(),
            statusCard(),
            sectionLabel(L("试一下", "Try it")),
            inputCard(),
            actionRow(),
            outputCard(),
            separatorLine(),
            footerRow(),
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.setCustomSpacing(20, after: stack.arrangedSubviews[0])
        stack.setCustomSpacing(8, after: stack.arrangedSubviews[2])
        stack.edgeInsets = NSEdgeInsets(top: 40, left: 26, bottom: 24, right: 26)
        stack.translatesAutoresizingMaskIntoConstraints = false

        bg.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: bg.topAnchor),
            stack.leadingAnchor.constraint(equalTo: bg.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: bg.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bg.bottomAnchor),
        ])
        window.contentView = bg
        self.window = window
    }

    // MARK: - Sections

    private func headerView() -> NSView {
        let cfg = NSImage.SymbolConfiguration(pointSize: 30, weight: .semibold)
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg)
        icon.contentTintColor = Brand.iconTint

        let title = NSTextField(labelWithString: "Polish")
        title.font = .systemFont(ofSize: 28, weight: .bold)

        let col = NSStackView(views: [title,
            caption(L("选中文字，按快捷键即可润色", "Select text, press the hotkey to polish"))])
        col.orientation = .vertical
        col.alignment = .leading
        col.spacing = 2

        let row = NSStackView(views: [icon, col])
        row.orientation = .horizontal
        row.spacing = 12
        row.alignment = .centerY
        return row
    }

    private func statusCard() -> NSView {
        statusStack = NSStackView()
        statusStack.orientation = .vertical
        statusStack.alignment = .leading
        statusStack.spacing = 9
        return card(statusStack, padding: 15)
    }

    private func inputCard() -> NSView {
        inputView = makeTextView(placeholder: L("在这里输入或粘贴文字…", "Type or paste text here…"))
        return scrollCard(inputView, height: 82)
    }

    private func outputCard() -> NSView {
        outputView = makeTextView(placeholder: L("结果会显示在这里", "The result appears here"))
        outputView.isEditable = false
        return scrollCard(outputView, height: 96)
    }

    private func actionRow() -> NSView {
        polishButton = accentButton(title: L("润色", "Polish"), symbol: "wand.and.stars", action: #selector(doPolish))
        translateButton = pillButton(title: L("中↔英", "中↔EN"), symbol: "character.book.closed", action: #selector(doTranslate))
        copyButton = pillButton(title: L("复制结果", "Copy"), symbol: "doc.on.doc", action: #selector(copyOutput))

        let row = NSStackView(views: [polishButton, translateButton, NSView(), copyButton])
        row.orientation = .horizontal
        row.spacing = 8
        return row
    }

    private func footerRow() -> NSView {
        let settingsButton = pillButton(title: L("设置…", "Settings…"), symbol: "gearshape", action: #selector(openSettings))
        launchCheckbox = NSButton(checkboxWithTitle: L("开机自动启动", "Launch at login"),
                                  target: self, action: #selector(toggleLaunch))
        let row = NSStackView(views: [settingsButton, NSView(), launchCheckbox])
        row.orientation = .horizontal
        row.spacing = 12
        return row
    }

    // MARK: - Status

    private func refreshStatus() {
        statusStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let ax = AXIsProcessTrusted()
        statusStack.addArrangedSubview(statusRow(L("辅助功能", "Accessibility"),
            ax ? L("已授权", "Granted") : L("未授权（读取选中文字必需）", "Not granted (required)"),
            ok: ax, action: ax ? nil : #selector(openAccessibility), actionTitle: L("去授权", "Grant")))

        let loggedIn = CodexAuth.isLoggedIn
        statusStack.addArrangedSubview(statusRow(L("Codex 登录", "Codex login"),
            loggedIn ? L("已登录 · ChatGPT 订阅", "Signed in · ChatGPT") : L("未登录", "Not signed in"), ok: loggedIn))

        statusStack.addArrangedSubview(statusRow(L("快捷键", "Hotkey"), HotKeyConfig.current.displayString, ok: true))

        let modelLabel = Settings.modelOptions.first { $0.id == Settings.model }?.id ?? Settings.model
        statusStack.addArrangedSubview(statusRow(L("模型", "Model"), modelLabel, ok: true))

        launchCheckbox.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
    }

    private func statusRow(_ name: String, _ value: String, ok: Bool,
                           action: Selector? = nil, actionTitle: String = "") -> NSView {
        let dot = NSTextField(labelWithString: "●")
        dot.textColor = ok ? Brand.okDot : Brand.warnDot
        dot.font = .systemFont(ofSize: 9)

        let nameLabel = NSTextField(labelWithString: name)
        nameLabel.font = .systemFont(ofSize: 12)
        nameLabel.textColor = .secondaryLabelColor
        nameLabel.widthAnchor.constraint(equalToConstant: 96).isActive = true

        let valueLabel = NSTextField(labelWithString: value)
        valueLabel.font = .systemFont(ofSize: 12, weight: .medium)
        valueLabel.lineBreakMode = .byTruncatingTail

        let row = NSStackView(views: [dot, nameLabel, valueLabel])
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY

        if let action {
            let fix = NSButton(title: actionTitle, target: self, action: action)
            fix.bezelStyle = .inline
            fix.controlSize = .small
            row.addArrangedSubview(fix)
        }
        return row
    }

    // MARK: - Actions

    @objc private func doPolish() { run(instruction: nil, busy: L("润色中…", "Polishing…")) }
    @objc private func doTranslate() { run(instruction: Self.translateInstruction, busy: L("翻译中…", "Translating…")) }

    private func run(instruction: String?, busy: String) {
        guard !isBusy else { return }
        let text = inputView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { outputView.string = L("先在上面输入一些文字。", "Type something above first."); return }

        isBusy = true
        polishButton.isEnabled = false
        translateButton.isEnabled = false
        let saved = polishButton.title
        polishButton.title = busy
        outputView.string = ""

        CodexClient.shared.rewrite(instruction: instruction, text: text, threadId: nil) { [weak self] result in
            guard let self else { return }
            self.isBusy = false
            self.polishButton.isEnabled = true
            self.translateButton.isEnabled = true
            self.polishButton.title = saved
            switch result {
            case .success(let reply): self.outputView.string = reply.text
            case .failure(let error): self.outputView.string = L("出错：", "Error: ") + error.localizedDescription
            }
        }
    }

    @objc private func copyOutput() {
        let text = outputView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc private func openSettings() { SettingsWindowController.shared.show() }

    @objc private func openAccessibility() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func toggleLaunch() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            let alert = NSAlert()
            alert.messageText = L("设置开机启动失败", "Couldn't set login item")
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        refreshStatus()
    }

    func windowDidBecomeKey(_ notification: Notification) { refreshStatus() }

    // MARK: - Reusable UI

    private func caption(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: 11.5)
        l.textColor = .secondaryLabelColor
        return l
    }

    private func sectionLabel(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text.uppercased())
        l.font = .systemFont(ofSize: 11, weight: .semibold)
        l.textColor = .tertiaryLabelColor
        return l
    }

    private func makeTextView(placeholder: String) -> PlaceholderTextView {
        let tv = PlaceholderTextView()
        tv.placeholderString = placeholder
        tv.font = .systemFont(ofSize: 13)
        tv.isRichText = false
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 6, height: 8)
        tv.autoresizingMask = [.width]
        return tv
    }

    private func roundedBox() -> NSView {
        let box = NSView()
        box.wantsLayer = true
        box.layer?.backgroundColor = Brand.cardFill.cgColor
        box.layer?.cornerRadius = 14
        box.layer?.borderWidth = 1
        box.layer?.borderColor = Brand.rim.cgColor
        return box
    }

    private func card(_ inner: NSView, padding: CGFloat) -> NSView {
        let box = roundedBox()
        inner.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(inner)
        NSLayoutConstraint.activate([
            box.widthAnchor.constraint(equalToConstant: winWidth - 52),
            inner.topAnchor.constraint(equalTo: box.topAnchor, constant: padding),
            inner.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: padding),
            inner.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -padding),
            inner.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -padding),
        ])
        return box
    }

    private func scrollCard(_ tv: NSTextView, height: CGFloat) -> NSView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = tv
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let box = roundedBox()
        box.addSubview(scroll)
        NSLayoutConstraint.activate([
            box.widthAnchor.constraint(equalToConstant: winWidth - 52),
            box.heightAnchor.constraint(equalToConstant: height),
            scroll.topAnchor.constraint(equalTo: box.topAnchor, constant: 6),
            scroll.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 6),
            scroll.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -6),
            scroll.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -6),
        ])
        return box
    }

    /// Filled cyan pill — the primary action.
    private func accentButton(title: String, symbol: String, action: Selector) -> NSButton {
        let b = HoverButton(title: "  " + title + "  ", target: self, action: action)
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        b.imagePosition = .imageLeading
        b.isBordered = false
        b.wantsLayer = true
        b.contentTintColor = Brand.pillText
        b.font = .systemFont(ofSize: 13, weight: .semibold)
        b.layer?.backgroundColor = Brand.pillFill.cgColor
        b.layer?.cornerRadius = 9
        b.heightAnchor.constraint(equalToConstant: 34).isActive = true
        b.widthAnchor.constraint(greaterThanOrEqualToConstant: 96).isActive = true
        return b
    }

    /// Soft-filled grey pill — secondary actions (Wispr's "Change" button style).
    private func pillButton(title: String, symbol: String, action: Selector) -> NSButton {
        let b = HoverButton(title: "  " + title + "  ", target: self, action: action)
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        b.imagePosition = .imageLeading
        b.isBordered = false
        b.wantsLayer = true
        b.contentTintColor = .labelColor
        b.font = .systemFont(ofSize: 13, weight: .medium)
        b.layer?.backgroundColor = Brand.softFill.cgColor
        b.layer?.cornerRadius = 9
        b.heightAnchor.constraint(equalToConstant: 34).isActive = true
        return b
    }

    private func separatorLine() -> NSView {
        let line = NSBox()
        line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        line.widthAnchor.constraint(equalToConstant: winWidth - 52).isActive = true
        return line
    }
}

/// NSButton that brightens slightly on hover (Wispr-style affordance).
final class HoverButton: NSButton {
    private var tracking: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self)
        addTrackingArea(t); tracking = t
    }
    override func mouseEntered(with event: NSEvent) { animator().alphaValue = 0.82 }
    override func mouseExited(with event: NSEvent) { animator().alphaValue = 1.0 }
}
