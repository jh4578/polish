import Foundation

extension Notification.Name {
    static let modelCatalogChanged = Notification.Name("PolishModelCatalogChanged")
}

/// The server catalog is account-specific. Cache only model metadata, never tokens.
enum ModelCatalog {
    struct Model: Codable {
        let slug: String
        let display_name: String
        let visibility: String
        let supported_reasoning_levels: [Reasoning]?

        struct Reasoning: Codable { let effort: String }
        var effort: String {
            let supported = supported_reasoning_levels?.map(\.effort) ?? []
            return ["none", "minimal", "low", "medium", "high"].first(where: supported.contains)
                ?? supported.first ?? "low"
        }
    }

    private struct Catalog: Codable { let models: [Model] }
    private struct Cache: Codable {
        let accountId: String
        let catalog: Catalog
    }

    private static let cacheKey = "AccountModelCatalog"
    private static var refreshing = false
    private(set) static var status: String = ""

    static var models: [Model] {
        guard let accountId = CodexAuth.accountId(),
              let data = UserDefaults.standard.data(forKey: cacheKey),
              let cache = try? JSONDecoder().decode(Cache.self, from: data),
              cache.accountId == accountId else { return [] }
        return cache.catalog.models
    }

    /// Use the installed Codex catalog version to negotiate its current model list.
    private static var clientVersion: String {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/models_cache.json")
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = obj["client_version"] as? String else { return "0.162.0" }
        return version
    }

    /// Called on the main queue; auth and network work run in the background.
    static func refresh() {
        guard !refreshing else { return }
        refreshing = true
        status = L("正在获取账号模型…", "Loading account models…")
        NotificationCenter.default.post(name: .modelCatalogChanged, object: nil)
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let token = try CodexAuth.accessToken()
                guard let accountId = CodexAuth.accountId() else {
                    throw CodexClient.CodexError.notLoggedIn
                }
                var url = URLComponents(string: "https://chatgpt.com/backend-api/codex/models")!
                url.queryItems = [URLQueryItem(name: "client_version", value: clientVersion)]
                var request = URLRequest(url: url.url!)
                request.timeoutInterval = 20
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue(accountId, forHTTPHeaderField: "chatgpt-account-id")
                request.setValue("codex_cli_rs", forHTTPHeaderField: "originator")
                URLSession.shared.dataTask(with: request) { data, response, error in
                    do {
                        if let error { throw error }
                        guard let http = response as? HTTPURLResponse, let data else {
                            throw CodexClient.CodexError.transport("无响应")
                        }
                        guard http.statusCode == 200 else {
                            throw CodexClient.CodexError.http(http.statusCode, "模型列表获取失败")
                        }
                        let decoded = try JSONDecoder().decode(Catalog.self, from: data)
                        let visible = decoded.models.filter { $0.visibility == "list" && !$0.slug.isEmpty }
                        guard !visible.isEmpty else {
                            throw CodexClient.CodexError.transport("账号未返回可显示的模型")
                        }
                        let cache = Cache(accountId: accountId, catalog: Catalog(models: visible))
                        let encoded = try JSONEncoder().encode(cache)
                        DispatchQueue.main.async {
                            // Ignore a response from an account that has since signed out/switched.
                            guard CodexAuth.accountId() == accountId else {
                                finish(L("账号已切换，请刷新", "Account changed; refresh again")); return
                            }
                            UserDefaults.standard.set(encoded, forKey: cacheKey)
                            finish(L("已更新 · \(visible.count) 个账号模型", "Updated · \(visible.count) account models"))
                        }
                    } catch {
                        DispatchQueue.main.async { failed(error) }
                    }
                }.resume()
            } catch {
                DispatchQueue.main.async { failed(error) }
            }
        }
    }

    private static func failed(_ error: Error) {
        let fallback = models.isEmpty ? L("使用内置选项", "Using built-in choices")
            : L("保留缓存列表", "Keeping cached list")
        finish(L("获取失败，\(fallback)：", "Refresh failed, \(fallback): ") + error.localizedDescription)
    }

    private static func finish(_ message: String) {
        refreshing = false
        status = message
        NotificationCenter.default.post(name: .modelCatalogChanged, object: nil)
    }
}
