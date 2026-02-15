import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: ChatViewModel
    
    // MARK: - 新增状态变量，用于处理删除确认
    @State private var showDeleteAlert = false
    @State private var pendingDeleteIndexSet: IndexSet?
    
    // 批量验证状态
    @State private var isValidating = false
    @State private var validationResult: String? = nil
    
    // v1.7: 从选中的 Embedding 供应商的模型列表中过滤 embedding 模型
    var embeddingModelsForSelectedProvider: [AIModelInfo] {
        guard !viewModel.embeddingProviderID.isEmpty,
              let providerUUID = UUID(uuidString: viewModel.embeddingProviderID),
              let provider = viewModel.providers.first(where: { $0.id == providerUUID }) else {
            return []
        }
        return provider.availableModels.filter {
            $0.id.localizedCaseInsensitiveContains("embed")
        }.sorted { $0.id < $1.id }
    }
    
    // v1.7: 辅助模型显示名称
    var helperDisplayModelName: String {
        if viewModel.helperGlobalModelID.isEmpty { return "跟随当前模型" }
        let components = viewModel.helperGlobalModelID.split(separator: "|")
        if components.count == 2 {
            if let found = viewModel.allFavoriteModels.first(where: { $0.id == viewModel.helperGlobalModelID }) {
                // 如果显示名称包含路径（如 model/gpt-4），只显示最后一段
                let parts = found.displayName.split(separator: "/")
                if parts.count >= 2 { return String(parts.last!).trimmingCharacters(in: .whitespaces) }
                return found.displayName
            }
            return String(components[1])
        }
        return "跟随当前模型"
    }
    
    var body: some View {
        List {
            Section(header: Text("当前对话模型")) {
                if viewModel.allFavoriteModels.isEmpty {
                    Text("暂无模型，请进入下方供应商添加").font(.caption).foregroundColor(.gray)
                } else {

                    // 使用自定义 NavigationLink 替代 Picker，实现多级菜单
                    NavigationLink {
                        ModelSelectionRootView(viewModel: viewModel)
                    } label: {
                        HStack {
                            Text("选择模型")
                            Spacer()
                            Text(viewModel.currentDisplayModelName)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                }
            }
            
            Section(header: Text("供应商配置")) {
                // 使用 Binding 集合遍历，解决输入焦点丢失问题
                ForEach($viewModel.providers) { $provider in
                    NavigationLink {
                        ProviderDetailView(config: $provider, viewModel: viewModel)
                    } label: {
                        HStack {
                            Image(systemName: provider.icon)
                                .frame(width: 20)
                                .foregroundColor(provider.isPreset ? .blue : .orange)
                            VStack(alignment: .leading) {
                                Text(provider.name)
                                if provider.isValidated {
                                    Text("已验证 • \(provider.savedModels.count) 模型").font(.caption2).foregroundColor(.green)
                                } else if !provider.apiKey.isEmpty {
                                    Text("未验证").font(.caption2).foregroundColor(.orange)
                                } else {
                                    Text("无 Key").font(.caption2).foregroundColor(.gray)
                                }
                            }
                        }
                    }
                }
                // MARK: - 修改删除逻辑：拦截删除动作，弹出确认框
                .onDelete { idx in
                    self.pendingDeleteIndexSet = idx
                    self.showDeleteAlert = true
                }
                
                NavigationLink {
                    AddProviderView(viewModel: viewModel)
                } label: {
                    Label("添加自定义供应商", systemImage: "plus.circle").foregroundColor(.blue)
                }
            }
            
            Section(header: Text("界面设置")) {
                Toggle("显示模型名称", isOn: $viewModel.showModelNameInNavBar)
                Toggle("显示回底部按钮", isOn: $viewModel.showScrollToBottomButton)
                Toggle("启用振动反馈", isOn: $viewModel.enableHapticFeedback)
                Toggle("消息气泡动画", isOn: $viewModel.enableMessageAnimation)
                Picker("对话历史上下文", selection: $viewModel.historyMessageCount) {
                    ForEach(Array(stride(from: 5, through: 50, by: 5)), id: \.self) { count in
                        Text("\(count)条").tag(count)
                    }
                }
                
                // v1.6: 主题选择
                Picker("主题配色", selection: $viewModel.currentTheme) {
                    ForEach(AppTheme.allCases) { theme in
                        HStack(spacing: 6) {
                            Circle().fill(theme.userBubbleColor).frame(width: 10, height: 10)
                            Circle().fill(theme.botBubbleColor).frame(width: 10, height: 10)
                            Text(theme.rawValue)
                        }
                        .tag(theme)
                    }
                }
            }
            
            
            Section(header: Text("文本渲染")) {
                Picker("Markdown 渲染模式", selection: $viewModel.markdownRenderMode) {
                    ForEach(MarkdownRenderMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                
                switch viewModel.markdownRenderMode {
                case .realtime:
                    Text("流式时实时渲染，可能影响性能")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                case .onComplete:
                    Text("完成后自动渲染，流畅且自动格式化")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                case .manual:
                    Text("流式显示纯文本，点击按钮手动渲染")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Toggle("启用 LaTeX 渲染", isOn: $viewModel.latexRenderingEnabled)
                
                if viewModel.latexRenderingEnabled {
                    Toggle("高级渲染模式", isOn: $viewModel.advancedLatexEnabled)
                    
                    if viewModel.advancedLatexEnabled {
                        Text("⚠️ 高级模式可能导致排版错误和渲染问题")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
            }
            
            Section(header: Text("模型参数")) {
                Picker("温度参数", selection: $viewModel.temperature) {
                    ForEach(0...20, id: \.self) { i in
                        let val = Double(i) / 10.0
                        Text(String(format: "%.1f", val)).tag(val)
                    }
                }
                
                NavigationLink {
                    SystemPromptEditView(prompt: $viewModel.customSystemPrompt)
                } label: {
                    HStack {
                        Text("系统提示词")
                        Spacer()
                        Text(viewModel.customSystemPrompt.isEmpty ? "未设置" : "已设置")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Section(header: Text("高级")) {
                // 思考模式
                Picker("思考模式", selection: $viewModel.thinkingMode) {
                    ForEach(ThinkingMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                

                // v1.7: 记忆功能
                Toggle("记忆功能", isOn: $viewModel.memoryEnabled)
                
                NavigationLink {
                    MemoryView(viewModel: viewModel)
                } label: {
                    HStack {
                        Text("记忆管理")
                        Spacer()
                        Text("\(viewModel.memories.count) 条")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // v1.7: Embedding 配置
                if viewModel.memoryEnabled {
                    Picker("向量供应商", selection: $viewModel.embeddingProviderID) {
                        Text("未配置").tag("")
                        ForEach(viewModel.providers) { provider in
                            Text(provider.name).tag(provider.id.uuidString)
                        }
                    }
                    
                    if !viewModel.embeddingProviderID.isEmpty {
                        let embModels = embeddingModelsForSelectedProvider
                        if embModels.isEmpty {
                            // 没有找到 embedding 模型，提示用户先获取模型列表
                            NavigationLink {
                                EmbeddingModelEditView(modelID: $viewModel.embeddingModelID)
                            } label: {
                                HStack {
                                    Text("Embedding 模型")
                                    Spacer()
                                    Text(viewModel.embeddingModelID.isEmpty ? "手动输入" : viewModel.embeddingModelID)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        } else {
                            // 从模型列表中过滤出 embedding 模型
                            Picker("Embedding 模型", selection: $viewModel.embeddingModelID) {
                                Text("未选择").tag("")
                                ForEach(embModels) { model in
                                    Text(model.displayName ?? model.id)
                                        .tag(model.id)
                                }
                            }
                        }
                    }
                }
                
                // v1.7: 辅助模型（标题生成等）
                NavigationLink {
                    HelperModelSelectionView(viewModel: viewModel)
                } label: {
                    HStack {
                        Text("辅助模型")
                        Spacer()
                        Text(helperDisplayModelName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                
                // 批量验证按钮
                Button {
                    isValidating = true
                    Task {
                        let result = await viewModel.validateAllProviders()
                        await MainActor.run {
                            isValidating = false
                            validationResult = "✅ \(result.success) 成功, ❌ \(result.failed) 失败"
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "checkmark.shield")
                        Text("批量验证供应商")
                        Spacer()
                        if isValidating {
                            ProgressView()
                        } else if let result = validationResult {
                            Text(result).font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
                .disabled(isValidating)
                
                // 导出配置
                if let configData = viewModel.exportConfig(),
                   let configString = String(data: configData, encoding: .utf8) {
                    ShareLink(item: configString) {
                        Label("导出全部配置", systemImage: "square.and.arrow.up")
                    }
                }
                
                
                // v1.7: 单独导出记忆
                if let memData = viewModel.exportMemories(),
                   let memString = String(data: memData, encoding: .utf8) {
                    ShareLink(item: memString) {
                        Label("单独导出记忆 (\(viewModel.memories.count)条)", systemImage: "brain.head.profile")
                    }
                }
                
                // v1.7: 单独导出聊天记录
                if let sesData = viewModel.exportSessions(),
                   let sesString = String(data: sesData, encoding: .utf8) {
                    ShareLink(item: sesString) {
                        Label("单独导出聊天 (\(viewModel.sessions.count)个)", systemImage: "message")
                    }
                }
            }
            
            Section {
                Button(role: .destructive) {
                    viewModel.clearCurrentChat()
                } label: {
                    Text("清空聊天记录")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
        .navigationTitle("设置")
        // MARK: - 新增 Alert 弹窗逻辑
        .alert("确认删除供应商？", isPresented: $showDeleteAlert) {
            Button("取消", role: .cancel) {
                pendingDeleteIndexSet = nil
            }
            Button("删除", role: .destructive) {
                if let offsets = pendingDeleteIndexSet {
                    // 执行真正的删除操作
                    viewModel.providers.remove(atOffsets: offsets)
                    viewModel.saveProviders()
                }
                pendingDeleteIndexSet = nil
            }
        } message: {
            Text("此操作不可恢复，该供应商及其保存的模型配置将被移除。")
        }
    }
}

// 下面的代码保持不变，为了完整性保留引用

// 详情页
struct ProviderDetailView: View {
    @Binding var config: ProviderConfig
    @ObservedObject var viewModel: ChatViewModel
    @State private var isFetching = false
    @State private var fetchError: String? = nil
    @State private var fetchedOnlineModels: [AIModelInfo] = []
    @State private var modelSearchText = ""  // 模型搜索
    
    //引入本地临时状态，防止输入过程中触发父视图刷新导致键盘断连
    @State private var draftConfig: ProviderConfig = ProviderConfig(name: "", baseURL: "", apiKey: "", isPreset: false, icon: "")
    
    // v1.7: 用于配置能力的模型
    @State private var modelToConfigure: AIModelInfo?
    
    var body: some View {
        Form {
            Section(header: Text("连接信息")) {
                TextField("名称", text: $draftConfig.name)
                Picker("类型", selection: $draftConfig.apiType) { ForEach(APIType.allCases) { type in Text(type.rawValue).tag(type) } }
                VStack(alignment: .leading) {
                    Text("Base URL").font(.caption).foregroundColor(.gray)
                    TextField("https://...", text: $draftConfig.baseURL).textInputAutocapitalization(.never).disableAutocorrection(true)
                }
            }
            
            Section(header: Text("API Keys (\(draftConfig.apiKeys.count)个)")) {
                ForEach(Array(draftConfig.apiKeys.enumerated()), id: \.offset) { index, key in
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Key \(index + 1)\(index == draftConfig.currentKeyIndex ? " ✓" : "")")
                                .font(.caption2)
                                .foregroundColor(index == draftConfig.currentKeyIndex ? .green : .gray)
                            Text(maskAPIKey(key))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if draftConfig.apiKeys.count > 1 {
                            Button(role: .destructive) {
                                draftConfig.apiKeys.remove(at: index)
                                if draftConfig.currentKeyIndex >= draftConfig.apiKeys.count {
                                    draftConfig.currentKeyIndex = max(0, draftConfig.apiKeys.count - 1)
                                }
                            } label: {
                                Image(systemName: "trash").foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                NavigationLink {
                    AddAPIKeyView(apiKeys: $draftConfig.apiKeys)
                } label: {
                    Label("添加新 Key", systemImage: "plus.circle").foregroundColor(.blue)
                }
            }
            
            Section(header: Text("模型管理")) {
                NavigationLink {
                    // 注意：这里传递的是 config.id 还是 draftConfig.id 由逻辑决定，通常 id 不变
                    AddCustomModelView(viewModel: viewModel, providerID: draftConfig.id)
                } label: {
                    Label("手动添加自定义模型", systemImage: "plus.square.dashed").foregroundColor(.blue)
                }
                
                if draftConfig.apiKey.isEmpty {
                    Text("请先填写 API Key").font(.caption).foregroundColor(.gray)
                } else {
                    Button { validateAndFetch() } label: {
                        HStack {
                            Text(isFetching ? "正在获取..." : "获取在线模型列表")
                            if draftConfig.isValidated && !isFetching { Image(systemName: "checkmark.circle.fill").foregroundColor(.green) }
                        }
                    }
                    .disabled(isFetching)
                    if let err = fetchError { Text(err).font(.caption2).foregroundColor(.red) }
                }
            }
            
            if !fetchedOnlineModels.isEmpty || !draftConfig.availableModels.isEmpty {
                Section(header: Text("可用模型")) {
                    // 搜索框
                    TextField("搜索模型...", text: $modelSearchText)
                        .textInputAutocapitalization(.never)
                    
                    // 排序逻辑：收藏的排在前面，然后按 ID 排序
                    let displayModels = mergeModels().filter { model in
                        modelSearchText.isEmpty ||
                        model.id.localizedCaseInsensitiveContains(modelSearchText) ||
                        (model.displayName?.localizedCaseInsensitiveContains(modelSearchText) ?? false)
                    }.sorted { m1, m2 in
                        let isFav1 = draftConfig.isModelFavorited(m1.id)
                        let isFav2 = draftConfig.isModelFavorited(m2.id)
                        if isFav1 != isFav2 { return isFav1 } // 收藏优先
                        return m1.id < m2.id
                    }
                    
                    ForEach(displayModels) { model in
                        // 构建组合 ID 用于检查设置
                        let compositeID = "\(draftConfig.id.uuidString)|\(model.id)"
                        let settings = viewModel.modelSettings[compositeID] ?? ModelSettings()
                        
                        Button { toggleDraftModelFavorite(model: model) } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    HStack {
                                        Text(model.id).font(.caption)
                                        // 显示能力状态图标
                                        if viewModel.checkThinkingSupport(modelId: compositeID) == .supported {
                                            Image(systemName: "lightbulb.fill")
                                                .font(.system(size: 10))
                                                .foregroundColor(.yellow)
                                        }
                                        if viewModel.checkVisionSupport(modelId: compositeID) == .supported {
                                            Image(systemName: "eye.fill")
                                                .font(.system(size: 10))
                                                .foregroundColor(.green)
                                        }
                                    }
                                    if let display = model.displayName { Text(display).font(.caption2).foregroundColor(.blue) }
                                }
                                Spacer()
                                if draftConfig.isModelFavorited(model.id) { Image(systemName: "star.fill").foregroundColor(.yellow) }
                                else { Image(systemName: "star").foregroundColor(.gray) }
                            }
                        }
                        .swipeActions(edge: .trailing) { // 左滑
                            Button {
                                self.modelToConfigure = model
                            } label: {
                                Label("能力配置", systemImage: "slider.horizontal.3")
                            }
                            .tint(.orange)
                        }
                    }
                }
            }
        }
        // 使用 config.name (静态) 而不是 draftConfig.name (动态)，防止输入时 View 刷新导致键盘断连
        .navigationTitle(config.name.isEmpty ? "供应商配置" : config.name)
        .onAppear {
            self.draftConfig = config
        }
        .onDisappear {
            // 退出页面时将修改同步回 ViewModel
            self.config = draftConfig
            viewModel.saveProviders()
        }
        .sheet(item: $modelToConfigure) { model in
            let compositeID = "\(draftConfig.id.uuidString)|\(model.id)"
            let settings = viewModel.modelSettings[compositeID] ?? ModelSettings()
            ModelCapabilityConfigView(viewModel: viewModel, modelID: compositeID, settings: settings)
        }
    }
    
    // 需要针对 draftConfig 的本地收藏逻辑
    func toggleDraftModelFavorite(model: AIModelInfo) {
        draftConfig.toggleFavorite(model.id)
        // 同时确保模型在 availableModels 中
        if !draftConfig.availableModels.contains(where: { $0.id == model.id }) {
            draftConfig.availableModels.append(model)
        }
    }
    
    func mergeModels() -> [AIModelInfo] {
        var set = Set<String>()
        var result = draftConfig.availableModels
        for m in result { set.insert(m.id) }
        for m in fetchedOnlineModels { if !set.contains(m.id) { result.append(m) } }
        return result.sorted { $0.id < $1.id }
    }
    
    func validateAndFetch() {
        guard !draftConfig.apiKey.isEmpty else { return }
        isFetching = true; fetchError = nil
        let service = LLMService()
        let cfg = draftConfig
        Task {
            do {
                let models = try await service.fetchModels(config: cfg)
                await MainActor.run { 
                    self.fetchedOnlineModels = models
                    self.draftConfig.isValidated = true 
                    self.isFetching = false 
                }
            } catch {
                await MainActor.run { 
                    self.fetchError = "失败: \(error.localizedDescription)"
                    self.draftConfig.isValidated = false 
                    self.isFetching = false 
                }
            }
        }
    }
    
    // 切换能力状态: 自动 -> 开启 -> 关闭 -> 自动
    func nextCapabilityState(_ current: CapabilityState) -> CapabilityState {
        switch current {
        case .auto: return .enabled
        case .enabled: return .disabled
        case .disabled: return .auto
        }
    }
}

struct AddCustomModelView: View {
    @ObservedObject var viewModel: ChatViewModel
    var providerID: UUID
    @State private var modelID: String = ""
    @State private var displayName: String = ""
    @Environment(\.dismiss) var dismiss
    
    var isDisabled: Bool { modelID.trimmingCharacters(in: .whitespaces).isEmpty }
    
    var body: some View {
        Form {
            Section(header: Text("模型信息")) {
                TextField("模型 ID (必填)", text: $modelID).textInputAutocapitalization(.never).disableAutocorrection(true)
                TextField("备注名称 (可选)", text: $displayName)
            }
            Section(footer: Text("保存后将自动加入收藏列表。")) {
                Button(action: {
                    if !isDisabled {
                        viewModel.addCustomModel(providerID: providerID, modelID: modelID.trimmingCharacters(in: .whitespaces), displayName: displayName.trimmingCharacters(in: .whitespaces))
                        dismiss()
                    }
                }) {
                    Text("保存并加入收藏")
                        .font(.headline).fontWeight(.bold)
                        .padding(.vertical, 12).frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .background(RoundedRectangle(cornerRadius: 10).fill(isDisabled ? Color.gray.opacity(0.3) : Color.green.opacity(0.8)))
                .foregroundColor(isDisabled ? Color.gray : Color.white)
                .disabled(isDisabled)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("添加模型")
    }
}

struct AddProviderView: View {
    @ObservedObject var viewModel: ChatViewModel
    @State private var newConfig = ProviderConfig(name: "", baseURL: "", apiKey: "", isPreset: false, icon: "server.rack")
    @Environment(\.dismiss) var dismiss
    var body: some View {
        Form {
            Section {
                TextField("名称", text: $newConfig.name)
                Picker("类型", selection: $newConfig.apiType) { ForEach(APIType.allCases) { type in Text(type.rawValue).tag(type) } }
                TextField("Base URL", text: $newConfig.baseURL).textInputAutocapitalization(.never).disableAutocorrection(true)
                TextField("API Key", text: $newConfig.apiKey).textInputAutocapitalization(.never).disableAutocorrection(true)
            }
            Button("保存") {
                if !newConfig.baseURL.hasPrefix("http") && !newConfig.baseURL.isEmpty { newConfig.baseURL = "https://" + newConfig.baseURL }
                viewModel.providers.append(newConfig)
                viewModel.saveProviders()
                dismiss()
            }.disabled(newConfig.baseURL.isEmpty)
        }
        .navigationTitle("添加")
    }
}

// MARK: - 模型选择层级视图
struct ModelSelectionRootView: View {
    @ObservedObject var viewModel: ChatViewModel
    @State private var searchText = ""
    
    // 过滤后的收藏模型
    var filteredFavorites: [(id: String, displayName: String, providerName: String)] {
        if searchText.isEmpty { return viewModel.allFavoriteModels }
        return viewModel.allFavoriteModels.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText) ||
            $0.providerName.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    // 过滤后的最近使用
    var filteredRecent: [(id: String, displayName: String, providerName: String)] {
        if searchText.isEmpty { return viewModel.recentlyUsedModels }
        return viewModel.recentlyUsedModels.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText) ||
            $0.providerName.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        List {
            // 搜索框
            TextField("搜索模型...", text: $searchText)
                .textInputAutocapitalization(.never)
            
            // 最近使用模型部分
            if !filteredRecent.isEmpty {
                Section(header: Text("🕐 最近使用")) {
                    ForEach(filteredRecent, id: \.id) { item in
                        let isSelected = (viewModel.selectedGlobalModelID == item.id)
                        Button(action: {
                            viewModel.selectedGlobalModelID = item.id
                        }) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(item.displayName)
                                        .foregroundColor(isSelected ? .blue : .primary)
                                    Text(item.providerName)
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                }
                                Spacer()
                                if isSelected {
                                    Image(systemName: "checkmark").foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
            }
            
            // 收藏模型部分
            if !filteredFavorites.isEmpty {
                Section(header: Text("⭐ 收藏模型")) {
                    ForEach(filteredFavorites, id: \.id) { item in
                        let isSelected = (viewModel.selectedGlobalModelID == item.id)
                        Button(action: {
                            viewModel.selectedGlobalModelID = item.id
                        }) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(item.displayName)
                                        .foregroundColor(isSelected ? .blue : .primary)
                                    Text(item.providerName)
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                }
                                Spacer()
                                if isSelected {
                                    Image(systemName: "checkmark").foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
            }
            
            // 按供应商显示所有模型（搜索时隐藏）
            if searchText.isEmpty {
                Section(header: Text("所有模型")) {
                    ForEach(viewModel.providers) { provider in
                        if !provider.availableModels.isEmpty {
                            NavigationLink {
                                ModelListForProviderView(viewModel: viewModel, provider: provider)
                            } label: {
                                HStack {
                                    Image(systemName: provider.icon)
                                        .frame(width: 20)
                                    Text(provider.name)
                                    Spacer()
                                    Text("\(provider.availableModels.count)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("选择模型")
    }
}

struct ModelListForProviderView: View {
    @ObservedObject var viewModel: ChatViewModel
    let provider: ProviderConfig
    @Environment(\.dismiss) var dismiss
    @State private var searchText = ""
    
    // 过滤后的模型列表
    var filteredModels: [AIModelInfo] {
        if searchText.isEmpty {
            return provider.availableModels
        }
        return provider.availableModels.filter {
            $0.id.localizedCaseInsensitiveContains(searchText) ||
            ($0.displayName?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }
    
    var body: some View {
        List {
            // 搜索框
            TextField("搜索模型...", text: $searchText)
                .textInputAutocapitalization(.never)
            
            ForEach(filteredModels) { model in
                let compositeID = "\(provider.id.uuidString)|\(model.id)"
                let isSelected = (viewModel.selectedGlobalModelID == compositeID)
                
                Button(action: {
                    viewModel.selectedGlobalModelID = compositeID
                    dismiss()
                }) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(model.displayName ?? model.id)
                                .foregroundColor(isSelected ? .blue : .primary)
                            if model.displayName != nil {
                                Text(model.id).font(.caption2).foregroundColor(.gray)
                            }
                        }
                        Spacer()
                        if isSelected {
                            Image(systemName: "checkmark").foregroundColor(.blue)
                        }
                    }
                }
            }
        }
        .navigationTitle(provider.name)
    }
}

// MARK: - API Key 管理辅助

/// 掩码显示 API Key，仅显示前4位和后4位
func maskAPIKey(_ key: String) -> String {
    guard key.count > 8 else { return String(repeating: "•", count: key.count) }
    let prefix = key.prefix(4)
    let suffix = key.suffix(4)
    let middle = String(repeating: "•", count: min(8, key.count - 8))
    return "\(prefix)\(middle)\(suffix)"
}

struct AddAPIKeyView: View {
    @Binding var apiKeys: [String]
    @State private var newKey: String = ""
    @Environment(\.dismiss) var dismiss
    
    var isDisabled: Bool { newKey.trimmingCharacters(in: .whitespaces).isEmpty }
    
    var body: some View {
        Form {
            Section(header: Text("输入 API Key")) {
                // 使用 TextField 以支持手机键盘输入 (SecureField 不支持 Continuity Keyboard)
                TextField("sk-...", text: $newKey)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
            }
            Section(footer: Text("添加多个 Key 可实现自动轮询，避免单 Key 限流。")) {
                Button(action: {
                    if !isDisabled {
                        apiKeys.append(newKey.trimmingCharacters(in: .whitespaces))
                        dismiss()
                    }
                }) {
                    Text("添加")
                        .font(.headline).fontWeight(.bold)
                        .padding(.vertical, 12).frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .background(RoundedRectangle(cornerRadius: 10).fill(isDisabled ? Color.gray.opacity(0.3) : Color.green.opacity(0.8)))
                .foregroundColor(isDisabled ? Color.gray : Color.white)
                .disabled(isDisabled)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("添加 Key")
    }
}

// MARK: - 系统提示词编辑

struct SystemPromptEditView: View {
    @Binding var prompt: String
    @State private var draftPrompt: String = ""
    @Environment(\.dismiss) var dismiss
    
    private let examplePrompts = [
        "请用简洁的中文回复",
        "你是一个专业的编程助手",
        "回答问题时请列出要点"
    ]
    
    var body: some View {
        Form {
            Section(header: Text("自定义提示词")) {
                TextField("输入系统提示词...", text: $draftPrompt, axis: .vertical)
                    .lineLimit(3...8)
            }
            
            if draftPrompt.isEmpty {
                Section(header: Text("示例")) {
                    ForEach(examplePrompts, id: \.self) { example in
                        Button(example) {
                            draftPrompt = example
                        }
                    }
                }
            }
            
            Section {
                Button("保存") {
                    prompt = draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                    dismiss()
                }
                .disabled(draftPrompt == prompt)
                
                if !draftPrompt.isEmpty {
                    Button("清空", role: .destructive) {
                        draftPrompt = ""
                    }
                }
            }
        }
        .navigationTitle("系统提示词")
        .onAppear {
            draftPrompt = prompt
        }
    }
}


// MARK: - 模型能力配置视图 (v1.7)
struct ModelCapabilityConfigView: View {
    @ObservedObject var viewModel: ChatViewModel
    let modelID: String
    @State var settings: ModelSettings
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        Form {
            Section(header: Text("模型 ID")) {
                Text(modelID)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section(header: Text("思考能力 (Thinking)"), footer: Text("强制开启可能会让不支持思考的模型产生幻觉或乱码。")) {
                Picker("状态", selection: $settings.thinking) {
                    ForEach(CapabilityState.allCases) { state in
                        Text(state.rawValue).tag(state)
                    }
                }
                .onChange(of: settings.thinking) { _ in save() }
            }
            
            Section(header: Text("视觉能力 (Vision)"), footer: Text("开启后允许上传图片。如果模型不支持视觉，图片将被忽略或导致报错。")) {
                Picker("状态", selection: $settings.vision) {
                    ForEach(CapabilityState.allCases) { state in
                        Text(state.rawValue).tag(state)
                    }
                }
                .onChange(of: settings.vision) { _ in save() }
            }
        }
        .navigationTitle("能力配置")
        .onDisappear {
            save()
        }
    }
    
    func save() {
        viewModel.updateModelSettings(modelId: modelID, thinking: settings.thinking, vision: settings.vision)
    }
}

// MARK: - v1.7: Embedding 模型编辑视图
struct EmbeddingModelEditView: View {
    @Binding var modelID: String
    @State private var draftModel: String = ""
    @Environment(\.dismiss) var dismiss
    
    private let examples = [
        "gemini-embedding-001",
        "text-embedding-3-small",
        "text-embedding-ada-002",
        "BAAI/bge-large-zh-v1.5"
    ]
    
    var body: some View {
        Form {
            Section(header: Text("Embedding 模型名称")) {
                TextField("模型 ID", text: $draftModel)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            
            Section(header: Text("常用模型")) {
                ForEach(examples, id: \.self) { example in
                    Button(example) {
                        draftModel = example
                    }
                    .font(.caption)
                }
            }
            
            Section {
                Button("保存") {
                    modelID = draftModel.trimmingCharacters(in: .whitespacesAndNewlines)
                    dismiss()
                }
                .disabled(draftModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .navigationTitle("Embedding 模型")
        .onAppear { draftModel = modelID }
    }
}

// MARK: - 辅助模型选择视图 (v1.7)
struct HelperModelSelectionView: View {
    @ObservedObject var viewModel: ChatViewModel
    @State private var searchText = ""
    @Environment(\.dismiss) var dismiss
    
    var filteredFavorites: [(id: String, displayName: String, providerName: String)] {
        if searchText.isEmpty { return viewModel.allFavoriteModels }
        return viewModel.allFavoriteModels.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText) ||
            $0.providerName.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        List {
            Section {
                Button(action: {
                    viewModel.helperGlobalModelID = "" // 清空表示跟随当前
                    dismiss()
                }) {
                    HStack {
                        Text("跟随当前模型")
                            .foregroundColor(viewModel.helperGlobalModelID.isEmpty ? .blue : .primary)
                        Spacer()
                        if viewModel.helperGlobalModelID.isEmpty {
                            Image(systemName: "checkmark").foregroundColor(.blue)
                        }
                    }
                }
            } header: {
                Text("默认设置")
            }
            
            TextField("搜索模型...", text: $searchText).textInputAutocapitalization(.never)
            
            if !filteredFavorites.isEmpty {
                Section(header: Text("⭐ 收藏模型")) {
                    ForEach(filteredFavorites, id: \.id) { item in
                        let isSelected = (viewModel.helperGlobalModelID == item.id)
                        Button(action: {
                            viewModel.helperGlobalModelID = item.id
                            dismiss()
                        }) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(item.displayName).foregroundColor(isSelected ? .blue : .primary)
                                    Text(item.providerName).font(.caption2).foregroundColor(.gray)
                                }
                                Spacer()
                                if isSelected { Image(systemName: "checkmark").foregroundColor(.blue) }
                            }
                        }
                    }
                }
            }
            
            if searchText.isEmpty {
                Section(header: Text("所有模型")) {
                    ForEach(viewModel.providers) { provider in
                        if !provider.availableModels.isEmpty {
                            NavigationLink {
                                HelperModelListForProviderView(viewModel: viewModel, provider: provider)
                            } label: {
                                HStack {
                                    Image(systemName: provider.icon).frame(width: 20)
                                    Text(provider.name)
                                    Spacer()
                                    Text("\(provider.availableModels.count)").font(.caption).foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("选择辅助模型")
    }
}

struct HelperModelListForProviderView: View {
    @ObservedObject var viewModel: ChatViewModel
    let provider: ProviderConfig
    @Environment(\.dismiss) var dismiss
    @State private var searchText = ""
    
    var filteredModels: [AIModelInfo] {
        if searchText.isEmpty { return provider.availableModels }
        return provider.availableModels.filter {
            $0.id.localizedCaseInsensitiveContains(searchText) ||
            ($0.displayName?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }
    
    // v1.5: 排序逻辑
    var sortedModels: [AIModelInfo] {
        return filteredModels.sorted {
            let name1 = $0.displayName?.lowercased() ?? $0.id.lowercased()
            let name2 = $1.displayName?.lowercased() ?? $1.id.lowercased()
            return name1 < name2
        }
    }
    
    var body: some View {
        List {
            TextField("搜索...", text: $searchText).textInputAutocapitalization(.never)
            ForEach(sortedModels) { model in
                let fullID = "\(provider.id.uuidString)|\(model.id)"
                let isSelected = (viewModel.helperGlobalModelID == fullID)
                Button(action: {
                    viewModel.helperGlobalModelID = fullID
                }) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(model.displayName ?? model.id)
                                .foregroundColor(isSelected ? .blue : .primary)
                            Text(model.id)
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                        Spacer()
                        if isSelected { Image(systemName: "checkmark").foregroundColor(.blue) }
                    }
                }
            }
        }
        .navigationTitle(provider.name)
    }
}
