import AppKit

enum AppLanguage: String, CaseIterable {
    case zh, en
    var displayName: String { self == .zh ? "中文" : "English" }
}

extension Notification.Name {
    static let languageChanged = Notification.Name("PolishLanguageChanged")
}

/// Tiny inline localization: `L("中文", "English")` returns the string for the
/// currently selected UI language. Keeps translations next to their use site.
func L(_ zh: String, _ en: String) -> String {
    Settings.language == .zh ? zh : en
}

/// Wispr-Flow-inspired palette: always-light, clean, neutral black/white with
/// rounded cards and a near-black primary pill. Fixed sRGB values (not semantic
/// colors) because every window is pinned to the light `.aqua` appearance, à la
/// Wispr Flow, so it looks identical whether the system is light or dark.
enum Brand {
    static let windowFill = NSColor(srgbRed: 0.96, green: 0.96, blue: 0.97, alpha: 1)  // page bg #F5F5F7
    static let cardFill   = NSColor.white                                              // card
    static let pillFill   = NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1)  // near-black
    static let pillText   = NSColor.white
    static let softFill   = NSColor(srgbRed: 0.92, green: 0.92, blue: 0.93, alpha: 1)  // secondary pill
    static let iconTint   = NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1)
    static let okDot      = NSColor.systemGreen
    static let warnDot    = NSColor.systemOrange
    static let rim        = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.10)
}

/// Pins a window to Wispr's always-light look regardless of system theme.
extension NSWindow {
    func applyLightAppearance() { appearance = NSAppearance(named: .aqua) }
}
