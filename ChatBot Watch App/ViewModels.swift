import SwiftUI
import PhotosUI
import Combine
import WatchKit
import ClockKit
import ImageIO
@MainActor
class ChatViewModel: ObservableObject {
    @AppStorage("savedProviders_v3") var savedProvidersData: Data = Data()
    @AppStorage("selectedGlobalModelID") var selectedGlobalModelID: String = ""
    @AppStorage("showModelNameInNavBar") var showModelNameInNavBar: Bool = true  // 显示顶部模型名称
    @AppStorage("showScrollToBottomButton") var showScrollToBottomButton: Bool = true  // 显示回到底部按钮
    @AppStorage("enableHapticFeedback") var enableHapticFeedback: Bool = true  // 启用振动反馈
    @AppStorage("historyMessageCount") var historyMessageCount: Int = 10  // 携带的对话历史数量
    @AppStorage("customSystemPrompt") var customSystemPrompt: String = ""  // 自定义系统提示词
    @AppStorage("temperature") var temperature: Double = 0.7  // 温度参数 (0.0-2.0)
    @AppStorage("latexRenderingEnabled") var latexRenderingEnabled: Bool = true  // 启用 LaTeX 数学格式渲染
    @AppStorage("advancedLatexEnabled") var advancedLatexEnabled: Bool = false  // 高级渲染模式（可能导致排版问题）
    @Published var providers: [ProviderConfig] = []
    @Published var sessions: [ChatSession] = []
    @Published var currentSessionId: UUID?
    @Published var inputText: String = ""
    @Published var isLoading: Bool = false
    @Published var isInputVisible: Bool = true  // 输入框是否可见（用于显示回到底部按钮）
    @Published var selectedImageItem: PhotosPickerItem? = nil
    @Published var selectedImageData: Data? = nil
    private let service = LLMService()
    private var currentTask: Task<Void, Never>?
    
    /// 停止当前生成
    func stopGeneration() {
        currentTask?.cancel()
        currentTask = nil
        isLoading = false
    }
    init() {
        // 使用 v15 强制刷新预设，内置用户配置的 Key
        let hasLoaded = UserDefaults.standard.bool(forKey: "hasLoadedPresets_v15")
        if hasLoaded, let decoded = try? JSONDecoder().decode([ProviderConfig].self, from: UserDefaults.standard.data(forKey: "savedProviders_v3") ?? Data()), !decoded.isEmpty {
            self.providers = decoded
        } else {
            // 智谱AI 默认配置，包含免费模型 GLM-4.6V-Flash
            let zhipuDefaultModel = AIModelInfo(id: "GLM-4.6V-Flash", displayName: "GLM-4.6V-Flash (免费)")
            let zhipuProvider = ProviderConfig(
                name: "智谱AI",
                baseURL: "https://open.bigmodel.cn/api/paas/v4",
                apiKey: "",
                isPreset: true,
                icon: "sparkles",
                apiType: .openAI,
                savedModels: [zhipuDefaultModel],
                isValidated: false
            )
            
            self.providers = [
                zhipuProvider,
                ProviderConfig(name: "OpenAI", baseURL: "https://api.openai.com/v1", apiKey: "", isPreset: true, icon: "globe"),
                ProviderConfig(name: "DeepSeek", baseURL: "https://api.deepseek.com", apiKey: "", isPreset: true, icon: "brain"),
                ProviderConfig(name: "硅基流动", baseURL: "https://api.siliconflow.cn/v1", apiKey: "", isPreset: true, icon: "cpu"),
                ProviderConfig(name: "阿里云百炼", baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1", apiKey: "", isPreset: true, icon: "cloud"),
                ProviderConfig(name: "ModelScope", baseURL: "https://api-inference.modelscope.cn/v1", apiKey: "", isPreset: true, icon: "cube"),
                ProviderConfig(name: "OpenRouter", baseURL: "https://openrouter.ai/api/v1", apiKey: "", isPreset: true, icon: "network"),
                ProviderConfig(name: "Gemini", baseURL: "https://generativelanguage.googleapis.com/v1beta", apiKey: "", isPreset: true, icon: "bolt.fill", apiType: .gemini),
                ProviderConfig(name: "GeminCLI", baseURL: "https://api.yamadaryo.me/v1", apiKey: "", isPreset: true, icon: "command", apiType: .openAI)
            ]
            
            // 自动选择智谱AI的默认模型
            selectedGlobalModelID = "\(zhipuProvider.id.uuidString)|\(zhipuDefaultModel.id)"
            
            UserDefaults.standard.set(true, forKey: "hasLoadedPresets_v15")
            saveProviders()
        }
        if let data = UserDefaults.standard.data(forKey: "chatSessions_v1") {
            do {
                let decoded = try JSONDecoder().decode([ChatSession].self, from: data)
                self.sessions = decoded.sorted(by: { $0.lastModified > $1.lastModified })
            } catch {
                print("⚠️ Failed to decode chat sessions: \(error)")
                self.sessions = []
            }
        }
        if sessions.isEmpty { createNewSession() }
        else if currentSessionId == nil { currentSessionId = sessions.first?.id }
        
        // 监听云端数据变更
        NotificationCenter.default.addObserver(forName: .init("CloudDataDidUpdate"), object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in self.loadFromCloud() }
        }

        // 启动定位以备用
        LocationService.shared.requestPermission()
        LocationService.shared.updateLocation()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // 从云端/本地重新加载配置
    func loadFromCloud() {
        if let decoded = try? JSONDecoder().decode([ProviderConfig].self, from: UserDefaults.standard.data(forKey: "savedProviders_v3") ?? Data()), !decoded.isEmpty {
            self.providers = decoded
            print("☁️ [ViewModel] UI refreshed from Cloud Data")
        }
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
    private func saveSessions() {
        if let encoded = try? JSONEncoder().encode(sessions) {
            UserDefaults.standard.set(encoded, forKey: "chatSessions_v1")
            
            // 写入轻量级数据供 Widget 使用，防止 OOM
            if let first = sessions.first {
                var msg = "No messages"
                if let lastM = first.messages.last(where: { $0.role != .system }) {
                    msg = lastM.text
                }
                let widgetData: [String: String] = ["title": first.title, "lastMessage": msg]
                UserDefaults.standard.set(widgetData, forKey: "widget_tiny_data")
            } else {
                 UserDefaults.standard.set(["title": "ChatBot", "lastMessage": "No conversations"], forKey: "widget_tiny_data")
            }
            // 确保 WidgetKit 刷新数据 (如果没有 App Group，这步其实无法跨进程刷新，这里主要为了逻辑完整性)
             #if canImport(WidgetKit)
             // WidgetCenter.shared.reloadAllTimelines() // 主 App 无法直接调用 WidgetCenter 刷新，除非配置了正确的目标
             #endif

            // 刷新表盘组件
            DispatchQueue.main.async {
                let server = CLKComplicationServer.sharedInstance()
                for complication in server.activeComplications ?? [] {
                    server.reloadTimeline(for: complication)
                }
            }
        }
    }
    
    var currentMessages: [ChatMessage] {
        guard let sessionId = currentSessionId, let session = sessions.first(where: { $0.id == sessionId }) else { return [] }
        return session.messages
    }
    
    /// 更新消息并保存到磁盘（用于非频繁操作）
    private func updateCurrentSessionMessages(_ newMessages: [ChatMessage]) {
        updateCurrentSessionMessagesInMemory(newMessages)
        saveSessions()
    }
    
    /// 仅更新内存中的消息（不写磁盘，用于流式输出）
    private func updateCurrentSessionMessagesInMemory(_ newMessages: [ChatMessage]) {
        guard let index = sessions.firstIndex(where: { $0.id == currentSessionId }) else { return }
        sessions[index].messages = newMessages
        sessions[index].lastModified = Date()
        
        // 改进标题生成：使用用户首条消息的前 15 字符
        if sessions[index].title == "新对话" || sessions[index].title.isEmpty {
            if let firstUserMsg = newMessages.first(where: { $0.role == .user }), !firstUserMsg.text.isEmpty {
                let cleanText = firstUserMsg.text.trimmingCharacters(in: .whitespacesAndNewlines)
                sessions[index].title = String(cleanText.prefix(15)) + (cleanText.count > 15 ? "..." : "")
            }
        }
        sessions.sort(by: { $0.lastModified > $1.lastModified })
    }
    
    // MARK: - 供应商与模型逻辑
    func saveProviders() {
        if let encoded = try? JSONEncoder().encode(providers) {
            savedProvidersData = encoded
            // 触发云端同步
            SyncService.shared.upload()
        }
    }
    
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
    // 缓存模型名称，避免重复计算
    private var _cachedModelName: String?
    private var _cachedModelID: String?
    
    var currentDisplayModelName: String {
        // 检查缓存是否有效
        if _cachedModelID == selectedGlobalModelID, let cached = _cachedModelName {
            return cached
        }
        
        // 计算新值
        let result: String
        if selectedGlobalModelID.isEmpty {
            result = "ChatBot"
        } else {
            let components = selectedGlobalModelID.split(separator: "|")
            if components.count == 2 {
                if let found = allFavoriteModels.first(where: { $0.id == selectedGlobalModelID }) {
                    let parts = found.displayName.split(separator: "/")
                    if parts.count >= 2 { result = String(parts.last!).trimmingCharacters(in: .whitespaces) }
                    else { result = found.displayName }
                } else {
                    result = String(components[1])
                }
            } else {
                result = "ChatBot"
            }
        }
        
        // 更新缓存
        _cachedModelID = selectedGlobalModelID
        _cachedModelName = result
        return result
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
        if enableHapticFeedback { WKInterfaceDevice.current().play(.click) } // 开始生成震动
        msgs.append(ChatMessage(role: .assistant, text: ""))
        updateCurrentSessionMessages(msgs)
        let botIndex = msgs.count - 1
        
        currentTask = Task {
            let history = buildHistoryWithContext(from: msgs)

            var responseText = ""
            var thinkingText = ""
            do {
                let stream = service.streamChat(messages: history, modelId: modelID, config: provider, temperature: temperature)
                for try await chunk in stream {
                    // 检查是否被取消
                    if Task.isCancelled { break }
                    
                    // 解析思考内容（使用 🧠THINK: 前缀标记）
                    var remainingChunk = chunk
                    while let thinkRange = remainingChunk.range(of: "🧠THINK:") {
                        let beforeThink = String(remainingChunk[..<thinkRange.lowerBound])
                        if !beforeThink.isEmpty {
                            responseText += beforeThink
                        }
                        remainingChunk = String(remainingChunk[thinkRange.upperBound...])
                        if let nextThinkRange = remainingChunk.range(of: "🧠THINK:") {
                            thinkingText += String(remainingChunk[..<nextThinkRange.lowerBound])
                            remainingChunk = String(remainingChunk[nextThinkRange.lowerBound...])
                        } else {
                            thinkingText += remainingChunk
                            remainingChunk = ""
                        }
                    }
                    if !remainingChunk.isEmpty {
                        responseText += remainingChunk
                    }
                    
                    let (parsedThinking, parsedContent) = parseThinkTags(responseText)
                    let finalThinking = thinkingText + (parsedThinking ?? "")
                    let finalContent = parsedContent
                    
                    if var currentMsgs = sessions.first(where: { $0.id == currentSessionId })?.messages, botIndex < currentMsgs.count {
                        currentMsgs[botIndex].text = finalContent
                        currentMsgs[botIndex].thinkingContent = finalThinking.isEmpty ? nil : finalThinking
                        updateCurrentSessionMessagesInMemory(currentMsgs) // 流式输出时仅更新内存
                        
                        // 轻微触觉反馈 (每收到一部分内容震动太频繁，这里可以不加，或者仅在思考结束时加)
                        // WKInterfaceDevice.current().play(.click)
                    }
                }
                // 流式输出完成后，一次性保存到磁盘
                saveSessions()
                // 生成完成：成功震动
                if enableHapticFeedback { WKInterfaceDevice.current().play(.success) }
            } catch {
                // 如果是取消错误，标记为用户停止
                if Task.isCancelled {
                    if var currentMsgs = sessions.first(where: { $0.id == currentSessionId })?.messages, botIndex < currentMsgs.count {
                        if !currentMsgs[botIndex].text.isEmpty {
                            currentMsgs[botIndex].text += "\n[已停止]"
                        }
                        updateCurrentSessionMessagesInMemory(currentMsgs)
                    }
                    saveSessions() // 停止后保存
                    // 停止震动 (使用 click 或 directionDown)
                    if enableHapticFeedback { WKInterfaceDevice.current().play(.directionDown) }
                } else if var currentMsgs = sessions.first(where: { $0.id == currentSessionId })?.messages, botIndex < currentMsgs.count {
                    if responseText.isEmpty { currentMsgs[botIndex].text = "❌ \(error.localizedDescription)" }
                    else { currentMsgs[botIndex].text += "\n[中断]" }
                    updateCurrentSessionMessagesInMemory(currentMsgs)
                    saveSessions() // 错误后保存
                    // 错误震动
                    if enableHapticFeedback { WKInterfaceDevice.current().play(.failure) }
                }
            }
            isLoading = false
            currentTask = nil
        }
    }
    
    /// 解析 <think>...</think> 标签，返回 (思考内容, 剩余内容)
    private func buildHistoryWithContext(from msgs: [ChatMessage]) -> [ChatMessage] {
        var history = msgs.dropLast(1).suffix(historyMessageCount).map { $0 }
        
        // 构造系统上下文
        var systemParts: [String] = []
        
        // 1. 用户自定义提示词（优先级最高）
        if !customSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            systemParts.append(customSystemPrompt)
        }
        
        // 2. 时间和位置信息
        let currentTime = Date().formatted(date: .numeric, time: .standard)
        var contextInfo = "Current Time: \(currentTime)"
        if let location = LocationService.shared.locationInfo {
             let cleanLoc = location.replacingOccurrences(of: "Location: ", with: "")
             contextInfo += "; Location: \(cleanLoc)"
        }
        systemParts.append(contextInfo)
        
        // 合并系统消息
        let systemMsg = ChatMessage(role: .system, text: systemParts.joined(separator: "\n\n"))
        history.insert(systemMsg, at: 0)
        
        return history
    }

    private func parseThinkTags(_ text: String) -> (thinking: String?, content: String) {
        var thinking = ""
        var content = text
        
        // 匹配 <think> 和 </think> 标签（包括未闭合的情况）
        let openTag = "<think>"
        let closeTag = "</think>"
        
        while let openRange = content.range(of: openTag, options: .caseInsensitive) {
            let beforeThink = String(content[..<openRange.lowerBound])
            let afterOpen = String(content[openRange.upperBound...])
            
            if let closeRange = afterOpen.range(of: closeTag, options: .caseInsensitive) {
                // 找到闭合标签
                thinking += String(afterOpen[..<closeRange.lowerBound])
                content = beforeThink + String(afterOpen[closeRange.upperBound...])
            } else {
                // 未闭合，剩余部分都是思考内容（流式场景）
                thinking += afterOpen
                content = beforeThink
                break
            }
        }
        
        return (thinking.isEmpty ? nil : thinking, content)
    }
    
    func appendSystemMessage(_ text: String) {
        if currentSessionId == nil { createNewSession() }
        var msgs = currentMessages
        msgs.append(ChatMessage(role: .assistant, text: text))
        updateCurrentSessionMessages(msgs)
    }
    func clearCurrentChat() { updateCurrentSessionMessages([]) }
    
    /// 重新生成最后一条回复
    func regenerateLastMessage() {
        guard !isLoading else { return }
        var msgs = currentMessages
        
        // 移除最后一条 assistant 消息
        while let last = msgs.last, last.role == .assistant {
            msgs.removeLast()
        }
        
        // 找到最后一条 user 消息
        guard let lastUserMsg = msgs.last, lastUserMsg.role == .user else { return }
        
        // 重新发送
        let components = selectedGlobalModelID.split(separator: "|")
        guard components.count == 2,
              let providerID = UUID(uuidString: String(components[0])),
              let modelID = String(components[1]) as String?,
              let provider = providers.first(where: { $0.id == providerID }),
              !provider.apiKey.isEmpty else { return }
        
        updateCurrentSessionMessages(msgs)
        isLoading = true
        msgs.append(ChatMessage(role: .assistant, text: ""))
        updateCurrentSessionMessages(msgs)
        let botIndex = msgs.count - 1
        
        currentTask = Task {
            let history = buildHistoryWithContext(from: msgs)
            var responseText = ""
            var thinkingText = ""
            do {
                let stream = service.streamChat(messages: history, modelId: modelID, config: provider, temperature: temperature)
                for try await chunk in stream {
                    if Task.isCancelled { break }
                    
                    var remainingChunk = chunk
                    while let thinkRange = remainingChunk.range(of: "🧠THINK:") {
                        let beforeThink = String(remainingChunk[..<thinkRange.lowerBound])
                        if !beforeThink.isEmpty { responseText += beforeThink }
                        remainingChunk = String(remainingChunk[thinkRange.upperBound...])
                        if let nextThinkRange = remainingChunk.range(of: "🧠THINK:") {
                            thinkingText += String(remainingChunk[..<nextThinkRange.lowerBound])
                            remainingChunk = String(remainingChunk[nextThinkRange.lowerBound...])
                        } else {
                            thinkingText += remainingChunk
                            remainingChunk = ""
                        }
                    }
                    if !remainingChunk.isEmpty { responseText += remainingChunk }
                    
                    let (parsedThinking, parsedContent) = parseThinkTags(responseText)
                    let finalThinking = thinkingText + (parsedThinking ?? "")
                    let finalContent = parsedContent
                    
                    if var currentMsgs = sessions.first(where: { $0.id == currentSessionId })?.messages, botIndex < currentMsgs.count {
                        currentMsgs[botIndex].text = finalContent
                        currentMsgs[botIndex].thinkingContent = finalThinking.isEmpty ? nil : finalThinking
                        updateCurrentSessionMessages(currentMsgs)
                    }
                }
            } catch {
                if Task.isCancelled {
                    if var currentMsgs = sessions.first(where: { $0.id == currentSessionId })?.messages, botIndex < currentMsgs.count {
                        if !currentMsgs[botIndex].text.isEmpty {
                            currentMsgs[botIndex].text += "\n[已停止]"
                        }
                        updateCurrentSessionMessages(currentMsgs)
                    }
                } else if var currentMsgs = sessions.first(where: { $0.id == currentSessionId })?.messages, botIndex < currentMsgs.count {
                    if responseText.isEmpty { currentMsgs[botIndex].text = "❌ \(error.localizedDescription)" }
                    else { currentMsgs[botIndex].text += "\n[中断]" }
                    updateCurrentSessionMessages(currentMsgs)
                }
            }
            isLoading = false
            currentTask = nil
        }
    }
    
    func loadImage() {
        Task {
            if let data = try? await selectedImageItem?.loadTransferable(type: Data.self) {
                // 使用 ImageIO 直接从 Data 下采样，避免解码全图导致 Watch 内存溢出 (OOM)
                // 提升分辨率至 1200px 以确保试卷/文档清晰可读
                if let downsampled = data.downsampled(to: 1200) {
                     // 0.6 质量通常在体积和清晰度之间有很好的平衡
                     self.selectedImageData = downsampled.jpegData(compressionQuality: 0.6)
                } else {
                     self.selectedImageData = data
                }
            }
        }
    }
    
    // MARK: - 消息编辑逻辑
    @Published var editingMessageID: UUID?
    @Published var editingText: String = ""
    
    func startEditing(message: ChatMessage) {
        stopGeneration() // 假如正在生成，先停止
        editingMessageID = message.id
        editingText = message.text
    }
    
    func cancelEditing() {
        editingMessageID = nil
        editingText = ""
    }
    
    func submitEdit() {
        guard let editingID = editingMessageID, !editingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        var msgs = currentMessages
        guard let index = msgs.firstIndex(where: { $0.id == editingID }) else { return }
        
        // 1. 更新该条消息文本
        msgs[index].text = editingText
        
        // 2. 移除该条消息之后的所有消息（清除旧的上下文和回复）
        if index < msgs.count - 1 {
            msgs.removeSubrange((index + 1)...)
        }
        
        // 3. 准备重新生成
        updateCurrentSessionMessages(msgs)
        cancelEditing() // 退出编辑模式
        
        // 4. 触发生成逻辑
        let components = selectedGlobalModelID.split(separator: "|")
        guard components.count == 2,
              let providerID = UUID(uuidString: String(components[0])),
              let modelID = String(components[1]) as String?,
              let provider = providers.first(where: { $0.id == providerID }),
              !provider.apiKey.isEmpty else { return }
        
        isLoading = true
        msgs.append(ChatMessage(role: .assistant, text: ""))
        updateCurrentSessionMessages(msgs)
        let botIndex = msgs.count - 1
        
        currentTask = Task {
            let history = buildHistoryWithContext(from: msgs)
            var responseText = ""
            var thinkingText = ""
            do {
                let stream = service.streamChat(messages: history, modelId: modelID, config: provider, temperature: temperature)
                for try await chunk in stream {
                    if Task.isCancelled { break }
                    
                    var remainingChunk = chunk
                    while let thinkRange = remainingChunk.range(of: "🧠THINK:") {
                        let beforeThink = String(remainingChunk[..<thinkRange.lowerBound])
                        if !beforeThink.isEmpty { responseText += beforeThink }
                        remainingChunk = String(remainingChunk[thinkRange.upperBound...])
                        if let nextThinkRange = remainingChunk.range(of: "🧠THINK:") {
                            thinkingText += String(remainingChunk[..<nextThinkRange.lowerBound])
                            remainingChunk = String(remainingChunk[nextThinkRange.lowerBound...])
                        } else {
                            thinkingText += remainingChunk
                            remainingChunk = ""
                        }
                    }
                    if !remainingChunk.isEmpty { responseText += remainingChunk }
                    
                    let (parsedThinking, parsedContent) = parseThinkTags(responseText)
                    let finalThinking = thinkingText + (parsedThinking ?? "")
                    let finalContent = parsedContent
                    
                    if var currentMsgs = sessions.first(where: { $0.id == currentSessionId })?.messages, botIndex < currentMsgs.count {
                        currentMsgs[botIndex].text = finalContent
                        currentMsgs[botIndex].thinkingContent = finalThinking.isEmpty ? nil : finalThinking
                        updateCurrentSessionMessages(currentMsgs)
                    }
                }
            } catch {
                if Task.isCancelled {
                    if var currentMsgs = sessions.first(where: { $0.id == currentSessionId })?.messages, botIndex < currentMsgs.count {
                        if !currentMsgs[botIndex].text.isEmpty {
                            currentMsgs[botIndex].text += "\n[已停止]"
                        }
                        updateCurrentSessionMessages(currentMsgs)
                    }
                } else if var currentMsgs = sessions.first(where: { $0.id == currentSessionId })?.messages, botIndex < currentMsgs.count {
                    if responseText.isEmpty { currentMsgs[botIndex].text = "❌ \(error.localizedDescription)" }
                    else { currentMsgs[botIndex].text += "\n[中断]" }
                    updateCurrentSessionMessages(currentMsgs)
                }
            }
            isLoading = false
            currentTask = nil
        }
    }
}

extension Data {
    /// 使用 ImageIO 进行高效下采样，避免内存峰值
    func downsampled(to maxDimension: CGFloat) -> UIImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(self as CFData, options) else { return nil }
        
        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ] as CFDictionary
        
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
