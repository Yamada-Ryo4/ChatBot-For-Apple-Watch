import Foundation

// 接口类型
enum APIType: String, Codable, Sendable, CaseIterable, Identifiable {
    case openAI = "OpenAI 兼容"
    case gemini = "Google Gemini"
    var id: String { rawValue }
}

// 聊天角色
enum Role: String, Codable, Sendable {
    case user
    case assistant
    case system
    var apiValue: String { rawValue }
}

// 消息结构
struct ChatMessage: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var role: Role
    var text: String
    var imageData: Data? = nil
}

// 对话会话
struct ChatSession: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var title: String
    var messages: [ChatMessage]
    var lastModified: Date
}

// 供应商配置
struct ProviderConfig: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var baseURL: String
    var apiKey: String
    var isPreset: Bool
    var icon: String
    var apiType: APIType = .openAI
    var savedModels: [AIModelInfo] = []
    var isValidated: Bool = false
}

// 模型信息
struct AIModelInfo: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var displayName: String?
    var name: String { id }
}

// MARK: - 网络响应结构
struct OpenAIModelListResponse: Codable, Sendable {
    let data: [OpenAIModel]
}
struct OpenAIModel: Codable, Identifiable, Sendable {
    let id: String
}
struct OpenAIStreamResponse: Decodable, Sendable {
    let choices: [StreamChoice]
}
struct StreamChoice: Decodable, Sendable {
    let delta: StreamDelta
}
struct StreamDelta: Decodable, Sendable {
    let content: String?
}
struct GeminiModelListResponse: Codable, Sendable {
    let models: [GeminiModelRaw]
}
struct GeminiModelRaw: Codable, Sendable {
    let name: String
}
