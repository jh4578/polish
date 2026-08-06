import Foundation

/// App settings persisted in UserDefaults.
enum Settings {
    static let defaultPolishInstruction =
        "Polish the text: improve grammar, fluency, and clarity while fully preserving the meaning and tone."

    /// Models the ChatGPT-subscription account accepts, fastest first.
    /// (Verified: gpt-5-mini/nano, 5.1/5.2/5.3/5.6, o4-mini etc. are all rejected.)
    struct ModelOption {
        let id: String
        let zh: String
        let en: String
        var label: String { L(zh, en) }
    }
    static let modelOptions = [
        ModelOption(id: "gpt-5.4-mini", zh: "速度优先 · gpt-5.4-mini（约1秒）", en: "Fast · gpt-5.4-mini (~1s)"),
        ModelOption(id: "gpt-5.5", zh: "质量优先 · gpt-5.5（约2秒）", en: "Quality · gpt-5.5 (~2s)"),
    ]

    static var model: String {
        get {
            let value = UserDefaults.standard.string(forKey: "Model")
            return modelOptions.contains { $0.id == value } ? value! : modelOptions[0].id
        }
        set { UserDefaults.standard.set(newValue, forKey: "Model") }
    }

    /// UI language. Changing it broadcasts `.languageChanged` so open windows rebuild.
    static var language: AppLanguage {
        get { AppLanguage(rawValue: UserDefaults.standard.string(forKey: "Language") ?? "") ?? .zh }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "Language")
            NotificationCenter.default.post(name: .languageChanged, object: nil)
        }
    }

    /// Whether the hotkey opens the instruction panel. When off, the hotkey
    /// polishes the selection immediately using `polishInstruction`.
    static var showPanel: Bool {
        get { UserDefaults.standard.object(forKey: "ShowPanel") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "ShowPanel") }
    }

    /// The instruction used when the user submits without typing anything
    /// (and for instant polish when the panel is disabled).
    static var polishInstruction: String {
        get {
            let value = UserDefaults.standard.string(forKey: "PolishInstruction")?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (value?.isEmpty ?? true) ? defaultPolishInstruction : value!
        }
        set { UserDefaults.standard.set(newValue, forKey: "PolishInstruction") }
    }
}
