import Foundation

/// Calls the Codex backend directly with the local ChatGPT subscription login
/// (`~/.codex/auth.json`) — no API key, no Node, no SDK subprocess. This is the
/// same endpoint the Codex CLI uses; usage counts against the ChatGPT plan.
final class CodexClient {

    struct Reply {
        let text: String
        let threadId: String?   // unused now; kept for the panel's follow-up API
    }

    enum CodexError: LocalizedError {
        case notLoggedIn
        case authExpired
        case http(Int, String)
        case empty
        case transport(String)

        var errorDescription: String? {
            switch self {
            case .notLoggedIn: return "未找到 Codex 登录信息，请先用 ChatGPT 账号登录 Codex"
            case .authExpired: return "Codex 登录已过期，请打开 Codex 重新登录"
            case .http(let code, let msg): return "请求失败(\(code))：\(msg)"
            case .empty: return "没有返回内容"
            case .transport(let msg): return msg
            }
        }
    }

    static let shared = CodexClient()

    private let endpoint = URL(string: "https://chatgpt.com/backend-api/codex/responses")!
    private let session: URLSession

    // A stable per-launch session id keeps calls grouped on one server-side session.
    private let sessionId = UUID().uuidString

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        session = URLSession(configuration: config)
    }

    // MARK: - Public API

    /// Rewrites text. `threadId` is ignored (each call is stateless and carries
    /// the current text), but kept so the panel's follow-up flow needs no change.
    func rewrite(instruction: String?, text: String?, threadId: String?,
                 completion: @escaping (Result<Reply, Error>) -> Void) {
        let finish: (Result<Reply, Error>) -> Void = { result in
            DispatchQueue.main.async { completion(result) }
        }

        let token: String
        do {
            token = try CodexAuth.accessToken()
        } catch {
            finish(.failure(error)); return
        }

        let instr = (instruction?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap {
            $0.isEmpty ? nil : $0
        } ?? Settings.polishInstruction

        let body = buildRequestBody(instruction: instr, text: text)
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            finish(.failure(CodexError.transport("请求编码失败"))); return
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(CodexAuth.accountId(), forHTTPHeaderField: "chatgpt-account-id")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("responses=experimental", forHTTPHeaderField: "OpenAI-Beta")
        request.setValue("codex_cli_rs", forHTTPHeaderField: "originator")
        request.setValue(sessionId, forHTTPHeaderField: "session_id")

        let task = session.dataTask(with: request) { data, response, error in
            if let error {
                finish(.failure(CodexError.transport(error.localizedDescription))); return
            }
            guard let http = response as? HTTPURLResponse, let data else {
                finish(.failure(CodexError.transport("无响应"))); return
            }
            guard http.statusCode == 200 else {
                let msg = String(data: data, encoding: .utf8) ?? ""
                if http.statusCode == 401 { finish(.failure(CodexError.authExpired)); return }
                finish(.failure(CodexError.http(http.statusCode, Self.briefError(msg)))); return
            }

            let text = Self.parseSSE(data)
            if text.isEmpty {
                finish(.failure(CodexError.empty))
            } else {
                finish(.success(Reply(text: text, threadId: nil)))
            }
        }
        task.resume()
    }

    // MARK: - Request

    private func buildRequestBody(instruction: String, text: String?) -> [String: Any] {
        let sys = """
        You are a precise text-rewriting assistant embedded in a Mac writing tool. \
        Reply with ONLY the final text — no explanations, no quotes, no markdown fences. \
        Keep the original language unless the instruction says otherwise. Preserve line breaks.
        """

        let userText: String
        if let text, !text.isEmpty {
            userText = "Instruction: \(instruction)\n\n<text>\n\(text)\n</text>"
        } else {
            userText = "Instruction: \(instruction)\n\n(Write the requested text.)"
        }

        return [
            "model": Settings.model,
            "instructions": sys,
            "input": [[
                "type": "message",
                "role": "user",
                "content": [["type": "input_text", "text": userText]],
            ]],
            "stream": true,
            "store": false,
            "reasoning": ["effort": "none"],   // fastest effort the ChatGPT plan allows
        ]
    }

    // MARK: - SSE parsing

    /// Collects `response.output_text.delta` chunks from a text/event-stream body.
    private static func parseSSE(_ data: Data) -> String {
        guard let raw = String(data: data, encoding: .utf8) else { return "" }
        var out = ""
        for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload.isEmpty || payload == "[DONE]" { continue }
            guard
                let obj = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any],
                let type = obj["type"] as? String
            else { continue }
            if type == "response.output_text.delta", let delta = obj["delta"] as? String {
                out += delta
            }
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func briefError(_ body: String) -> String {
        if let obj = try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any] {
            if let err = obj["error"] as? [String: Any], let msg = err["message"] as? String { return msg }
            if let detail = obj["detail"] as? String { return detail }
        }
        return String(body.prefix(120))
    }
}
