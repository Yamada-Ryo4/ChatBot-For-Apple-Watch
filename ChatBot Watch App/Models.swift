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
    var apiKeys: [String] = []           // 支持多个 API Key
    var currentKeyIndex: Int = 0          // 当前使用的 Key 索引
    var isPreset: Bool
    var icon: String
    var apiType: APIType = .openAI
    var savedModels: [AIModelInfo] = []
    var isValidated: Bool = false
    
    // 兼容性：保留单 Key 访问接口
    var apiKey: String {
        get { apiKeys.isEmpty ? "" : apiKeys[min(currentKeyIndex, max(0, apiKeys.count - 1))] }
        set {
            if apiKeys.isEmpty { apiKeys = [newValue] }
            else if currentKeyIndex < apiKeys.count { apiKeys[currentKeyIndex] = newValue }
            else { apiKeys.append(newValue) }
        }
    }
    
    // 轮询到下一个 Key
    mutating func rotateKey() {
        guard apiKeys.count > 1 else { return }
        currentKeyIndex = (currentKeyIndex + 1) % apiKeys.count
    }
    
    // 兼容旧数据的初始化器
    init(name: String, baseURL: String, apiKey: String, isPreset: Bool, icon: String, apiType: APIType = .openAI, savedModels: [AIModelInfo] = [], isValidated: Bool = false) {
        self.name = name
        self.baseURL = baseURL
        self.apiKeys = apiKey.isEmpty ? [] : [apiKey]
        self.currentKeyIndex = 0
        self.isPreset = isPreset
        self.icon = icon
        self.apiType = apiType
        self.savedModels = savedModels
        self.isValidated = isValidated
    }
}

struct AIModelInfo: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var displayName: String?
    var name: String { id }
}
