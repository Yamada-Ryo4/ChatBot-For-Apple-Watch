import Foundation

// 这是一个纯逻辑服务，不涉及 UI，所以不要加 @MainActor
// 这是一个纯逻辑服务，不涉及 UI，所以不要加 @MainActor
class LLMService: NSObject {
    
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120.0  // 请求超时 120秒
        config.timeoutIntervalForResource = 300.0 // 资源超时 5分钟
        config.waitsForConnectivity = true        // 等待网络连接
        return URLSession(configuration: config) // ⚠️ 移除 delegate，恢复系统默认安全验证
    }()
    
    // 移除手动 TLS 验证代理方法，因为服务器证书经过验证是合法的 Let's Encrypt 证书
    // 同时也移除了可能导致 HTTP/2 握手问题的干扰


    func fetchModels(config: ProviderConfig) async throws -> [AIModelInfo] {
        switch config.apiType {
        case .openAI: return try await fetchOpenAIModels(baseURL: config.baseURL, apiKey: config.apiKey)
        case .gemini: return try await fetchGeminiModels(baseURL: config.baseURL, apiKey: config.apiKey)
        }
    }

    func streamChat(messages: [ChatMessage], modelId: String, config: ProviderConfig, temperature: Double = 0.7) -> AsyncThrowingStream<String, Error> {
        switch config.apiType {
        case .openAI: return streamOpenAIChat(messages: messages, modelId: modelId, baseURL: config.baseURL, apiKey: config.apiKey, temperature: temperature)
        case .gemini: return streamGeminiChat(messages: messages, modelId: modelId, baseURL: config.baseURL, apiKey: config.apiKey, temperature: temperature)
        }
    }
    
    // MARK: - Implementations
    private func fetchOpenAIModels(baseURL: String, apiKey: String) async throws -> [AIModelInfo] {
        guard let request = buildRequest(baseURL: baseURL, path: "models", apiKey: apiKey, type: .openAI) else { throw URLError(.badURL) }
        
        // 使用 legacyData 
        let (data, response) = try await legacyData(for: request)
        try validateResponse(response, data: data)
        // 使用文件底部的私有结构体解析
        let list = try JSONDecoder().decode(PrivateOpenAIModelListResponse.self, from: data)
        return list.data.map { AIModelInfo(id: $0.id, displayName: nil) }.sorted { $0.id < $1.id }
    }
    
    private func fetchGeminiModels(baseURL: String, apiKey: String) async throws -> [AIModelInfo] {
        guard let request = buildRequest(baseURL: baseURL, path: "models", apiKey: apiKey, type: .gemini) else { throw URLError(.badURL) }
        let (data, response) = try await legacyData(for: request)
        try validateResponse(response, data: data)
        let list = try JSONDecoder().decode(PrivateGeminiModelListResponse.self, from: data)
        return list.models.map { m in
            let shortID = m.name.replacingOccurrences(of: "models/", with: "")
            return AIModelInfo(id: shortID, displayName: nil)
        }.filter { $0.id.contains("gemini") }.sorted { $0.id < $1.id }
    }
    
    private func streamOpenAIChat(messages: [ChatMessage], modelId: String, baseURL: String, apiKey: String, temperature: Double) -> AsyncThrowingStream<String, Error> {
        return AsyncThrowingStream { continuation in
            let task = Task {
                let openAIMessages: [[String: Any]] = messages.map { msg in
                    var content: Any = msg.text
                    if let imgData = msg.imageData {
                        content = [["type": "text", "text": msg.text], ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(imgData.base64EncodedString())"]]]
                    }
                    return ["role": msg.role.rawValue, "content": content]
                }
                let body: [String: Any] = ["model": modelId, "messages": openAIMessages, "stream": true, "temperature": temperature]
                guard var req = buildRequest(baseURL: baseURL, path: "chat/completions", apiKey: apiKey, type: .openAI) else { continuation.finish(throwing: URLError(.badURL)); return }
                req.httpMethod = "POST"
                req.httpBody = try? JSONSerialization.data(withJSONObject: body)
                await performStream(request: req, continuation: continuation) { line in
                    guard line.hasPrefix("data: ") else {
                        // 非 data: 开头的行，可能是其他格式
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty && trimmed != "" {
                            print("⚠️ OpenAI 非标准行: \(line.prefix(200))")
                            return "[RAW] " + line
                        }
                        return nil
                    }
                    let json = String(line.dropFirst(6))
                    if json.trimmingCharacters(in: .whitespaces) == "[DONE]" { return nil }
                    
                    // 尝试标准 OpenAI 格式解析
                    if let data = json.data(using: .utf8), let res = try? JSONDecoder().decode(PrivateOpenAIStreamResponse.self, from: data) {
                        let delta = res.choices.first?.delta
                        var result = ""
                        // 使用特殊前缀标记思考内容：🧠THINK:
                        if let reasoning = delta?.reasoning_content, !reasoning.isEmpty {
                            result += "🧠THINK:" + reasoning
                        }
                        if let content = delta?.content, !content.isEmpty {
                            result += content
                        }
                        return result.isEmpty ? nil : result
                    }
                    
                    // 解析失败，尝试通用 JSON 解析
                    if let data = json.data(using: .utf8),
                       let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        // 尝试提取常见字段
                        if let error = dict["error"] as? [String: Any], let message = error["message"] as? String {
                            return "❌ API错误: " + message
                        }
                        // 其他格式：输出原始内容
                        print("⚠️ OpenAI 未知格式: \(json.prefix(200))")
                        return "[DEBUG] " + json
                    }
                    
                    // 完全无法解析，返回原始数据
                    if !json.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        print("⚠️ OpenAI 解析失败: \(json.prefix(200))")
                        return "[PARSE_FAIL] " + json
                    }
                    return nil
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
    
    private func streamGeminiChat(messages: [ChatMessage], modelId: String, baseURL: String, apiKey: String, temperature: Double) -> AsyncThrowingStream<String, Error> {
        return AsyncThrowingStream { continuation in
            let task = Task {
                let contents: [[String: Any]] = messages.map { msg in
                    var parts: [[String: Any]] = []
                    if let imgData = msg.imageData { parts.append(["inline_data": ["mime_type": "image/jpeg", "data": imgData.base64EncodedString()]]) }
                    if !msg.text.isEmpty { parts.append(["text": msg.text]) }
                    let role = (msg.role == .user) ? "user" : "model"
                    return ["role": role, "parts": parts]
                }
                let generationConfig: [String: Any] = ["temperature": temperature]
                let body: [String: Any] = ["contents": contents, "generationConfig": generationConfig]
                let path = "models/\(modelId):streamGenerateContent?alt=sse"
                
                guard var req = buildRequest(baseURL: baseURL, path: path, apiKey: apiKey, type: .gemini) else { continuation.finish(throwing: URLError(.badURL)); return }
                req.httpMethod = "POST"
                req.httpBody = try? JSONSerialization.data(withJSONObject: body)
                await performStream(request: req, continuation: continuation) { line in
                    guard line.hasPrefix("data: ") else {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            print("⚠️ Gemini 非标准行: \(line.prefix(200))")
                            return "[RAW] " + line
                        }
                        return nil
                    }
                    let json = String(line.dropFirst(6))
                    
                    // 尝试标准 Gemini 格式解析
                    if let data = json.data(using: .utf8), let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        // 检查错误
                        if let error = dict["error"] as? [String: Any], let message = error["message"] as? String {
                            return "❌ API错误: " + message
                        }
                        // 标准格式
                        if let candidates = dict["candidates"] as? [[String: Any]],
                           let content = candidates.first?["content"] as? [String: Any],
                           let parts = content["parts"] as? [[String: Any]],
                           let text = parts.first?["text"] as? String {
                            return text
                        }
                        // 未知格式，输出原始内容
                        print("⚠️ Gemini 未知格式: \(json.prefix(200))")
                        return "[DEBUG] " + json
                    }
                    
                    // 完全无法解析
                    if !json.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        print("⚠️ Gemini 解析失败: \(json.prefix(200))")
                        return "[PARSE_FAIL] " + json
                    }
                    return nil
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    private func validateResponse(_ response: URLResponse?, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else { return }
        if httpResponse.statusCode != 200 {
            let errorBody = String(data: data, encoding: .utf8) ?? "No body"
            let msg = "HTTP \(httpResponse.statusCode) - \(errorBody.prefix(100))"
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
        // 添加 User-Agent 伪装，防止被服务端防火墙拦截导致 SSL 中断
        request.addValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        request.addValue("*/*", forHTTPHeaderField: "Accept")
        
        switch type {
        case .openAI: request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        case .gemini: request.addValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        }
        return request
    }
    
    // MARK: - Legacy Wrappers for Delegate Support
    // 必须使用传统的 dataTask 才能保证触发 delegate，从而跳过 TLS 验证
    
    private func legacyData(for request: URLRequest) async throws -> (Data, URLResponse) {
        return try await withCheckedThrowingContinuation { continuation in
            let task = session.dataTask(with: request) { data, response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let data = data, let response = response else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                    return
                }
                continuation.resume(returning: (data, response))
            }
            task.resume()
        }
    }

    private func performStream(request: URLRequest, continuation: AsyncThrowingStream<String, Error>.Continuation, parser: @escaping (String) -> String?) async {
        // 使用 cachePolicy 忽略缓存，强制发起网络请求
        var newReq = request
        newReq.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        
        do {
            // 目前 async/await 的 bytes(for:) 方法在某些 watchOS 版本上可能不会正确触发 URLSessionTaskDelegate
            // 导致 TLS 验证无法跳过。
            // 虽然 legacyData 可以保证触发，但它不支持流式。
            // 考虑到项目必须支持流式输出，我们会先尝试用 bytes(for:)。
            // 如果仍然有问题，请确保 Info.plist 的 ATS Exceptions 设置正确。
            
            let (result, response) = try await session.bytes(for: newReq)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                continuation.yield("❌ HTTP Error: \(httpResponse.statusCode)")
                continuation.finish(throwing: URLError(.badServerResponse))
                return
            }
            
            for try await line in result.lines {
                if let text = parser(line) { continuation.yield(text) }
            }
            continuation.finish()
        } catch {
            print("❌ Stream Error: \(error)")
            // 如果遇到 SSL 错误，尝试降级为 legacyData 获取全文（虽然不是流式，但至少能用）
            if (error as NSError).domain == NSURLErrorDomain && (error as NSError).code == NSURLErrorServerCertificateUntrusted {
                 do {
                     print("⚠️ TLS Error detected, fallback to legacyData...")
                     let (data, _) = try await legacyData(for: newReq)
                     if let str = String(data: data, encoding: .utf8) {
                         // 将全文当作一行处理
                         if let text = parser("data: " + str) { continuation.yield(text) } // 模拟流式格式
                     }
                     continuation.finish()
                 } catch {
                     continuation.finish(throwing: error)
                 }
            } else {
                continuation.finish(throwing: error)
            }
        }
    }
}

// MARK: - Private Network Response Models
// 这些结构体是 LLMService 私有的，主线程看不到，因此不会报错
private struct PrivateOpenAIModelListResponse: Codable {
    let data: [PrivateOpenAIModel]
}
private struct PrivateOpenAIModel: Codable, Identifiable {
    let id: String
}
private struct PrivateOpenAIStreamResponse: Decodable {
    let choices: [PrivateStreamChoice]
}
private struct PrivateStreamChoice: Decodable {
    let delta: PrivateStreamDelta
}
private struct PrivateStreamDelta: Decodable {
    let content: String?
    let reasoning_content: String? // 智谱AI等模型的思考内容字段
}
private struct PrivateGeminiModelListResponse: Codable {
    let models: [PrivateGeminiModelRaw]
}
private struct PrivateGeminiModelRaw: Codable {
    let name: String
}
