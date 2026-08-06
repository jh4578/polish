import AppKit

/// A tiny non-activating floating HUD used in instant-polish mode
/// (spinner + short status text, auto-dismisses).
final class ProgressHUD {
    static let shared = ProgressHUD()

    private var panel: NSPanel?
    private var label: NSTextField!
    private var spinner: NSProgressIndicator!
    private var dismissWork: DispatchWorkItem?

    func show(_ text: String, spinning: Bool) {
        dismissWork?.cancel()
        if panel == nil { build() }
        label.stringValue = text
        spinning ? spinner.startAnimation(nil) : spinner.stopAnimation(nil)
        spinner.isHidden = !spinning

        if let panel {
            let mouse = NSEvent.mouseLocation
            panel.layoutIfNeeded()
            panel.setContentSize(NSSize(width: label.intrinsicContentSize.width + (spinning ? 46 : 28),
                                        height: 34))
            panel.setFrameOrigin(NSPoint(x: mouse.x + 14, y: mouse.y - 44))
            panel.orderFrontRegardless()
        }
    }

    func dismiss(after delay: TimeInterval = 0) {
        let work = DispatchWorkItem { [weak self] in
            self?.panel?.orderOut(nil)
        }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func build() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 160, height: 34),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false

        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 8

        spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false

        label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 12)

        let stack = NSStackView(views: [spinner, label])
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false

        effect.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: effect.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: effect.centerYAnchor),
        ])
        panel.contentView = effect
        self.panel = panel
    }
}
