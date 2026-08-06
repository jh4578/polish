import Foundation

/// Reads (and if needed refreshes) the ChatGPT subscription login that the
/// Codex CLI stores in ~/.codex/auth.json. No API key involved.
enum CodexAuth {

    private static var authURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".codex/auth.json")
    }

    private static func load() -> [String: Any]? {
        guard
            let data = try? Data(contentsOf: authURL),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return obj
    }

    static func accountId() -> String? {
        (load()?["tokens"] as? [String: Any])?["account_id"] as? String
    }

    /// Whether a usable ChatGPT login exists (for status display).
    static var isLoggedIn: Bool {
        (try? accessToken()) != nil
    }

    /// Returns a currently-valid access token, refreshing synchronously if it is
    /// expired or about to expire. Throws if there is no usable login.
    static func accessToken() throws -> String {
        guard let auth = load(), let tokens = auth["tokens"] as? [String: Any],
              let access = tokens["access_token"] as? String else {
            throw CodexClient.CodexError.notLoggedIn
        }

        if let exp = jwtExpiry(access), exp.timeIntervalSinceNow > 120 {
            return access
        }

        // Expired/expiring: try a refresh; fall back to the existing token.
        if let refresh = tokens["refresh_token"] as? String,
           let clientId = jwtClaim(access, "client_id") as? String,
           let refreshed = try? refreshSync(refreshToken: refresh, clientId: clientId) {
            return refreshed
        }
        if jwtExpiry(access).map({ $0.timeIntervalSinceNow > 0 }) == true {
            return access   // still technically valid; let the request try
        }
        throw CodexClient.CodexError.authExpired
    }

    // MARK: - Refresh (OAuth refresh-token grant)

    private static func refreshSync(refreshToken: String, clientId: String) throws -> String {
        let url = URL(string: "https://auth.openai.com/oauth/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientId,
        ])

        let sem = DispatchSemaphore(value: 0)
        var newAccess: String?
        var newRefresh: String?
        URLSession.shared.dataTask(with: request) { data, response, _ in
            defer { sem.signal() }
            guard let data, (response as? HTTPURLResponse)?.statusCode == 200,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            newAccess = obj["access_token"] as? String
            newRefresh = obj["refresh_token"] as? String
        }.resume()
        _ = sem.wait(timeout: .now() + 15)

        guard let access = newAccess else {
            throw CodexClient.CodexError.authExpired
        }
        persist(accessToken: access, refreshToken: newRefresh)
        return access
    }

    /// Writes refreshed tokens back to auth.json so the CLI and this app stay in sync.
    private static func persist(accessToken: String, refreshToken: String?) {
        guard var auth = load(), var tokens = auth["tokens"] as? [String: Any] else { return }
        tokens["access_token"] = accessToken
        if let refreshToken { tokens["refresh_token"] = refreshToken }
        auth["tokens"] = tokens

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        auth["last_refresh"] = formatter.string(from: Date())

        guard let data = try? JSONSerialization.data(withJSONObject: auth, options: [.prettyPrinted]) else { return }
        try? data.write(to: authURL, options: [.atomic])
    }

    // MARK: - JWT helpers

    private static func jwtExpiry(_ token: String) -> Date? {
        (jwtClaim(token, "exp") as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
    }

    private static func jwtClaim(_ token: String, _ key: String) -> Any? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var b64 = String(parts[1]).replacingOccurrences(of: "-", with: "+")
                                  .replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return obj[key]
    }
}
