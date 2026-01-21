import Foundation

// MARK: - 基础枚举

enum APIType: String, Codable, Sendable, CaseIterable, Identifiable {
    case openAI = "OpenAI 兼容"
    case gemini = "Google Gemini"
    var id: String { rawValue }
}

enum Role: String, Codable, Sendable {
    case user
    case assistant
    case system
    var apiValue: String { rawValue }
}

// MARK: - 核心数据结构

struct ChatMessage: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var role: Role
    var text: String
    var imageData: Data? = nil
    var thinkingContent: String? = nil
    var isThinkingExpanded: Bool = false
}

struct ChatSession: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var title: String
    var messages: [ChatMessage]
    var lastModified: Date
}

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

struct AIModelInfo: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var displayName: String?
    var name: String { id }
}
