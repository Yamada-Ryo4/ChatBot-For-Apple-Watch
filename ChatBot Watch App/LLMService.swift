import Foundation
#if canImport(UIKit)
import UIKit
#endif

class LLMService: NSObject, URLSessionDelegate {
    
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60.0
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()
    
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(.performDefaultHandling, nil)
    }

    func fetchModels(config: ProviderConfig) async throws -> [AIModelInfo] {
        switch config.apiType {
        case .openAI: return try await fetchOpenAIModels(baseURL: config.baseURL, apiKey: config.apiKey)
        case .gemini: return try await fetchGeminiModels(baseURL: config.baseURL, apiKey: config.apiKey)
        }
    }

    func streamChat(messages: [ChatMessage], modelId: String, config: ProviderConfig) -> AsyncThrowingStream<String, Error> {
        switch config.apiType {
        case .openAI: return streamOpenAIChat(messages: messages, modelId: modelId, baseURL: config.baseURL, apiKey: config.apiKey)
        case .gemini: return streamGeminiChat(messages: messages, modelId: modelId, baseURL: config.baseURL, apiKey: config.apiKey)
        }
    }
    
    // MARK: - Implementations
    private func fetchOpenAIModels(baseURL: String, apiKey: String) async throws -> [AIModelInfo] {
        guard let request = buildRequest(baseURL: baseURL, path: "models", apiKey: apiKey, type: .openAI) else { throw URLError(.badURL) }
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
        let list = try JSONDecoder().decode(OpenAIModelListResponse.self, from: data)
        return list.data.map { AIModelInfo(id: $0.id, displayName: nil) }.sorted { $0.id < $1.id }
    }
    
    private func fetchGeminiModels(baseURL: String, apiKey: String) async throws -> [AIModelInfo] {
        guard let request = buildRequest(baseURL: baseURL, path: "models", apiKey: apiKey, type: .gemini) else { throw URLError(.badURL) }
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
        let list = try JSONDecoder().decode(GeminiModelListResponse.self, from: data)
        return list.models.map { m in
            let shortID = m.name.replacingOccurrences(of: "models/", with: "")
            return AIModelInfo(id: shortID, displayName: nil)
        }.filter { $0.id.contains("gemini") }.sorted { $0.id < $1.id }
    }
    
    private func streamOpenAIChat(messages: [ChatMessage], modelId: String, baseURL: String, apiKey: String) -> AsyncThrowingStream<String, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                let openAIMessages: [[String: Any]] = messages.map { msg in
                    var content: Any = msg.text
                    if let imgData = msg.imageData {
                        content = [["type": "text", "text": msg.text], ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(imgData.base64EncodedString())"]]]
                    }
                    return ["role": msg.role.apiValue, "content": content]
                }
                let body: [String: Any] = ["model": modelId, "messages": openAIMessages, "stream": true]
                guard var req = buildRequest(baseURL: baseURL, path: "chat/completions", apiKey: apiKey, type: .openAI) else { continuation.finish(throwing: URLError(.badURL)); return }
                req.httpMethod = "POST"
                req.httpBody = try? JSONSerialization.data(withJSONObject: body)
                await performStream(request: req, continuation: continuation) { line in
                    guard line.hasPrefix("data: ") else { return nil }
                    let json = String(line.dropFirst(6))
                    if json.trimmingCharacters(in: .whitespaces) == "[DONE]" { return nil }
                    if let data = json.data(using: .utf8), let res = try? JSONDecoder().decode(OpenAIStreamResponse.self, from: data) {
                        return res.choices.first?.delta.content
                    }
                    return nil
                }
            }
        }
    }
    
    private func streamGeminiChat(messages: [ChatMessage], modelId: String, baseURL: String, apiKey: String) -> AsyncThrowingStream<String, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                let contents: [[String: Any]] = messages.map { msg in
                    var parts: [[String: Any]] = []
                    if let imgData = msg.imageData { parts.append(["inline_data": ["mime_type": "image/jpeg", "data": imgData.base64EncodedString()]]) }
                    if !msg.text.isEmpty { parts.append(["text": msg.text]) }
                    let role = (msg.role == .user) ? "user" : "model"
                    return ["role": role, "parts": parts]
                }
                let body: [String: Any] = ["contents": contents]
                let path = "models/\(modelId):streamGenerateContent?alt=sse"
                
                guard var req = buildRequest(baseURL: baseURL, path: path, apiKey: apiKey, type: .gemini) else { continuation.finish(throwing: URLError(.badURL)); return }
                req.httpMethod = "POST"
                req.httpBody = try? JSONSerialization.data(withJSONObject: body)
                await performStream(request: req, continuation: continuation) { line in
                    guard line.hasPrefix("data: ") else { return nil }
                    let json = String(line.dropFirst(6))
                    if let data = json.data(using: .utf8), let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let candidates = dict["candidates"] as? [[String: Any]], let content = candidates.first?["content"] as? [String: Any],
                       let parts = content["parts"] as? [[String: Any]], let text = parts.first?["text"] as? String {
                        return text
                    }
                    return nil
                }
            }
        }
    }

    private func validateResponse(_ response: URLResponse?, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else { return }
        if httpResponse.statusCode != 200 {
            let errorBody = String(data: data, encoding: .utf8) ?? "No body"
            let msg = "HTTP \(httpResponse.statusCode)"
            print("❌ API Error: \(msg) | URL: \(httpResponse.url?.absoluteString ?? "")")
            throw NSError(domain: "APIError", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }
    }
    
    private func buildRequest(baseURL: String, path: String, apiKey: String, type: APIType) -> URLRequest? {
        var cleanBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanBase.hasSuffix("/") { cleanBase = String(cleanBase.dropLast()) }
        var fullPath = ""
        switch type {
        case .openAI: fullPath = "\(cleanBase)/\(path)"
        case .gemini:
            if cleanBase.contains("/v1beta") { fullPath = "\(cleanBase)/\(path)" }
            else { fullPath = "\(cleanBase)/v1beta/\(path)" }
        }
        guard let url = URL(string: fullPath) else { return nil }
        var request = URLRequest(url: url)
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        switch type {
        case .openAI: request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        case .gemini: request.addValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        }
        return request
    }
    
    private func performStream(request: URLRequest, continuation: AsyncThrowingStream<String, Error>.Continuation, parser: @escaping (String) -> String?) async {
        do {
            let (result, response) = try await session.bytes(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                continuation.yield("❌ HTTP Error: \(httpResponse.statusCode)")
                continuation.finish(throwing: URLError(.badServerResponse))
                return
            }
            for try await line in result.lines {
                if let text = parser(line) { continuation.yield(text) }
            }
            continuation.finish()
        } catch { continuation.finish(throwing: error) }
    }
}
