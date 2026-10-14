import Foundation

/// App settings persisted in UserDefaults.
enum Settings {
    static let defaultPolishInstruction =
        "Polish the text: improve grammar, fluency, and clarity while fully preserving the meaning and tone."

    /// Models verified with this Mac's ChatGPT subscription, fastest first.
    struct ModelOption {
        let id: String
        let zh: String
        let en: String
        var label: String { L(zh, en) }
    }
    private static let fallbackModelOptions = [
        ModelOption(id: "gpt-6-luna", zh: "速度优先 · gpt-6-luna", en: "Fast · gpt-6-luna"),
        ModelOption(id: "gpt-6.1-sol", zh: "质量优先 · gpt-6.1-sol", en: "Quality · gpt-6.1-sol"),
    ]

    static var modelOptions: [ModelOption] {
        let models = ModelCatalog.models
        return models.isEmpty ? fallbackModelOptions : models.map {
            ModelOption(id: $0.slug, zh: $0.display_name, en: $0.display_name)
        }
    }

    static var reasoningEffort: String {
        ModelCatalog.models.first(where: { $0.slug == model })?.effort ?? "low"
    }

    static var model: String {
        get {
            let value = UserDefaults.standard.string(forKey: "Model")
            // Preserve the user's speed/quality preference when retiring old models.
            let migrated = value == "gpt-5.5" ? "gpt-6.1-sol"
                : value == "gpt-5.4-mini" ? "gpt-6-luna" : value
            return modelOptions.first(where: { $0.id == migrated })?.id ?? modelOptions[0].id
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
