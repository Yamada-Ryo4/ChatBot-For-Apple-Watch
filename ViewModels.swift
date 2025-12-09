import SwiftUI
import PhotosUI
import Combine

@MainActor
class ChatViewModel: ObservableObject {
    @AppStorage("savedProviders_v3") var savedProvidersData: Data = Data()
    @AppStorage("selectedGlobalModelID") var selectedGlobalModelID: String = ""
    @Published var providers: [ProviderConfig] = []
    @Published var sessions: [ChatSession] = []
    @Published var currentSessionId: UUID?
    @Published var inputText: String = ""
    @Published var isLoading: Bool = false
    @Published var selectedImageItem: PhotosPickerItem? = nil
    @Published var selectedImageData: Data? = nil
    private let service = LLMService()
    
    init() {
        // 使用 v8 强制刷新预设，确保你的修改生效
        let hasLoaded = UserDefaults.standard.bool(forKey: "hasLoadedPresets_v8")
        if hasLoaded, let decoded = try? JSONDecoder().decode([ProviderConfig].self, from: UserDefaults.standard.data(forKey: "savedProviders_v3") ?? Data()), !decoded.isEmpty {
            self.providers = decoded
        } else {
            self.providers = [
                ProviderConfig(name: "OpenAI (官方)", baseURL: "https://api.openai.com/v1", apiKey: "", isPreset: true, icon: "globe"),
                ProviderConfig(name: "DeepSeek", baseURL: "https://api.deepseek.com", apiKey: "", isPreset: true, icon: "brain"),
                ProviderConfig(name: "硅基流动", baseURL: "https://api.siliconflow.cn/v1", apiKey: "", isPreset: true, icon: "cpu"),
                ProviderConfig(name: "智谱AI", baseURL: "https://open.bigmodel.cn/api/paas/v4", apiKey: "", isPreset: true, icon: "sparkles"),
                ProviderConfig(name: "阿里云百炼", baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1", apiKey: "", isPreset: true, icon: "cloud"),
                ProviderConfig(name: "ModelScope", baseURL: "https://api-inference.modelscope.cn/v1", apiKey: "", isPreset: true, icon: "cube"),
                ProviderConfig(name: "OpenRouter", baseURL: "https://openrouter.ai/api/v1", apiKey: "", isPreset: true, icon: "network"),
                ProviderConfig(name: "Gemini", baseURL: "https://gemini.yamadaryo.me", apiKey: "", isPreset: true, icon: "bolt.fill", apiType: .gemini)
            ]
            UserDefaults.standard.set(true, forKey: "hasLoadedPresets_v8")
            saveProviders()
        }
        if let data = UserDefaults.standard.data(forKey: "chatSessions_v1"), let decoded = try? JSONDecoder().decode([ChatSession].self, from: data) { self.sessions = decoded.sorted(by: { $0.lastModified > $1.lastModified }) }
        if sessions.isEmpty { createNewSession() }
        else if currentSessionId == nil { currentSessionId = sessions.first?.id }
    }
    
    // MARK: - 会话管理
    func createNewSession() {
        let newSession = ChatSession(title: "新对话", messages: [], lastModified: Date())
        sessions.insert(newSession, at: 0)
        currentSessionId = newSession.id
        saveSessions()
    }
    func selectSession(_ session: ChatSession) { currentSessionId = session.id }
    func deleteSession(at offsets: IndexSet) {
        let idsToDelete = offsets.map { sessions[$0].id }
        sessions.remove(atOffsets: offsets)
        if let current = currentSessionId, idsToDelete.contains(current) { if let first = sessions.first { currentSessionId = first.id } else { createNewSession() } }
        saveSessions()
    }
    private func saveSessions() { if let encoded = try? JSONEncoder().encode(sessions) { UserDefaults.standard.set(encoded, forKey: "chatSessions_v1") } }
    
    var currentMessages: [ChatMessage] {
        guard let sessionId = currentSessionId, let session = sessions.first(where: { $0.id == sessionId }) else { return [] }
        return session.messages
    }
    private func updateCurrentSessionMessages(_ newMessages: [ChatMessage]) {
        guard let index = sessions.firstIndex(where: { $0.id == currentSessionId }) else { return }
        sessions[index].messages = newMessages
        sessions[index].lastModified = Date()
        if newMessages.count == 1, let firstText = newMessages.first?.text, !firstText.isEmpty { sessions[index].title = String(firstText.prefix(10)) }
        sessions.sort(by: { $0.lastModified > $1.lastModified })
        saveSessions()
    }
    
    // MARK: - 供应商与模型逻辑
    func saveProviders() { if let encoded = try? JSONEncoder().encode(providers) { savedProvidersData = encoded } }
    
    func fetchModelsForProvider(providerID: UUID) async {
        guard let index = providers.firstIndex(where: { $0.id == providerID }) else { return }
        let provider = providers[index]
        guard !provider.apiKey.isEmpty else { return }
        do {
            let models = try await service.fetchModels(config: provider)
            self.providers[index].savedModels = models
            self.providers[index].isValidated = true
            saveProviders()
        } catch { self.providers[index].isValidated = false }
    }
    
    func toggleModelFavorite(providerID: UUID, model: AIModelInfo) {
        guard let index = providers.firstIndex(where: { $0.id == providerID }) else { return }
        var currentSaved = providers[index].savedModels
        if let existIndex = currentSaved.firstIndex(where: { $0.id == model.id }) { currentSaved.remove(at: existIndex) }
        else { currentSaved.append(model) }
        providers[index].savedModels = currentSaved
        saveProviders()
    }
    
    func addCustomModel(providerID: UUID, modelID: String, displayName: String) {
        guard let index = providers.firstIndex(where: { $0.id == providerID }) else { return }
        let newModel = AIModelInfo(id: modelID, displayName: displayName.isEmpty ? nil : displayName)
        var currentSaved = providers[index].savedModels
        if let existIndex = currentSaved.firstIndex(where: { $0.id == modelID }) { currentSaved.remove(at: existIndex) }
        currentSaved.insert(newModel, at: 0)
        providers[index].savedModels = currentSaved
        saveProviders()
    }
    
    var allFavoriteModels: [(id: String, displayName: String)] {
        var list: [(String, String)] = []
        for provider in providers {
            for model in provider.savedModels {
                let compositeID = "\(provider.id.uuidString)|\(model.id)"
                let nameToShow = model.displayName ?? model.id
                let displayName = "\(provider.name) / \(nameToShow)"
                list.append((compositeID, displayName))
            }
        }
        return list
    }
    
    var currentDisplayModelName: String {
        if selectedGlobalModelID.isEmpty { return "ChatBot" }
        let components = selectedGlobalModelID.split(separator: "|")
        if components.count == 2 {
            if let found = allFavoriteModels.first(where: { $0.id == selectedGlobalModelID }) {
                let parts = found.displayName.split(separator: "/")
                if parts.count >= 2 { return String(parts.last!).trimmingCharacters(in: .whitespaces) }
                return found.displayName
            }
            return String(components[1])
        }
        return "ChatBot"
    }
    
    func sendMessage() {
        guard (!inputText.isEmpty || selectedImageData != nil) else { return }
        let components = selectedGlobalModelID.split(separator: "|")
        guard components.count == 2, let providerID = UUID(uuidString: String(components[0])), let modelID = String(components[1]) as String? else {
            appendSystemMessage("⚠️ 请先在设置中选择一个模型"); return
        }
        guard let provider = providers.first(where: { $0.id == providerID }) else {
            appendSystemMessage("⚠️ 找不到供应商配置"); return
        }
        if provider.apiKey.isEmpty { appendSystemMessage("⚠️ \(provider.name) 未配置 API Key"); return }
        
        if currentSessionId == nil { createNewSession() }
        var msgs = currentMessages
        let userMsg = ChatMessage(role: .user, text: inputText, imageData: selectedImageData)
        msgs.append(userMsg)
        updateCurrentSessionMessages(msgs)
        
        inputText = ""; selectedImageItem = nil; selectedImageData = nil; isLoading = true
        msgs.append(ChatMessage(role: .assistant, text: ""))
        updateCurrentSessionMessages(msgs)
        let botIndex = msgs.count - 1
        
        Task {
            let history = msgs.dropLast(1).suffix(10).map { $0 }
            var responseText = ""
            do {
                let stream = service.streamChat(messages: history, modelId: modelID, config: provider)
                for try await chunk in stream {
                    responseText += chunk
                    if var currentMsgs = sessions.first(where: { $0.id == currentSessionId })?.messages, botIndex < currentMsgs.count {
                        currentMsgs[botIndex].text = responseText
                        updateCurrentSessionMessages(currentMsgs)
                    }
                }
            } catch {
                if var currentMsgs = sessions.first(where: { $0.id == currentSessionId })?.messages, botIndex < currentMsgs.count {
                    if responseText.isEmpty { currentMsgs[botIndex].text = "❌ \(error.localizedDescription)" }
                    else { currentMsgs[botIndex].text += "\n[中断]" }
                    updateCurrentSessionMessages(currentMsgs)
                }
            }
            isLoading = false
        }
    }
    
    func appendSystemMessage(_ text: String) {
        if currentSessionId == nil { createNewSession() }
        var msgs = currentMessages
        msgs.append(ChatMessage(role: .assistant, text: text))
        updateCurrentSessionMessages(msgs)
    }
    func clearCurrentChat() { updateCurrentSessionMessages([]) }
    func loadImage() {
        Task { if let data = try? await selectedImageItem?.loadTransferable(type: Data.self), let uiImage = UIImage(data: data) { self.selectedImageData = uiImage.jpegData(compressionQuality: 0.5) } }
    }
}
