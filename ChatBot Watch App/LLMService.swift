import Foundation

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
        case .openAI, .openAIResponses: return try await fetchOpenAIModels(baseURL: config.baseURL, apiKey: config.apiKey)
        case .gemini: return try await fetchGeminiModels(baseURL: config.baseURL, apiKey: config.apiKey)
        case .anthropic: return try await fetchAnthropicModels(baseURL: config.baseURL, apiKey: config.apiKey)
        case .workersAI: return [] // Workers AI 无模型列表接口
        }
    }

    func streamChat(messages: [ChatMessage], modelId: String, config: ProviderConfig, temperature: Double = 0.7) -> AsyncThrowingStream<String, Error> {
        switch config.apiType {
        case .openAI: return streamOpenAIChat(messages: messages, modelId: modelId, baseURL: config.baseURL, apiKey: config.apiKey, temperature: temperature)
        case .gemini: return streamGeminiChat(messages: messages, modelId: modelId, baseURL: config.baseURL, apiKey: config.apiKey, temperature: temperature)
        case .openAIResponses: return streamOpenAIResponses(messages: messages, modelId: modelId, baseURL: config.baseURL, apiKey: config.apiKey, temperature: temperature)
        case .anthropic: return streamAnthropicChat(messages: messages, modelId: modelId, baseURL: config.baseURL, apiKey: config.apiKey, temperature: temperature)
        case .workersAI: return streamOpenAIChat(messages: messages, modelId: modelId, baseURL: config.baseURL, apiKey: config.apiKey, temperature: temperature)
        }
    }
    
    // MARK: - v1.7: Embedding API
    
    func fetchEmbedding(text: String, modelId: String, config: ProviderConfig, dimensions: Int? = nil) async throws -> [Float] {
        switch config.apiType {
        case .openAI, .openAIResponses:
            return try await fetchOpenAIEmbedding(text: text, modelId: modelId, baseURL: config.baseURL, apiKey: config.apiKey, dimensions: dimensions)
        case .gemini:
            return try await fetchGeminiEmbedding(text: text, modelId: modelId, baseURL: config.baseURL, apiKey: config.apiKey, dimensions: dimensions)
        case .workersAI:
            return try await fetchWorkersAIEmbedding(text: text, baseURL: config.baseURL)
        case .anthropic:
            throw NSError(domain: "Embedding", code: -1, userInfo: [NSLocalizedDescriptionKey: "Anthropic 不支持 Embedding API"])
        }
    }
    
    // MARK: - Workers AI Embedding
    
    private func fetchWorkersAIEmbedding(text: String, baseURL: String) async throws -> [Float] {
        let urlString = baseURL.hasPrefix("http") ? baseURL : "https://\(baseURL)"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["text": text])
        
        let (data, _) = try await session.data(for: request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArr = json["data"] as? [[Double]],
              let first = dataArr.first else {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? String {
                throw NSError(domain: "Embedding", code: -1, userInfo: [NSLocalizedDescriptionKey: error])
            }
            throw NSError(domain: "Embedding", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法解析 Workers AI 响应"])
        }
        return first.map { Float($0) }
    }
    
    private func fetchOpenAIEmbedding(text: String, modelId: String, baseURL: String, apiKey: String, dimensions: Int? = nil) async throws -> [Float] {
        guard let req = buildRequest(baseURL: baseURL, path: "embeddings", apiKey: apiKey, type: .openAI) else {
            throw URLError(.badURL)
        }
        var request = req
        request.httpMethod = "POST"
        var body: [String: Any] = ["model": modelId, "input": text]
        if let dim = dimensions { body["dimensions"] = dim }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await session.data(for: request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArr = json["data"] as? [[String: Any]],
              let first = dataArr.first,
              let embedding = first["embedding"] as? [Double] else {
            // 检查是否有错误信息
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw NSError(domain: "Embedding", code: -1, userInfo: [NSLocalizedDescriptionKey: message])
            }
            throw NSError(domain: "Embedding", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法解析 Embedding 响应"])
        }
        return embedding.map { Float($0) }
    }
    
    private func fetchGeminiEmbedding(text: String, modelId: String, baseURL: String, apiKey: String, dimensions: Int? = nil) async throws -> [Float] {
        let path = "models/\(modelId):embedContent"
        guard let req = buildRequest(baseURL: baseURL, path: path, apiKey: apiKey, type: .gemini) else {
            throw URLError(.badURL)
        }
        var request = req
        request.httpMethod = "POST"
        var body: [String: Any] = [
            "model": "models/\(modelId)",
            "content": ["parts": [["text": text]]]
        ]
        if let dim = dimensions { body["outputDimensionality"] = dim }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await session.data(for: request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let embeddingObj = json["embedding"] as? [String: Any],
              let values = embeddingObj["values"] as? [Double] else {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw NSError(domain: "Embedding", code: -1, userInfo: [NSLocalizedDescriptionKey: message])
            }
            throw NSError(domain: "Embedding", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法解析 Gemini Embedding 响应"])
        }
        return values.map { Float($0) }
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
                
                // v1.7.1: 放宽安全限制，防止 "17岁" 等内容被误拦截
                let safetySettings: [[String: Any]] = [
                    ["category": "HARM_CATEGORY_HARASSMENT", "threshold": "BLOCK_NONE"],
                    ["category": "HARM_CATEGORY_HATE_SPEECH", "threshold": "BLOCK_NONE"],
                    ["category": "HARM_CATEGORY_SEXUALLY_EXPLICIT", "threshold": "BLOCK_NONE"],
                    ["category": "HARM_CATEGORY_DANGEROUS_CONTENT", "threshold": "BLOCK_NONE"]
                ]
                
                let body: [String: Any] = [
                    "contents": contents,
                    "generationConfig": generationConfig,
                    "safetySettings": safetySettings
                ]
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
    
    // MARK: - Anthropic Models Fetch
    private func fetchAnthropicModels(baseURL: String, apiKey: String) async throws -> [AIModelInfo] {
        // Anthropic 不提供模型列表 API，返回预设的模型列表
        return [
            AIModelInfo(id: "claude-3-5-sonnet-20241022", displayName: "Claude 3.5 Sonnet"),
            AIModelInfo(id: "claude-3-5-haiku-20241022", displayName: "Claude 3.5 Haiku"),
            AIModelInfo(id: "claude-3-opus-20240229", displayName: "Claude 3 Opus"),
            AIModelInfo(id: "claude-3-sonnet-20240229", displayName: "Claude 3 Sonnet"),
            AIModelInfo(id: "claude-3-haiku-20240307", displayName: "Claude 3 Haiku")
        ]
    }
    
    // MARK: - OpenAI Responses API (新格式)
    private func streamOpenAIResponses(messages: [ChatMessage], modelId: String, baseURL: String, apiKey: String, temperature: Double) -> AsyncThrowingStream<String, Error> {
        return AsyncThrowingStream { continuation in
            let task = Task {
                // 构建 input 数组格式
                var inputItems: [[String: Any]] = []
                for msg in messages {
                    var item: [String: Any] = ["role": msg.role.rawValue]
                    if let imgData = msg.imageData {
                        // 多模态内容
                        item["content"] = [
                            ["type": "input_text", "text": msg.text],
                            ["type": "input_image", "image_url": "data:image/jpeg;base64,\(imgData.base64EncodedString())"]
                        ]
                    } else {
                        item["content"] = msg.text
                    }
                    inputItems.append(item)
                }
                
                let body: [String: Any] = [
                    "model": modelId,
                    "input": inputItems,
                    "stream": true,
                    "temperature": temperature
                ]
                
                guard var req = buildRequest(baseURL: baseURL, path: "responses", apiKey: apiKey, type: .openAIResponses) else {
                    continuation.finish(throwing: URLError(.badURL))
                    return
                }
                req.httpMethod = "POST"
                req.httpBody = try? JSONSerialization.data(withJSONObject: body)
                
                await performStream(request: req, continuation: continuation) { line in
                    guard line.hasPrefix("data: ") else {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty && trimmed != "" {
                            print("⚠️ OpenAI Responses 非标准行: \(line.prefix(200))")
                            return "[RAW] " + line
                        }
                        return nil
                    }
                    let json = String(line.dropFirst(6))
                    if json.trimmingCharacters(in: .whitespaces) == "[DONE]" { return nil }
                    
                    if let data = json.data(using: .utf8),
                       let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        // 检查错误
                        if let error = dict["error"] as? [String: Any], let message = error["message"] as? String {
                            return "❌ API错误: " + message
                        }
                        
                        // 解析 response.output_text.delta 事件
                        if let eventType = dict["type"] as? String {
                            if eventType == "response.output_text.delta" {
                                if let delta = dict["delta"] as? String { return delta }
                            }
                            // 处理思考内容 (如果有)
                            if eventType == "response.reasoning.delta" {
                                if let delta = dict["delta"] as? String { return "🧠THINK:" + delta }
                            }
                        }
                        
                        // 兼容旧的 choices 格式 (某些兼容 API 可能使用)
                        if let choices = dict["choices"] as? [[String: Any]],
                           let delta = choices.first?["delta"] as? [String: Any],
                           let content = delta["content"] as? String {
                            return content
                        }
                    }
                    return nil
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
    
    // MARK: - Anthropic Messages API
    private func streamAnthropicChat(messages: [ChatMessage], modelId: String, baseURL: String, apiKey: String, temperature: Double) -> AsyncThrowingStream<String, Error> {
        return AsyncThrowingStream { continuation in
            let task = Task {
                // 分离 system 消息和其他消息
                var systemPrompt = ""
                var anthropicMessages: [[String: Any]] = []
                
                for msg in messages {
                    if msg.role == .system {
                        systemPrompt += (systemPrompt.isEmpty ? "" : "\n") + msg.text
                        continue
                    }
                    
                    let role = msg.role == .user ? "user" : "assistant"
                    var content: Any
                    
                    if let imgData = msg.imageData {
                        // 多模态内容
                        content = [
                            ["type": "image", "source": [
                                "type": "base64",
                                "media_type": "image/jpeg",
                                "data": imgData.base64EncodedString()
                            ]],
                            ["type": "text", "text": msg.text]
                        ]
                    } else {
                        content = msg.text
                    }
                    anthropicMessages.append(["role": role, "content": content])
                }
                
                var body: [String: Any] = [
                    "model": modelId,
                    "messages": anthropicMessages,
                    "max_tokens": 4096,
                    "stream": true,
                    "temperature": temperature
                ]
                if !systemPrompt.isEmpty {
                    body["system"] = systemPrompt
                }
                
                guard var req = buildRequest(baseURL: baseURL, path: "messages", apiKey: apiKey, type: .anthropic) else {
                    continuation.finish(throwing: URLError(.badURL))
                    return
                }
                req.httpMethod = "POST"
                req.httpBody = try? JSONSerialization.data(withJSONObject: body)
                
                await performStream(request: req, continuation: continuation) { line in
                    guard line.hasPrefix("data: ") else {
                        // 处理 event: 行（Anthropic SSE 格式）
                        if line.hasPrefix("event: ") { return nil }
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty && trimmed != "" {
                            print("⚠️ Anthropic 非标准行: \(line.prefix(200))")
                        }
                        return nil
                    }
                    let json = String(line.dropFirst(6))
                    
                    if let data = json.data(using: .utf8),
                       let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        // 检查错误
                        if let error = dict["error"] as? [String: Any], let message = error["message"] as? String {
                            return "❌ API错误: " + message
                        }
                        
                        // 解析事件类型
                        if let eventType = dict["type"] as? String {
                            switch eventType {
                            case "content_block_delta":
                                if let delta = dict["delta"] as? [String: Any] {
                                    // text delta
                                    if let text = delta["text"] as? String {
                                        return text
                                    }
                                    // thinking delta (Claude 思考模式)
                                    if let thinking = delta["thinking"] as? String {
                                        return "🧠THINK:" + thinking
                                    }
                                }
                            case "message_stop", "message_delta":
                                return nil
                            case "error":
                                if let error = dict["error"] as? [String: Any],
                                   let message = error["message"] as? String {
                                    return "❌ " + message
                                }
                            default:
                                break
                            }
                        }
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
        case .openAI, .openAIResponses, .workersAI: fullPath = "\(cleanBase)/\(path)"
        case .gemini:
            if cleanBase.contains("/v1beta") { fullPath = "\(cleanBase)/\(path)" }
            else { fullPath = "\(cleanBase)/v1beta/\(path)" }
        case .anthropic:
            if cleanBase.contains("/v1") { fullPath = "\(cleanBase)/\(path)" }
            else { fullPath = "\(cleanBase)/v1/\(path)" }
        }
        guard let url = URL(string: fullPath) else { return nil }
        var request = URLRequest(url: url)
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        // 添加 User-Agent 伪装，防止被服务端防火墙拦截导致 SSL 中断
        request.addValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        request.addValue("*/*", forHTTPHeaderField: "Accept")
        
        switch type {
        case .openAI, .openAIResponses: request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        case .gemini: request.addValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        case .anthropic:
            request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .workersAI: break // Workers AI 不需要认证
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
    let usage: PrivateUsage?  // v1.5: Token 统计
}
private struct PrivateStreamChoice: Decodable {
    let delta: PrivateStreamDelta
}
private struct PrivateStreamDelta: Decodable {
    let content: String?
    let reasoning_content: String? // 智谱AI等模型的思考内容字段
}
private struct PrivateUsage: Decodable {
    let prompt_tokens: Int?
    let completion_tokens: Int?
    let total_tokens: Int?
}
private struct PrivateGeminiModelListResponse: Codable {
    let models: [PrivateGeminiModelRaw]
}
private struct PrivateGeminiModelRaw: Codable {
    let name: String
}
