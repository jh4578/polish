import AppKit

/// Settings window, styled after Wispr Flow: each row is "title + grey subtitle
/// on the left, control on the right, separator below". Language, hotkey, model,
/// popup toggle, and the default polish prompt.
final class SettingsWindowController: NSObject, NSWindowDelegate, NSTextViewDelegate {
    static let shared = SettingsWindowController()

    private let rowWidth: CGFloat = 430

    private var window: NSWindow?
    private var langPopup: NSPopUpButton!
    private var hotKeyLabel: NSTextField!
    private var modelPopup: NSPopUpButton!
    private var panelSwitch: NSSwitch!
    private var promptView: NSTextView!

    /// Called after the hotkey is changed from this window.
    var onHotKeyChange: (() -> Void)?

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(languageChanged),
                                               name: .languageChanged, object: nil)
    }

    func show() {
        build()
        refresh()
        NSApp.activate(ignoringOtherApps: true)
        if window?.isVisible != true { window?.center() }
        window?.makeKeyAndOrderFront(nil)
    }

    @objc private func languageChanged() {
        guard window != nil else { return }
        build(); refresh()
    }

    private func refresh() {
        langPopup.selectItem(at: AppLanguage.allCases.firstIndex(of: Settings.language) ?? 0)
        hotKeyLabel.stringValue = HotKeyConfig.current.displayString
        if let idx = Settings.modelOptions.firstIndex(where: { $0.id == Settings.model }) {
            modelPopup.selectItem(at: idx)
        }
        panelSwitch.state = Settings.showPanel ? .on : .off
        promptView.string = Settings.polishInstruction
    }

    private func build() {
        let window = self.window ?? NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 440),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        window.title = L("Polish 设置", "Polish Settings")
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.applyLightAppearance()

        // Controls
        langPopup = NSPopUpButton()
        for lang in AppLanguage.allCases { langPopup.addItem(withTitle: lang.displayName) }
        langPopup.target = self; langPopup.action = #selector(changeLanguage)

        hotKeyLabel = NSTextField(labelWithString: "")
        hotKeyLabel.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        hotKeyLabel.textColor = .secondaryLabelColor
        let changeButton = NSButton(title: L("更改…", "Change…"), target: self, action: #selector(changeHotKey))
        changeButton.bezelStyle = .rounded

        modelPopup = NSPopUpButton()
        for opt in Settings.modelOptions { modelPopup.addItem(withTitle: opt.label) }
        modelPopup.target = self; modelPopup.action = #selector(changeModel)

        panelSwitch = NSSwitch()
        panelSwitch.target = self; panelSwitch.action = #selector(togglePanel)

        // Prompt editor block
        let promptTitle = NSTextField(labelWithString: L("默认润色指令", "Default polish instruction"))
        promptTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        let promptSub = subLabel(L("弹窗直接回车、或关闭弹窗时使用", "Used on plain Enter, or when the popup is off"))

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let pv = NSTextView()
        pv.font = .systemFont(ofSize: 13)
        pv.isRichText = false
        pv.allowsUndo = true
        pv.drawsBackground = false
        pv.textContainerInset = NSSize(width: 8, height: 8)
        pv.autoresizingMask = [.width]
        pv.delegate = self
        scroll.documentView = pv
        self.promptView = pv
        let promptCard = cardWrap(scroll, height: 92)

        let resetButton = NSButton(title: L("恢复默认", "Reset to default"),
                                   target: self, action: #selector(resetPrompt))
        resetButton.bezelStyle = .rounded

        let promptBlock = NSStackView(views: [promptTitle, promptSub, promptCard, resetButton])
        promptBlock.orientation = .vertical
        promptBlock.alignment = .leading
        promptBlock.spacing = 6
        promptBlock.setCustomSpacing(8, after: promptSub)

        // Rows
        let rows = NSStackView(views: [
            settingRow(L("界面语言", "Language"), subtitle: subLabel(L("切换后界面即时切换", "Switches the whole UI instantly")), control: langPopup),
            sep(),
            settingRow(L("快捷键", "Hotkey"), subtitle: hotKeyLabel, control: changeButton),
            sep(),
            settingRow(L("模型", "Model"), subtitle: subLabel(L("mini 更快，5.5 质量更高", "mini is faster, 5.5 higher quality")), control: modelPopup),
            sep(),
            settingRow(L("按快捷键时显示弹窗", "Show popup on hotkey"),
                       subtitle: subLabel(L("关闭后有选中直接润色；没选中仍弹窗", "Off: instant polish when text is selected")), control: panelSwitch),
            sep(),
            promptBlock,
        ])
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 12
        rows.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)
        rows.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(rows)
        NSLayoutConstraint.activate([
            rows.topAnchor.constraint(equalTo: content.topAnchor),
            rows.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            rows.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            rows.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        window.contentView = content
        self.window = window
    }

    // MARK: - Row helpers

    private func settingRow(_ title: String, subtitle: NSView, control: NSView) -> NSView {
        let t = NSTextField(labelWithString: title)
        t.font = .systemFont(ofSize: 13, weight: .semibold)

        let left = NSStackView(views: [t, subtitle])
        left.orientation = .vertical
        left.alignment = .leading
        left.spacing = 2

        control.setContentHuggingPriority(.required, for: .horizontal)
        let row = NSStackView(views: [left, NSView(), control])
        row.orientation = .horizontal
        row.spacing = 12
        row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: rowWidth).isActive = true
        return row
    }

    private func subLabel(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: 11)
        l.textColor = .secondaryLabelColor
        return l
    }

    private func sep() -> NSView {
        let b = NSBox()
        b.boxType = .separator
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(equalToConstant: rowWidth).isActive = true
        return b
    }

    private func cardWrap(_ inner: NSView, height: CGFloat) -> NSView {
        let box = NSView()
        box.wantsLayer = true
        box.layer?.backgroundColor = Brand.cardFill.cgColor
        box.layer?.cornerRadius = 10
        box.layer?.borderWidth = 1
        box.layer?.borderColor = Brand.rim.cgColor
        inner.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(inner)
        NSLayoutConstraint.activate([
            box.widthAnchor.constraint(equalToConstant: rowWidth),
            box.heightAnchor.constraint(equalToConstant: height),
            inner.topAnchor.constraint(equalTo: box.topAnchor, constant: 4),
            inner.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 4),
            inner.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -4),
            inner.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -4),
        ])
        return box
    }

    // MARK: - Actions

    @objc private func changeLanguage() {
        let langs = AppLanguage.allCases
        let idx = langPopup.indexOfSelectedItem
        if langs.indices.contains(idx) { Settings.language = langs[idx] }
    }

    @objc private func changeHotKey() {
        HotKeyRecorderController.shared.show { [weak self] config in
            self?.hotKeyLabel.stringValue = config.displayString
            self?.onHotKeyChange?()
            self?.window?.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func changeModel() {
        let idx = modelPopup.indexOfSelectedItem
        if Settings.modelOptions.indices.contains(idx) { Settings.model = Settings.modelOptions[idx].id }
    }

    @objc private func togglePanel() { Settings.showPanel = (panelSwitch.state == .on) }

    @objc private func resetPrompt() {
        promptView.string = Settings.defaultPolishInstruction
        Settings.polishInstruction = Settings.defaultPolishInstruction
    }

    func textDidChange(_ notification: Notification) {
        Settings.polishInstruction = promptView.string
    }
}
