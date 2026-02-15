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
    @AppStorage("markdownRenderMode") var markdownRenderModeRaw: String = MarkdownRenderMode.realtime.rawValue  // v1.8.6: Markdown 渲染模式
    @AppStorage("advancedLatexEnabled") var advancedLatexEnabled: Bool = false  // v1.7: 启用高级 LaTeX 渲染模式（可能导致排版问题）
    @AppStorage("thinkingMode") var thinkingModeRaw: String = ThinkingMode.auto.rawValue // v1.6: 思考模式
    @AppStorage("enableMessageAnimation") var enableMessageAnimation: Bool = true  // v1.6: 消息气泡动画
    @AppStorage("appThemeRaw") var appThemeRaw: String = AppTheme.classic.rawValue  // v1.6: 主题配色
    @AppStorage("memoryEnabled") var memoryEnabled: Bool = true  // v1.7: 记忆功能开关
    @AppStorage("embeddingProviderID") var embeddingProviderID: String = ""  // v1.7: Embedding 供应商 ID
    @AppStorage("embeddingModelID") var embeddingModelID: String = ""  // v1.7: Embedding 模型 ID
    @AppStorage("helperGlobalModelID") var helperGlobalModelID: String = "" // v1.7: 辅助模型 ID（用于标题生成等）
    @Published var memories: [MemoryItem] = []  // v1.7: 记忆列表
    
    // v1.6: 主题计算属性
    var currentTheme: AppTheme {
        get { AppTheme(rawValue: appThemeRaw) ?? .classic }
        set { appThemeRaw = newValue.rawValue }
    }
    
    // v1.8.6: 渲染模式计算属性
    var markdownRenderMode: MarkdownRenderMode {
        get { MarkdownRenderMode(rawValue: markdownRenderModeRaw) ?? .realtime }
        set { markdownRenderModeRaw = newValue.rawValue }
    }
    
    // v1.7: 模型能力配置 (JSON 存储)
    @AppStorage("modelSettings") var modelSettingsData: Data = Data()
    @Published var modelSettings: [String: ModelSettings] = [:] {
        didSet { saveModelSettings() }
    }
    
    var thinkingMode: ThinkingMode {
        get { ThinkingMode(rawValue: thinkingModeRaw) ?? .auto }
        set { thinkingModeRaw = newValue.rawValue }
    }
    
    @Published var providers: [ProviderConfig] = []
    @Published var sessions: [ChatSession] = []
    @Published var currentSessionId: UUID?
    @Published var inputText: String = ""
    @Published var isLoading: Bool = false
    @Published var streamingText: String = ""          // v1.6: 流式输出专用（避免全量重渲染）
    @Published var streamingThinkingText: String = ""   // v1.6: 流式思考内容
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
        // v1.6: 清空流式状态
        streamingText = ""
        streamingThinkingText = ""
    }
    init() {
        // 定义最新的预设供应商
        let latestPresets: [ProviderConfig] = [
            ProviderConfig(name: "智谱AI", baseURL: "https://open.bigmodel.cn/api/paas/v4", apiKey: "", isPreset: true, icon: "sparkles"),
            ProviderConfig(name: "OpenAI", baseURL: "https://api.openai.com/v1", apiKey: "", isPreset: true, icon: "globe"),
            ProviderConfig(name: "Anthropic", baseURL: "https://api.anthropic.com", apiKey: "", isPreset: true, icon: "a.circle.fill", apiType: .anthropic),
            ProviderConfig(name: "DeepSeek", baseURL: "https://api.deepseek.com", apiKey: "", isPreset: true, icon: "brain"),
            ProviderConfig(name: "Nvidia", baseURL: "https://integrate.api.nvidia.com/v1", apiKey: "", isPreset: true, icon: "bolt.horizontal.fill"),
            ProviderConfig(name: "硅基流动", baseURL: "https://api.siliconflow.cn/v1", apiKey: "", isPreset: true, icon: "cpu"),
            ProviderConfig(name: "阿里云百炼", baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1", apiKey: "", isPreset: true, icon: "cloud"),
            ProviderConfig(name: "ModelScope", baseURL: "https://api-inference.modelscope.cn/v1", apiKey: "", isPreset: true, icon: "cube"),
            ProviderConfig(name: "OpenRouter", baseURL: "https://openrouter.ai/api/v1", apiKey: "", isPreset: true, icon: "network"),
            ProviderConfig(name: "Gemini", baseURL: "https://gemini.yamadaryo.me/v1beta", apiKey: "", isPreset: true, icon: "sparkle", apiType: .gemini),
            ProviderConfig(name: "OpenCode Zen", baseURL: "https://opencode.ai/zen/v1", apiKey: "", isPreset: true, icon: "bolt.fill", apiType: .openAI)
        ]
        
        if let decoded = try? JSONDecoder().decode([ProviderConfig].self, from: UserDefaults.standard.data(forKey: "savedProviders_v3") ?? Data()), !decoded.isEmpty {
            // 每次启动都同步预设属性（图标、URL、apiType），但保留用户数据
            var mergedProviders: [ProviderConfig] = []
            
            for preset in latestPresets {
                if let existing = decoded.first(where: { $0.name == preset.name && $0.isPreset }) {
                    // 同步预设属性，保留用户数据
                    var updated = preset
                    updated.id = existing.id  // 保持 ID 以维持选择状态
                    updated.availableModels = existing.availableModels
                    updated.favoriteModelIds = existing.favoriteModelIds
                    updated.isValidated = existing.isValidated
                    updated.lastUsedModelId = existing.lastUsedModelId
                    updated.modelsLastFetched = existing.modelsLastFetched
                    // 保留用户自己配置的 Key（如果预设 Key 为空 或 用户已修改过）
                    if !existing.apiKey.isEmpty {
                        updated.apiKeys = existing.apiKeys
                        updated.currentKeyIndex = existing.currentKeyIndex
                    }
                    mergedProviders.append(updated)
                } else {
                    // 新增的预设供应商
                    mergedProviders.append(preset)
                }
            }
            
            // 保留用户自定义的非预设供应商
            for custom in decoded where !custom.isPreset {
                mergedProviders.append(custom)
            }
            
            self.providers = mergedProviders
            saveProviders()
            
            // 自动验证有 Key 但未验证的供应商
            Task {
                for i in 0..<self.providers.count {
                    if !self.providers[i].apiKey.isEmpty && !self.providers[i].isValidated {
                        await self.autoValidateProvider(index: i)
                    }
                }
            }
        } else {
            // 首次安装，使用全新预设
            self.providers = latestPresets
            saveProviders()
            
            Task {
                for i in 0..<self.providers.count {
                    if !self.providers[i].apiKey.isEmpty {
                        await self.autoValidateProvider(index: i)
                    }
                }
            }
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
        
        loadModelSettings() // v1.7: 加载模型能力配置
        loadMemories()      // v1.7: 加载记忆
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
    func saveSessions() {
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
    
    // 自动验证供应商（首次启动时调用）
    private func autoValidateProvider(index: Int) async {
        guard index < providers.count else { return }
        let provider = providers[index]
        guard !provider.apiKey.isEmpty else { return }
        do {
            let models = try await service.fetchModels(config: provider)
            await MainActor.run {
                self.providers[index].savedModels = models
                self.providers[index].isValidated = true
                self.saveProviders()
            }
            print("✅ 自动验证成功: \(provider.name)")
        } catch {
            print("⚠️ 自动验证失败: \(provider.name) - \(error.localizedDescription)")
        }
    }
    
    func fetchModelsForProvider(providerID: UUID, forceRefresh: Bool = false) async {
        guard let index = providers.firstIndex(where: { $0.id == providerID }) else { return }
        let provider = providers[index]
        guard !provider.apiKey.isEmpty else { return }
        
        // 缓存逻辑：1小时内不重复获取（除非强制刷新）
        if !forceRefresh,
           let lastFetch = provider.modelsLastFetched,
           Date().timeIntervalSince(lastFetch) < 3600,
           !provider.availableModels.isEmpty {
            return
        }
        
        do {
            let models = try await service.fetchModels(config: provider)
            self.providers[index].availableModels = models
            self.providers[index].isValidated = true
            self.providers[index].modelsLastFetched = Date()
            saveProviders()
        } catch {
            self.providers[index].isValidated = false
            // 如果是认证错误且有多个 Key，尝试轮换
            if provider.apiKeys.count > 1 {
                self.providers[index].rotateKey()
                saveProviders()
            }
        }
    }
    
    // 批量验证所有有 API Key 的供应商
    func validateAllProviders() async -> (success: Int, failed: Int) {
        var success = 0
        var failed = 0
        for i in 0..<providers.count {
            guard !providers[i].apiKey.isEmpty else { continue }
            do {
                let models = try await service.fetchModels(config: providers[i])
                await MainActor.run {
                    self.providers[i].availableModels = models
                    self.providers[i].isValidated = true
                    self.providers[i].modelsLastFetched = Date()
                }
                success += 1
            } catch {
                await MainActor.run {
                    self.providers[i].isValidated = false
                }
                failed += 1
            }
        }
        await MainActor.run { saveProviders() }
        return (success, failed)
    }
    
    func toggleModelFavorite(providerID: UUID, model: AIModelInfo) {
        guard let index = providers.firstIndex(where: { $0.id == providerID }) else { return }
        providers[index].toggleFavorite(model.id)
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
    
    // 获取所有收藏的模型
    var allFavoriteModels: [(id: String, displayName: String, providerName: String)] {
        var list: [(String, String, String)] = []
        for provider in providers {
            for model in provider.availableModels where provider.isModelFavorited(model.id) {
                let compositeID = "\(provider.id.uuidString)|\(model.id)"
                let nameToShow = model.displayName ?? model.id
                list.append((compositeID, nameToShow, provider.name))
            }
        }
        return list
    }
    
    // 获取所有可用模型（按供应商分组）
    var allAvailableModels: [(provider: ProviderConfig, models: [AIModelInfo])] {
        providers.filter { !$0.availableModels.isEmpty }.map { ($0, $0.availableModels) }
    }
    
    // 获取最近使用的模型（每个供应商一个）
    var recentlyUsedModels: [(id: String, displayName: String, providerName: String)] {
        var list: [(String, String, String)] = []
        for provider in providers {
            guard let lastModelId = provider.lastUsedModelId,
                  let model = provider.availableModels.first(where: { $0.id == lastModelId }) else { continue }
            let compositeID = "\(provider.id.uuidString)|\(model.id)"
            let nameToShow = model.displayName ?? model.id
            list.append((compositeID, nameToShow, provider.name))
        }
        return list
    }
    
    // MARK: - 配置导出/导入
    
    /// 导出全部配置（含记忆和聊天记录）
    func exportConfig() -> Data? {
        let exportData = ExportableConfig(
            providers: providers,
            selectedGlobalModelID: selectedGlobalModelID,
            temperature: temperature,
            historyMessageCount: historyMessageCount,
            customSystemPrompt: customSystemPrompt,
            memories: memories,
            sessions: sessions,
            helperGlobalModelID: helperGlobalModelID
        )
        return try? JSONEncoder().encode(exportData)
    }
    
    /// 单独导出记忆
    func exportMemories() -> Data? {
        return try? JSONEncoder().encode(memories)
    }
    
    /// 单独导出聊天记录
    func exportSessions() -> Data? {
        return try? JSONEncoder().encode(sessions)
    }
    
    /// 从 JSON 数据导入配置
    func importConfig(from data: Data) throws {
        let config = try JSONDecoder().decode(ExportableConfig.self, from: data)
        self.providers = config.providers
        self.selectedGlobalModelID = config.selectedGlobalModelID
        self.temperature = config.temperature
        self.historyMessageCount = config.historyMessageCount
        self.customSystemPrompt = config.customSystemPrompt
        saveProviders()
        
        // v1.7: 导入记忆（合并，不覆盖）
        if let importedMemories = config.memories {
            for mem in importedMemories {
                if !memories.contains(where: { $0.content == mem.content }) {
                    memories.append(mem)
                }
            }
            if memories.count > maxMemoryCount {
                memories = Array(memories.prefix(maxMemoryCount))
            }
            saveMemories()
        }
        
        // v1.7: 导入聊天记录（合并）
        if let importedSessions = config.sessions {
            for session in importedSessions {
                if !sessions.contains(where: { $0.id == session.id }) {
                    sessions.append(session)
                }
            }
            saveSessions()
        }
        
        // v1.7: 导入辅助模型设置
        if let helperID = config.helperGlobalModelID {
            self.helperGlobalModelID = helperID
        }
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
        guard let providerIndex = providers.firstIndex(where: { $0.id == providerID }) else {
            appendSystemMessage("⚠️ 找不到供应商配置"); return
        }
        let provider = providers[providerIndex]
        if provider.apiKey.isEmpty { appendSystemMessage("⚠️ \(provider.name) 未配置 API Key"); return }
        
        // 记录最近使用的模型
        providers[providerIndex].lastUsedModelId = modelID
        saveProviders()
        
        if currentSessionId == nil { createNewSession() }
        var msgs = currentMessages
        
        // v1.5: 记录发送时间
        let sendTime = Date()
        var userMsg = ChatMessage(role: .user, text: inputText, imageData: selectedImageData)
        userMsg.sendTime = sendTime
        msgs.append(userMsg)
        updateCurrentSessionMessages(msgs)
        
        inputText = ""; selectedImageItem = nil; selectedImageData = nil; isLoading = true
        if enableHapticFeedback { WKInterfaceDevice.current().play(.click) } // 开始生成震动

        // v1.6: 初始化流式输出状态
        streamingText = ""
        streamingThinkingText = ""
        
        // v1.5: AI 消息也记录发送时间
        var assistantMsg = ChatMessage(role: .assistant, text: "")
        assistantMsg.sendTime = sendTime
        msgs.append(assistantMsg)
        updateCurrentSessionMessages(msgs)
        let botIndex = msgs.count - 1
        
        currentTask = Task {
            let history = await buildHistoryWithContext(from: msgs)

            var responseText = ""
            var thinkingText = ""
            
            // v1.8.1: 流式解析状态机 (优化性能)
            var isThinking = false
            var pendingBuffer = ""
            
            // v1.6: 性能优化 - 200ms 节流（只更新 streamingText，不触发全量 diff）
            var lastUIUpdateTime = Date()
            let uiUpdateInterval: TimeInterval = 0.15  // 150ms 平衡流畅度和性能
            var pendingUpdate = false
            
            do {
                let stream = service.streamChat(messages: history, modelId: modelID, config: provider, temperature: temperature)
                for try await chunk in stream {
                    // 检查是否被取消
                    if Task.isCancelled { break }
                    
                    // 1. 处理内部标记 (保留兼容性)
                    var processedChunk = chunk
                    if let range = processedChunk.range(of: "🧠THINK:") {
                         processedChunk = processedChunk.replacingOccurrences(of: "🧠THINK:", with: "")
                    }
                    
                    // 2. 追加到缓冲
                    pendingBuffer += processedChunk
                    
                    // 3. 状态机解析循环
                    while true {
                        let tag = isThinking ? "</think>" : "<think>"
                        if let range = pendingBuffer.range(of: tag, options: .caseInsensitive) {
                            // 找到标签
                            let contentBefore = String(pendingBuffer[..<range.lowerBound])
                            
                            if isThinking {
                                thinkingText += contentBefore
                                isThinking = false // 结束思考
                            } else {
                                responseText += contentBefore
                                isThinking = true // 开始思考
                            }
                            
                            // 移除已处理部分（包括标签）
                            pendingBuffer = String(pendingBuffer[range.upperBound...])
                            // 继续循环检查剩余 buffer 是否有下一个标签
                        } else {
                            // 未找到完整标签，处理安全部分
                            let keepLength = tag.count - 1
                            if pendingBuffer.count > keepLength {
                                let safeIndex = pendingBuffer.index(pendingBuffer.endIndex, offsetBy: -keepLength)
                                let safeContent = String(pendingBuffer[..<safeIndex])
                                
                                if isThinking {
                                    thinkingText += safeContent
                                } else {
                                    responseText += safeContent
                                }
                                
                                // 保留可能构成标签的后缀
                                pendingBuffer = String(pendingBuffer[safeIndex...])
                            }
                            break // 退出内层循环，等待下一个 Chunk
                        }
                    }
                    
                    // v1.6: 高性能流式更新 — 只更新 streamingText，不碰 sessions
                    let now = Date()
                    if now.timeIntervalSince(lastUIUpdateTime) >= uiUpdateInterval {
                        let finalContent = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
                        streamingText = finalContent
                        if thinkingMode != .disabled {
                            streamingThinkingText = thinkingText
                        }
                        lastUIUpdateTime = now
                        pendingUpdate = false
                    } else {
                        pendingUpdate = true
                    }
                }
                
                // 循环结束，处理剩余 Buffer
                if !pendingBuffer.isEmpty {
                    if isThinking {
                         thinkingText += pendingBuffer
                    } else {
                         responseText += pendingBuffer
                    }
                }
                
                // v1.6: 流式完成 — 一次性写入 sessions（触发完整 Markdown 渲染）
                do {
                    let finalContent = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
                    let finalThinking = thinkingText
                    
                    if var currentMsgs = sessions.first(where: { $0.id == currentSessionId })?.messages, botIndex < currentMsgs.count {
                        currentMsgs[botIndex].text = finalContent
                        
                        if thinkingMode == .disabled {
                            currentMsgs[botIndex].thinkingContent = nil
                        } else {
                            currentMsgs[botIndex].thinkingContent = finalThinking.isEmpty ? nil : finalThinking
                        }
                        
                        // 先清空流式状态，再写入 sessions
                        streamingText = ""
                        streamingThinkingText = ""
                        updateCurrentSessionMessagesInMemory(currentMsgs)
                    }
                }
                
                // 流式输出完成后，一次性保存到磁盘
                saveSessions()
                // 生成完成：成功震动
                if enableHapticFeedback { WKInterfaceDevice.current().play(.success) }
                
                // v1.7: 后台提取记忆（非阻塞）
                if self.memoryEnabled {
                    Task { [weak self] in
                        await self?.extractMemories()
                    }
                }
                
                // v1.7: 自动生成会话标题（首次对话时）
                if let session = self.sessions.first(where: { $0.id == self.currentSessionId }),
                   session.title == "新对话",
                   let firstUserMsg = session.messages.first(where: { $0.role == .user }) {
                    Task { [weak self] in
                        await self?.generateSessionTitle(from: firstUserMsg.text)
                    }
                }
            } catch {
                // v1.6: 先清空流式状态
                streamingText = ""
                streamingThinkingText = ""
                
                // 如果是取消错误，标记为用户停止
                if Task.isCancelled {
                    if var currentMsgs = sessions.first(where: { $0.id == currentSessionId })?.messages, botIndex < currentMsgs.count {
                        // 写入已积累的文本
                        let finalContent = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
                        currentMsgs[botIndex].text = finalContent.isEmpty ? "" : finalContent + "\n[已停止]"
                        if thinkingMode != .disabled && !thinkingText.isEmpty {
                            currentMsgs[botIndex].thinkingContent = thinkingText
                        }
                        updateCurrentSessionMessagesInMemory(currentMsgs)
                    }
                    saveSessions()
                    if enableHapticFeedback { WKInterfaceDevice.current().play(.directionDown) }
                } else if var currentMsgs = sessions.first(where: { $0.id == currentSessionId })?.messages, botIndex < currentMsgs.count {
                    let finalContent = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if finalContent.isEmpty { currentMsgs[botIndex].text = "❌ \(error.localizedDescription)" }
                    else { currentMsgs[botIndex].text = finalContent + "\n[中断]" }
                    if thinkingMode != .disabled && !thinkingText.isEmpty {
                        currentMsgs[botIndex].thinkingContent = thinkingText
                    }
                    updateCurrentSessionMessagesInMemory(currentMsgs)
                    saveSessions()
                    if enableHapticFeedback { WKInterfaceDevice.current().play(.failure) }
                }
            }
            isLoading = false
            currentTask = nil
        }
    }
    
    /// 解析 <think>...</think> 标签，返回 (思考内容, 剩余内容)
    private func buildHistoryWithContext(from msgs: [ChatMessage]) async -> [ChatMessage] {
        var history = msgs.dropLast(1).suffix(historyMessageCount).map { $0 }
        
        // 构造系统上下文
        var systemParts: [String] = []
        
        // 1. 用户自定义提示词（优先级最高）
        if !customSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            systemParts.append(customSystemPrompt)
        }
        
        // 2. v1.7: 注入长期记忆（全量回退模式）
        if memoryEnabled && !memories.isEmpty {
            // 从最后一条用户消息提取查询
            let userQuery = msgs.last(where: { $0.role == .user })?.text ?? ""
            let relevantMemories: [MemoryItem]
            
            // 检查是否有带 embedding 的记忆且已配置 Embedding 提供商
            let hasEmbeddings = memories.contains(where: { $0.embedding != nil })
            if hasEmbeddings, let (embConfig, embModel) = getEmbeddingProvider(), !userQuery.isEmpty {
                // 向量检索 Top-5（综合相似度 + 重要性）
                if let queryEmb = try? await service.fetchEmbedding(text: userQuery, modelId: embModel, config: embConfig) {
                    var scored: [(MemoryItem, Float)] = memories.map { m in
                        let similarity = m.embedding.map { cosineSimilarity(queryEmb, $0) } ?? 0.3
                        let finalScore = similarity * 0.7 + m.importance * 0.3
                        return (m, finalScore)
                    }
                    scored.sort { $0.1 > $1.1 }
                    relevantMemories = scored.prefix(5).map { $0.0 }
                } else {
                    relevantMemories = Array(memories.sorted { $0.importance > $1.importance }.prefix(10))
                }
            } else {
                // 无 Embedding，按重要性排序注入（最多 10 条）
                relevantMemories = Array(memories.sorted { $0.importance > $1.importance }.prefix(10))
            }
            
            if !relevantMemories.isEmpty {
                let memoryLines = relevantMemories.map { "- \($0.content)" }.joined(separator: "\n")
                systemParts.append("你知道以下关于用户的信息（长期记忆）：\n\(memoryLines)")
            }
        }
        
        // 3. 时间和位置信息
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
    
    // MARK: - 记忆系统 (v1.7)
    
    private let maxMemoryCount = 50
    
    func saveMemories() {
        if let encoded = try? JSONEncoder().encode(memories) {
            UserDefaults.standard.set(encoded, forKey: "userMemories_v1")
            // v1.7: 同步到 iCloud
            NSUbiquitousKeyValueStore.default.set(encoded, forKey: "userMemories_v1")
            NSUbiquitousKeyValueStore.default.synchronize()
        }
    }
    
    func loadMemories() {
        // 优先从 iCloud 加载，如果本地没有则用 iCloud 的
        if let cloudData = NSUbiquitousKeyValueStore.default.data(forKey: "userMemories_v1"),
           let cloudMemories = try? JSONDecoder().decode([MemoryItem].self, from: cloudData) {
            // 其次加载本地
            if let localData = UserDefaults.standard.data(forKey: "userMemories_v1"),
               let localMemories = try? JSONDecoder().decode([MemoryItem].self, from: localData) {
                // 合并：iCloud 和本地取并集
                memories = mergeMemories(local: localMemories, cloud: cloudMemories)
            } else {
                memories = cloudMemories
            }
            // 同步合并结果到两边
            saveMemories()
        } else if let data = UserDefaults.standard.data(forKey: "userMemories_v1"),
                  let decoded = try? JSONDecoder().decode([MemoryItem].self, from: data) {
            memories = decoded
        }
        
        // 监听 iCloud 变更
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default,
            queue: .main
        ) { [weak self] _ in
            self?.handleiCloudMemoryChange()
        }
    }
    
    /// 合并本地和 iCloud 记忆（按内容去重）
    private func mergeMemories(local: [MemoryItem], cloud: [MemoryItem]) -> [MemoryItem] {
        var merged = local
        for cloudMem in cloud {
            if !merged.contains(where: { $0.content == cloudMem.content }) {
                merged.append(cloudMem)
            }
        }
        // 按时间排序，最新的在前面
        merged.sort { $0.createdAt > $1.createdAt }
        if merged.count > maxMemoryCount {
            merged = Array(merged.prefix(maxMemoryCount))
        }
        return merged
    }
    
    /// 处理 iCloud 远程变更
    private func handleiCloudMemoryChange() {
        guard let cloudData = NSUbiquitousKeyValueStore.default.data(forKey: "userMemories_v1"),
              let cloudMemories = try? JSONDecoder().decode([MemoryItem].self, from: cloudData) else { return }
        memories = mergeMemories(local: memories, cloud: cloudMemories)
        // 只写本地，避免循环
        if let encoded = try? JSONEncoder().encode(memories) {
            UserDefaults.standard.set(encoded, forKey: "userMemories_v1")
        }
        print("☁️ iCloud 记忆同步完成，当前共 \(memories.count) 条")
    }
    
    func addMemory(_ content: String, embedding: [Float]? = nil, importance: Float = 0.5) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // 去重：如果已存在相同内容的记忆，跳过
        guard !memories.contains(where: { $0.content == trimmed }) else { return }
        
        let sessionTitle = sessions.first(where: { $0.id == currentSessionId })?.title
        let item = MemoryItem(content: trimmed, createdAt: Date(), source: sessionTitle, embedding: embedding, importance: importance)
        memories.insert(item, at: 0)
        
        // 超出上限，移除最旧的
        if memories.count > maxMemoryCount {
            memories = Array(memories.prefix(maxMemoryCount))
        }
        saveMemories()
    }
    
    func deleteMemory(id: UUID) {
        memories.removeAll { $0.id == id }
        saveMemories()
    }
    
    func deleteMemories(at offsets: IndexSet) {
        memories.remove(atOffsets: offsets)
        saveMemories()
    }
    
    func clearAllMemories() {
        memories.removeAll()
        saveMemories()
    }
    
    /// v1.7: 利用 LLM 从当前对话中提取记忆，并生成向量嵌入
    func extractMemories() async {
        guard memoryEnabled else { return }
        
        // 获取当前会话的消息（最近几轮）
        let msgs = currentMessages
        guard msgs.count >= 2 else { return }  // 至少有一问一答
        
        // 取最近 6 条消息（3 轮对话）用于提取
        let recentMsgs = msgs.suffix(min(6, msgs.count))
        let conversationText = recentMsgs.compactMap { msg -> String? in
            guard msg.role != .system else { return nil }
            let role = msg.role == .user ? "用户" : "AI"
            return "\(role): \(msg.text)"
        }.joined(separator: "\n")
        
        guard !conversationText.isEmpty else { return }
        
        // 构建提取 prompt (v1.7.2: 强化 Prompt，防止整段摘抄)
        let extractionPrompt = """
        任务：从以下对话中提取关于用户的关键事实信息。
        要求：
        1. 只提取事实（如姓名、年龄、喜好、习惯、计划等），不要提取闲聊或临时问题。
        2. 必须用第三人称陈述句（例如："用户喜欢..."），**不要摘抄原文**。
        3. 极度精简，每条信息不超过 20 字。
        4. 格式：
           - 普通事实：以 "- " 开头。
           - 强调事实（用户明确要求记住）：以 "[!] " 开头。
        5. 如果没有新事实，仅回复 "无"。
        
        示例：
        对话：
        用户：我下周要去北京出差。
        AI：好的。
        提取：
        - 用户计划下周去北京出差
        
        对话内容：
        \(conversationText)
        """
        
        // 优先使用辅助模型 (v1.7.2)
        let targetModelID = helperGlobalModelID.isEmpty ? selectedGlobalModelID : helperGlobalModelID
        let components = targetModelID.split(separator: "|")
        guard components.count == 2,
              let providerID = UUID(uuidString: String(components[0])),
              let provider = providers.first(where: { $0.id == providerID }),
              !provider.apiKey.isEmpty else { return }
        let modelID = String(components[1])
        
        // 使用非流式请求提取（收集全部结果）
        let extractionMsg = ChatMessage(role: .user, text: extractionPrompt)
        let stream = service.streamChat(
            messages: [extractionMsg],
            modelId: modelID,
            config: provider,
            temperature: 0.1  // 极低温度确保精确提取
        )
        
        var result = ""
        do {
            for try await chunk in stream {
                result += chunk
            }
        } catch {
            print("⚠️ 记忆提取失败: \(error.localizedDescription)")
            return
        }
        
        // 解析结果
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "无", !trimmed.hasPrefix("无") else { return }
        
        // 获取 Embedding 提供商配置
        let embProvider = getEmbeddingProvider()
        
        // 逐行解析 "- xxx" 格式
        let lines = trimmed.components(separatedBy: "\n")
        for line in lines {
            var cleaned = line.trimmingCharacters(in: .whitespacesAndNewlines)
            // 解析 "[!] xxx" 或 "- xxx" 格式
            var isHighPriority = false
            if cleaned.hasPrefix("[!] ") {
                cleaned = String(cleaned.dropFirst(4))
                isHighPriority = true
            } else if cleaned.hasPrefix("- ") {
                cleaned = String(cleaned.dropFirst(2))
            } else if cleaned.hasPrefix("* ") {
                cleaned = String(cleaned.dropFirst(2))
            }
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty, cleaned.count > 2 else { continue }
            
            // 生成向量嵌入（如果配置了 Embedding 提供商）
            var emb: [Float]? = nil
            if let (embConfig, embModel) = embProvider {
                do {
                    emb = try await service.fetchEmbedding(text: cleaned, modelId: embModel, config: embConfig)
                } catch {
                    print("⚠️ Embedding 生成失败: \(error.localizedDescription)")
                }
            }
            
            await MainActor.run {
                addMemory(cleaned, embedding: emb, importance: isHighPriority ? 0.8 : 0.5)
            }
        }
        
        print("✅ 记忆提取完成，当前共 \(memories.count) 条记忆")
    }
    
    /// 获取 Embedding 提供商配置
    private func getEmbeddingProvider() -> (ProviderConfig, String)? {
        guard !embeddingProviderID.isEmpty, !embeddingModelID.isEmpty,
              let providerUUID = UUID(uuidString: embeddingProviderID),
              let provider = providers.first(where: { $0.id == providerUUID }),
              !provider.apiKey.isEmpty else { return nil }
        return (provider, embeddingModelID)
    }
    
    /// 余弦相似度
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        let denominator = sqrt(normA) * sqrt(normB)
        guard denominator > 0 else { return 0 }
        return dotProduct / denominator
    }
    
    /// 检索与查询最相关的 Top-K 记忆
    func retrieveRelevantMemories(for query: String, topK: Int = 5) async -> [MemoryItem] {
        // 如果没有配置 Embedding，返回全部记忆
        guard let (embConfig, embModel) = getEmbeddingProvider() else {
            return Array(memories.prefix(topK))
        }
        
        // 检查是否有记忆带有 embedding
        let memoriesWithEmbedding = memories.filter { $0.embedding != nil }
        guard !memoriesWithEmbedding.isEmpty else {
            return Array(memories.prefix(topK))
        }
        
        // 生成查询向量
        do {
            let queryEmbedding = try await service.fetchEmbedding(text: query, modelId: embModel, config: embConfig)
            
            // 计算相似度并排序
            var scored: [(memory: MemoryItem, score: Float)] = []
            for memory in memories {
                if let emb = memory.embedding {
                    let score = cosineSimilarity(queryEmbedding, emb)
                    scored.append((memory, score))
                } else {
                    // 没有 embedding 的记忆给中等分数
                    scored.append((memory, 0.3))
                }
            }
            
            scored.sort { $0.score > $1.score }
            return scored.prefix(topK).map { $0.memory }
        } catch {
            print("⚠️ 查询 Embedding 失败: \(error.localizedDescription)，回退全量注入")
            return Array(memories.prefix(topK))
        }
    }
    
    /// v1.7: 自动生成会话标题
    func generateSessionTitle(from firstMessage: String) async {
        // 优先使用辅助模型，若未设置则使用当前模型
        let targetModelID = helperGlobalModelID.isEmpty ? selectedGlobalModelID : helperGlobalModelID
        
        let components = targetModelID.split(separator: "|")
        guard components.count == 2,
              let providerID = UUID(uuidString: String(components[0])),
              let provider = providers.first(where: { $0.id == providerID }),
              !provider.apiKey.isEmpty else { return }
        let modelID = String(components[1])
        
        let titlePrompt = "用不超过10个字总结以下内容的主题，只输出标题本身，不要加引号或标点：\n\(firstMessage.prefix(200))"
        let titleMsg = ChatMessage(role: .user, text: titlePrompt)
        let stream = service.streamChat(
            messages: [titleMsg],
            modelId: modelID,
            config: provider,
            temperature: 0.3
        )
        
        var result = ""
        do {
            for try await chunk in stream {
                result += chunk
            }
        } catch {
            print("⚠️ 标题生成失败: \(error.localizedDescription)")
            return
        }
        
        let title = result.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "《", with: "")
            .replacingOccurrences(of: "》", with: "")
        guard !title.isEmpty, title.count <= 20 else { return }
        
        await MainActor.run {
            if let idx = self.sessions.firstIndex(where: { $0.id == self.currentSessionId }) {
                self.sessions[idx].title = title
                self.saveSessions()
                print("✅ 自动标题: \(title)")
            }
        }
    }
    
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
        
        // v1.6: 初始化流式输出状态
        streamingText = ""
        streamingThinkingText = ""
        
        msgs.append(ChatMessage(role: .assistant, text: ""))
        updateCurrentSessionMessagesInMemory(msgs) // 只更新内存，不写磁盘
        let botIndex = msgs.count - 1
        
        currentTask = Task {
            let history = await buildHistoryWithContext(from: msgs)
            var responseText = ""
            var thinkingText = ""
            
            // v1.6: 200ms 节流（只更新 streamingText）
            var lastUIUpdateTime = Date()
            let uiUpdateInterval: TimeInterval = 0.15  // 150ms 平衡流畅度和性能
            
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
                    responseText = parsedContent // 更新解析后的内容
                    thinkingText = finalThinking
                    
                    // v1.6: 节流更新 streamingText
                    let now = Date()
                    if now.timeIntervalSince(lastUIUpdateTime) >= uiUpdateInterval {
                        streamingText = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !thinkingText.isEmpty {
                            streamingThinkingText = thinkingText
                        }
                        lastUIUpdateTime = now
                    }
                }
                
                // 流式完成 — 一次性写入 sessions
                let finalContent = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
                if var currentMsgs = sessions.first(where: { $0.id == currentSessionId })?.messages, botIndex < currentMsgs.count {
                    currentMsgs[botIndex].text = finalContent
                    currentMsgs[botIndex].thinkingContent = thinkingText.isEmpty ? nil : thinkingText
                    streamingText = ""
                    streamingThinkingText = ""
                    updateCurrentSessionMessagesInMemory(currentMsgs)
                }
                saveSessions()
                
            } catch {
                streamingText = ""
                streamingThinkingText = ""
                
                if Task.isCancelled {
                    if var currentMsgs = sessions.first(where: { $0.id == currentSessionId })?.messages, botIndex < currentMsgs.count {
                        let finalContent = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
                        currentMsgs[botIndex].text = finalContent.isEmpty ? "" : finalContent + "\n[已停止]"
                        if !thinkingText.isEmpty { currentMsgs[botIndex].thinkingContent = thinkingText }
                        updateCurrentSessionMessagesInMemory(currentMsgs)
                    }
                    saveSessions()
                } else if var currentMsgs = sessions.first(where: { $0.id == currentSessionId })?.messages, botIndex < currentMsgs.count {
                    let finalContent = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if finalContent.isEmpty { currentMsgs[botIndex].text = "❌ \(error.localizedDescription)" }
                    else { currentMsgs[botIndex].text = finalContent + "\n[中断]" }
                    if !thinkingText.isEmpty { currentMsgs[botIndex].thinkingContent = thinkingText }
                    updateCurrentSessionMessagesInMemory(currentMsgs)
                    saveSessions()
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
    
    // MARK: - 模型能力检查 (v1.7)
    
    enum ThinkingSupportStatus {
        case supported      // 原生支持 (e.g. DeepSeek-R1)
        case unsupported    // 原生不支持 (e.g. GPT-3.5)
        case unknown        // 未知 / 无法判断
    }
    
    /// 获取当前模型的思考能力状态
    /// 优先级：模型专属设置 > 全局思考模式 > 自动判断
    func checkThinkingSupport(modelId: String = "") -> ThinkingSupportStatus {
        let targetId = modelId.isEmpty ? resolveCurrentModelID() : modelId
        let lower = targetId.lowercased()
        
        // 1. 检查模型专属设置
        if let settings = modelSettings[targetId] {
            switch settings.thinking {
            case .enabled: return .supported
            case .disabled: return .unsupported
            case .auto: break // 继续检查
            }
        }
        
        // 2. 检查全局模式
        // 注意：全局模式控制的是“是否显示”，这里返回的是“是否支持”
        // 如果全局强制开启，则视为支持；强制关闭不影响支持状态判断，但会影响显示逻辑
        if thinkingMode == .enabled { return .supported }
        
        // 3. 查表逻辑 (ModelRegistry)
        if let info = ModelRegistry.shared.getCapability(modelId: targetId) {
            if info.supportsThinking { return .supported }
        }
        
        // 4. 兜底/旧逻辑
        if lower.contains("deepseek-r1") || 
           lower.contains("deepseek-reasoner") {
            return .supported
        }
        
        // 已知不支持列表
        if lower.contains("gpt-3") || 
           lower.contains("gpt-4") || 
           lower.contains("claude-3") || 
           lower.contains("gemini") ||
           lower.contains("deepseek-chat") || // V3 非 R1
           lower.contains("deepseek-v3") {
            return .unsupported
        }
        
        return .unknown
    }
    
    /// 获取当前模型的视觉能力状态
    /// 优先级：模型专属设置 > 自动判断
    func checkVisionSupport(modelId: String = "") -> ThinkingSupportStatus {
        let targetId = modelId.isEmpty ? resolveCurrentModelID() : modelId
        let lower = targetId.lowercased()
        
        // 1. 检查模型专属设置
        if let settings = modelSettings[targetId] {
            switch settings.vision {
            case .enabled: return .supported
            case .disabled: return .unsupported
            case .auto: break 
            }
        }
        
        // 2. 查表逻辑 (ModelRegistry)
        if let info = ModelRegistry.shared.getCapability(modelId: targetId) {
            if info.supportsVision { return .supported }
        }
        
        // 3. 兜底逻辑
        if lower.contains("vision") || 
           lower.contains("gpt-4o") || 
           lower.contains("gemini-1.5") || 
           lower.contains("claude-3") ||
           lower.contains("vl") { // Qwen-VL, DeepSeek-VL
            return .supported
        }
        
        if lower.contains("gpt-3") || 
           lower.contains("deepseek-r1") { // R1 目前主要是文本
            return .unsupported
        }
        
        return .unknown
    }
    
    /// 解析当前选中的模型 ID (去除 Provider 前缀)
    func resolveCurrentModelID() -> String {
        let components = selectedGlobalModelID.split(separator: "|")
        if components.count >= 2 {
            return String(components[1])
        }
        return selectedGlobalModelID
    }
    
    // 保存模型设置
    func saveModelSettings() {
        if let data = try? JSONEncoder().encode(modelSettings) {
            modelSettingsData = data
        }
    }
    
    // 加载模型设置 (在 init 中调用)
    func loadModelSettings() {
        if let decoded = try? JSONDecoder().decode([String: ModelSettings].self, from: modelSettingsData) {
            modelSettings = decoded
        }
    }
    
    // 更新特定模型的能力设置
    func updateModelSettings(modelId: String, thinking: CapabilityState? = nil, vision: CapabilityState? = nil) {
        var settings = modelSettings[modelId] ?? ModelSettings()
        if let t = thinking { settings.thinking = t }
        if let v = vision { settings.vision = v }
        modelSettings[modelId] = settings
    }
    
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
        // v1.8: 记录重新生成的时间
        let sendTime = Date()
        var assistantMsg = ChatMessage(role: .assistant, text: "")
        assistantMsg.sendTime = sendTime
        msgs.append(assistantMsg)
        
        updateCurrentSessionMessages(msgs)
        let botIndex = msgs.count - 1
        
        currentTask = Task {
            let history = await buildHistoryWithContext(from: msgs)
            var responseText = ""
            var thinkingText = ""
            var firstTokenReceived = false
            var localFirstTokenTime: Date? = nil // v1.8: 本地暂存首 Token 时间
            
            // v1.8.1: 流式解析状态机 (优化性能)
            var isThinking = false
            var pendingBuffer = ""
            
            // v1.8.3: 终极性能权衡 - 3秒更新 + 实时Markdown
            var lastUIUpdateTime = Date()
            let uiUpdateInterval: TimeInterval = 3.0
            var pendingUpdate = false
            
            do {
                let stream = service.streamChat(messages: history, modelId: modelID, config: provider, temperature: temperature)
                for try await chunk in stream {
                    if Task.isCancelled { break }
                    
                    // v1.8: 记录首 Token 时间
                    if !firstTokenReceived {
                        firstTokenReceived = true
                        localFirstTokenTime = Date()
                        if var currentMsgs = sessions.first(where: { $0.id == currentSessionId })?.messages, botIndex < currentMsgs.count {
                            currentMsgs[botIndex].firstTokenTime = localFirstTokenTime
                            updateCurrentSessionMessagesInMemory(currentMsgs)
                        }
                    }
                    // 1. 处理内部标记 (保留兼容性)
                    var processedChunk = chunk
                    if let range = processedChunk.range(of: "🧠THINK:") {
                         processedChunk = processedChunk.replacingOccurrences(of: "🧠THINK:", with: "")
                    }
                    
                    // 2. 追加到缓冲
                    pendingBuffer += processedChunk
                    
                    // 3. 状态机解析循环
                    while true {
                        let tag = isThinking ? "</think>" : "<think>"
                        if let range = pendingBuffer.range(of: tag, options: .caseInsensitive) {
                            let contentBefore = String(pendingBuffer[..<range.lowerBound])
                            if isThinking {
                                thinkingText += contentBefore
                                isThinking = false
                            } else {
                                responseText += contentBefore
                                isThinking = true
                            }
                            pendingBuffer = String(pendingBuffer[range.upperBound...])
                        } else {
                            let keepLength = tag.count - 1
                            if pendingBuffer.count > keepLength {
                                let safeIndex = pendingBuffer.index(pendingBuffer.endIndex, offsetBy: -keepLength)
                                let safeContent = String(pendingBuffer[..<safeIndex])
                                if isThinking { thinkingText += safeContent }
                                else { responseText += safeContent }
                                pendingBuffer = String(pendingBuffer[safeIndex...])
                            }
                            break
                        }
                    }
                    
                    // 4. 节流 UI 更新（流式输出时禁用动画，减少Watch卡顿）
                    let now = Date()
                    if now.timeIntervalSince(lastUIUpdateTime) >= uiUpdateInterval {
                        let finalThinking = thinkingText
                        var finalContent = responseText
                        finalContent = finalContent.trimmingCharacters(in: .whitespacesAndNewlines)
                        
                        // v1.8.4: 流式输出时禁用动画，只做数据更新
                        if var currentMsgs = sessions.first(where: { $0.id == currentSessionId })?.messages, botIndex < currentMsgs.count {
                            currentMsgs[botIndex].text = finalContent
                            if thinkingMode == .disabled {
                                currentMsgs[botIndex].thinkingContent = nil
                            } else {
                                currentMsgs[botIndex].thinkingContent = finalThinking.isEmpty ? nil : finalThinking
                            }
                            updateCurrentSessionMessagesInMemory(currentMsgs)
                        }
                        lastUIUpdateTime = now
                        pendingUpdate = false
                    } else {
                        pendingUpdate = true
                    }
                }
                
                // 结束处理剩余 Buffer
                if !pendingBuffer.isEmpty {
                    if isThinking { thinkingText += pendingBuffer }
                    else { responseText += pendingBuffer }
                }
                
                // v1.8: 完成记录
                if true {
                    let finalThinking = thinkingText
                    var finalContent = responseText
                    finalContent = finalContent.trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    if var currentMsgs = sessions.first(where: { $0.id == currentSessionId })?.messages, botIndex < currentMsgs.count {
                        currentMsgs[botIndex].text = finalContent
                        if thinkingMode == .disabled {
                            currentMsgs[botIndex].thinkingContent = nil
                        } else {
                            currentMsgs[botIndex].thinkingContent = finalThinking.isEmpty ? nil : finalThinking
                        }
                        currentMsgs[botIndex].completeTime = Date()
                        if let t = localFirstTokenTime { currentMsgs[botIndex].firstTokenTime = t }
                        updateCurrentSessionMessagesInMemory(currentMsgs)
                    }
                }
                
                saveSessions() // 最终保存
                if enableHapticFeedback { WKInterfaceDevice.current().play(.success) }
                
            } catch {
                if Task.isCancelled {
                    if var currentMsgs = sessions.first(where: { $0.id == currentSessionId })?.messages, botIndex < currentMsgs.count {
                        if !currentMsgs[botIndex].text.isEmpty {
                            currentMsgs[botIndex].text += "\n[已停止]"
                        }
                        if let t = localFirstTokenTime { currentMsgs[botIndex].firstTokenTime = t }
                        updateCurrentSessionMessagesInMemory(currentMsgs)
                    }
                    saveSessions()
                    if enableHapticFeedback { WKInterfaceDevice.current().play(.directionDown) }
                } else if var currentMsgs = sessions.first(where: { $0.id == currentSessionId })?.messages, botIndex < currentMsgs.count {
                    if responseText.isEmpty { currentMsgs[botIndex].text = "❌ \(error.localizedDescription)" }
                    else { currentMsgs[botIndex].text += "\n[中断]" }
                    if let t = localFirstTokenTime { currentMsgs[botIndex].firstTokenTime = t }
                    updateCurrentSessionMessagesInMemory(currentMsgs)
                    saveSessions()
                    if enableHapticFeedback { WKInterfaceDevice.current().play(.failure) }
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
