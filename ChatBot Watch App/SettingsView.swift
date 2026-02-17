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
    @State private var showAddProviderSheet = false // v1.7.2: 使用 Sheet 修复输入问题
    @State private var showImportSheet = false // v1.8: 导入配置
    @State private var importResult: String? = nil
    
    // v1.9: 文件导出状态
    @State private var exportedConfigURL: URL? = nil
    @State private var exportedMemoriesURL: URL? = nil
    @State private var exportedSessionsURL: URL? = nil
    
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
                
                Button {
                    showAddProviderSheet = true
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
                

                // v1.11: 记忆与向量
                NavigationLink {
                    MemorySettingsView(viewModel: viewModel)
                } label: {
                    HStack {
                        Text("记忆与向量")
                        Spacer()
                        if viewModel.memoryEnabled {
                            Text("已启用")
                                .font(.caption).foregroundColor(.secondary)
                        } else {
                            Text("已禁用")
                                .font(.caption).foregroundColor(.secondary)
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
                
                // v1.10: 云端数据管理
                NavigationLink {
                    CloudDataView(viewModel: viewModel)
                } label: {
                    Label("云端数据管理", systemImage: "icloud")
                }
                
                // v1.8: 迁移进度
                if let progress = viewModel.migrationProgress {
                    HStack {
                        ProgressView()
                        Text(progress).font(.caption).foregroundColor(.secondary)
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
        .sheet(isPresented: $showAddProviderSheet) {
            NavigationStack {
                AddProviderView(viewModel: viewModel)
            }
        }
        .sheet(isPresented: $showImportSheet) {
            NavigationStack {
                ImportConfigView(viewModel: viewModel, importResult: $importResult)
            }
        }
        .alert("导入结果", isPresented: Binding<Bool>(
            get: { importResult != nil },
            set: { if !$0 { importResult = nil } }
        )) {
            Button("确定") { importResult = nil }
        } message: {
            Text(importResult ?? "")
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
    @State private var showAddKeySheet = false // v1.7.2: 使用 Sheet 修复输入问题
    
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
                Button {
                    showAddKeySheet = true
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
        .sheet(isPresented: $showAddKeySheet) {
            NavigationStack {
                AddAPIKeyView(apiKeys: $draftConfig.apiKeys)
            }
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
                    // v1.8: 将获取的模型合并写入 draftConfig，确保 onDisappear 保存时持久化
                    self.draftConfig.availableModels = mergeModels()
                    self.draftConfig.modelsLastFetched = Date()
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
                SecureField("API Key", text: $newConfig.apiKey)
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
                // v1.8: 使用 SecureField 走 iPhone 安全输入通道，支持可靠粘贴
                SecureField("sk-...", text: $newKey)
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

// MARK: - v1.8: 导入配置

struct ImportConfigView: View {
    @ObservedObject var viewModel: ChatViewModel
    @Binding var importResult: String?
    @State private var jsonText: String = ""
    @Environment(\.dismiss) var dismiss
    
    // v1.10: R2 导入支持
    @AppStorage("lastImportConfigURL") private var lastImportURL: String = ""
    @State private var isImporting: Bool = false
    
    var body: some View {
        Form {
            // 方式 1: URL 导入 (推荐)
            Section(header: Text("方式 1: 从 URL 导入 (推荐)")) {
                TextField("https://example.com/config.json", text: $lastImportURL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                
                Button {
                    guard let url = URL(string: lastImportURL) else {
                        importResult = "❌ 无效的 URL"
                        return
                    }
                    isImporting = true
                    Task {
                        do {
                            try await viewModel.importConfigFromURL(url)
                            await MainActor.run {
                                importResult = "✅ 导入成功！\(viewModel.providers.count) 个供应商，\(viewModel.memories.count) 条记忆"
                                isImporting = false
                                dismiss()
                            }
                        } catch {
                            await MainActor.run {
                                importResult = "❌ 下载/导入失败：\(error.localizedDescription)"
                                isImporting = false
                            }
                        }
                    }
                } label: {
                    if isImporting {
                        HStack {
                            ProgressView()
                            Text("下载导入中...")
                        }
                    } else {
                        Text("下载并导入")
                    }
                }
                .disabled(lastImportURL.isEmpty || isImporting)
            }
            
            // 方式 2: 粘贴文本
            Section(header: Text("方式 2: 粘贴 JSON 文本")) {
                TextField("从 iPhone 粘贴...", text: $jsonText, axis: .vertical)
                    .lineLimit(3...6)
                    .font(.caption2)
                Text("如果在 Watch 上粘贴困难，请使用上方 URL 导入")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            if !jsonText.isEmpty {
                Section {
                    Text("已输入 \(jsonText.count) 字符")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            
            Section(footer: Text("导入将完整覆盖当前所有配置、记忆和会话。")) {
                Button("导入（全量覆盖）") {
                    do {
                        try viewModel.importFullConfig(from: jsonText)
                        importResult = "✅ 导入成功！\(viewModel.providers.count) 个供应商，\(viewModel.memories.count) 条记忆"
                    } catch {
                        importResult = "❌ 导入失败：\(error.localizedDescription)"
                    }
                    dismiss()
                }
                .disabled(jsonText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .navigationTitle("导入配置")
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
                .onChange(of: settings.thinking) { _, _ in save() }  // v1.12: 新版 API
            }
            
            Section(header: Text("视觉能力 (Vision)"), footer: Text("开启后允许上传图片。如果模型不支持视觉，图片将被忽略或导致报错。")) {
                Picker("状态", selection: $settings.vision) {
                    ForEach(CapabilityState.allCases) { state in
                        Text(state.rawValue).tag(state)
                    }
                }
                .onChange(of: settings.vision) { _, _ in save() }  // v1.12: 新版 API
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

// MARK: - v1.11: 记忆与向量设置视图
struct MemorySettingsView: View {
    @ObservedObject var viewModel: ChatViewModel
    
    // 提取自 SettingsView 的计算属性
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
    
    var body: some View {
        Form {
            Section(header: Text("记忆系统")) {
                Toggle("启用记忆功能", isOn: $viewModel.memoryEnabled)
                
                if viewModel.memoryEnabled {
                    NavigationLink {
                        MemoryView(viewModel: viewModel)
                    } label: {
                        HStack {
                            Text("记忆管理")
                            Spacer()
                            Text("\(viewModel.memories.count) 条")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            if viewModel.memoryEnabled {
                Section(header: Text("向量配置 (Embedding)")) {
                    Picker("向量供应商", selection: $viewModel.embeddingProviderID) {
                        Text("未配置").tag("")
                        Text("Workers AI ☁️").tag("workersAI")
                        ForEach(viewModel.providers) { provider in
                            Text(provider.name).tag(provider.id.uuidString)
                        }
                    }
                    
                    if viewModel.embeddingProviderID == "workersAI" {
                        NavigationLink {
                            WorkersAIURLEditView(url: $viewModel.workersAIEmbeddingURL)
                        } label: {
                            HStack {
                                Text("端点 URL")
                                Spacer()
                                Text(viewModel.workersAIEmbeddingURL.replacingOccurrences(of: "https://", with: ""))
                                    .font(.caption).foregroundColor(.secondary).lineLimit(1)
                            }
                        }
                    } else if !viewModel.embeddingProviderID.isEmpty {
                        let embModels = embeddingModelsForSelectedProvider
                        if embModels.isEmpty {
                            NavigationLink {
                                EmbeddingModelEditView(modelID: $viewModel.embeddingModelID)
                            } label: {
                                HStack {
                                    Text("模型 ID")
                                    Spacer()
                                    Text(viewModel.embeddingModelID.isEmpty ? "手动输入" : viewModel.embeddingModelID)
                                        .font(.caption).foregroundColor(.secondary).lineLimit(1)
                                }
                            }
                        } else {
                            Picker("选择模型", selection: $viewModel.embeddingModelID) {
                                Text("未选择").tag("")
                                ForEach(embModels) { model in
                                    Text(model.displayName ?? model.id).tag(model.id)
                                }
                            }
                        }
                    }
                    
                    if !viewModel.embeddingProviderID.isEmpty {
                        Button {
                            Task {
                                await viewModel.probeEmbeddingDimension()
                                await viewModel.checkAndAutoMigrate()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("同步维度")
                                Spacer()
                                if viewModel.detectedEmbeddingDim > 0 {
                                    Text("\(viewModel.detectedEmbeddingDim)d")
                                        .font(.caption).foregroundColor(.secondary)
                                }
                            }
                        }
                        
                        if let progress = viewModel.migrationProgress {
                            HStack {
                                ProgressView()
                                Text(progress).font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("记忆设置")
    }
}

// MARK: - v1.12: 云端数据管理视图
struct CloudDataView: View {
    @ObservedObject var viewModel: ChatViewModel
    @State private var showOverwriteAlert = false
    @State private var isUploading = false
    
    /// 格式化最后同步时间
    private var lastSyncText: String? {
        guard viewModel.lastCloudSyncTime > 0 else { return nil }
        let date = Date(timeIntervalSince1970: viewModel.lastCloudSyncTime)
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }
    
    var body: some View {
        List {
            // MARK: 同步状态
            if let syncTime = lastSyncText {
                Section {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.caption2)
                            Text("上次同步")
                                .font(.caption2)
                        }
                        .foregroundColor(.secondary)
                        
                        Text(syncTime)
                            .font(.caption)
                            .foregroundColor(.primary)
                    }
                    .padding(.vertical, 2)
                }
            }
            
            // MARK: 上传
            Section(footer: Text("将当前全部配置、记忆和聊天记录上传到云端。Workers 会自动保留历史版本。")) {
                Button {
                    guard !isUploading else { return }
                    isUploading = true
                    Task {
                        await viewModel.uploadConfigToCloud()
                        isUploading = false
                    }
                } label: {
                    HStack {
                        if isUploading {
                            ProgressView()
                                .frame(width: 20, height: 20)
                            Text("正在上传...")
                                .foregroundColor(.secondary)
                        } else {
                            Image(systemName: "icloud.and.arrow.up.fill")
                                .foregroundColor(.blue)
                                .frame(width: 20)
                            Text("上传到云端")
                        }
                    }
                }
                .disabled(isUploading || viewModel.cloudBackupURL.isEmpty)
            }
            
            // MARK: 状态信息
            if let status = viewModel.cloudUploadStatus {
                Section {
                    HStack(spacing: 8) {
                        if status.contains("✅") || status.contains("⏭️") {
                            Image(systemName: status.contains("⏭️") ? "equal.circle.fill" : "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else if status.contains("❌") {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                        }
                        Text(status)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // MARK: 恢复模式
            Section(header: Text("从云端恢复")) {
                // 增量合并
                NavigationLink {
                    CloudImportSelectionView(viewModel: viewModel)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.triangle.merge")
                            .foregroundColor(.cyan)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("增量合并")
                                .font(.body)
                            Text("选择要合并的数据项，保留本地已有数据")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // 历史版本
                NavigationLink {
                    CloudVersionListView(viewModel: viewModel)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundColor(.indigo)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("历史版本")
                                .font(.body)
                            Text("浏览和恢复 Workers 保留的历史备份")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // 完整覆盖
                Button(role: .destructive) {
                    showOverwriteAlert = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.counterclockwise.circle.fill")
                            .foregroundColor(.red)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("完整覆盖")
                                .foregroundColor(.red)
                            Text("清空本地，完全恢复云端状态")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            // MARK: 设置入口
            Section {
                NavigationLink {
                    CloudBackupSettingsView(viewModel: viewModel)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "gearshape.fill")
                            .foregroundColor(.gray)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("云备份设置")
                            if !viewModel.cloudBackupURL.isEmpty {
                                Text(viewModel.cloudBackupURL
                                    .replacingOccurrences(of: "https://", with: "")
                                    .replacingOccurrences(of: "http://", with: ""))
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("云端数据")
        .alert("确定要完整覆盖吗？", isPresented: $showOverwriteAlert) {
            Button("取消", role: .cancel) { }
            Button("覆盖本地数据", role: .destructive) {
                Task {
                    do {
                        try await viewModel.downloadConfigFromCloud(mode: .overwrite)
                        viewModel.cloudUploadStatus = "✅ 完整恢复成功"
                        viewModel.lastCloudSyncTime = Date().timeIntervalSince1970
                    } catch {
                        viewModel.cloudUploadStatus = "❌ 恢复失败: \(error.localizedDescription)"
                    }
                }
            }
        } message: {
            Text("所有本地配置、聊天记录和记忆都将被替换为云端版本。此操作无法撤销。")
        }
    }
}

// MARK: - v1.12: 历史版本列表视图
struct CloudVersionListView: View {
    @ObservedObject var viewModel: ChatViewModel
    @State private var versions: [ChatViewModel.BackupVersion] = []
    @State private var isLoading = true
    @State private var errorMessage: String? = nil
    @State private var operationStatus: String? = nil
    @State private var isDeduplicating = false
    @State private var renamingVersion: ChatViewModel.BackupVersion? = nil
    
    var body: some View {
        List {
            if isLoading {
                Section {
                    HStack {
                        ProgressView()
                        Text("加载中...").foregroundColor(.secondary)
                    }
                }
            } else if let error = errorMessage {
                Section {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Button {
                        Task { await loadVersions() }
                    } label: {
                        Label("重试", systemImage: "arrow.clockwise")
                    }
                }
            } else if versions.isEmpty {
                Section {
                    Text("暂无历史版本")
                        .foregroundColor(.secondary)
                }
            } else {
                // 当前版本
                if let current = versions.first(where: { $0.version == 0 }) {
                    Section(header: Text("当前版本")) {
                        versionRow(current)
                    }
                }
                
                // 历史版本
                let history = versions.filter { $0.version > 0 }
                if !history.isEmpty {
                    Section(header: Text("历史版本 (\(history.count))")) {
                        ForEach(history) { version in
                            versionRow(version)
                        }
                    }
                }
            }
            
            // 工具
            if !versions.isEmpty {
                Section(header: Text("工具")) {
                    // 一键去重
                    Button {
                        guard !isDeduplicating else { return }
                        isDeduplicating = true
                        Task {
                            do {
                                let result = try await viewModel.deduplicateBackups()
                                operationStatus = result.removed > 0
                                    ? "✅ \(result.message)"
                                    : "ℹ️ \(result.message)"
                await loadVersions(forceRefresh: true)
                            } catch {
                                operationStatus = "❌ 去重失败: \(error.localizedDescription)"
                            }
                            isDeduplicating = false
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if isDeduplicating {
                                ProgressView()
                                    .frame(width: 18, height: 18)
                                Text("去重中...")
                                    .foregroundColor(.secondary)
                            } else {
                                Image(systemName: "wand.and.stars")
                                    .foregroundColor(.purple)
                                    .frame(width: 18)
                                Text("一键去重")
                            }
                        }
                    }
                    .disabled(isDeduplicating)
                    
                    // 手动刷新
                    Button {
                        Task { await loadVersions(forceRefresh: true) }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.clockwise")
                                .foregroundColor(.blue)
                                .frame(width: 18)
                            Text("刷新列表")
                        }
                    }
                }
            }
            
            // 操作状态
            if let status = operationStatus {
                Section {
                    HStack(spacing: 6) {
                        if status.contains("✅") {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                        } else if status.contains("❌") {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.red)
                        } else if status.contains("ℹ️") {
                            Image(systemName: "info.circle.fill").foregroundColor(.blue)
                        }
                        Text(status).font(.caption).foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle("历史版本")
        .task { await loadVersions() }
        .sheet(item: $renamingVersion) { version in
            RenameBackupSheet(viewModel: viewModel, version: version, isPresented: Binding(
                get: { renamingVersion != nil },
                set: { if !$0 { renamingVersion = nil } }
            ))
        }
    }
    
    private func loadVersions(forceRefresh: Bool = false) async {
        isLoading = true
        errorMessage = nil
        do {
            versions = try await viewModel.fetchBackupVersions(forceRefresh: forceRefresh)
            isLoading = false
        } catch {
            // 网络失败时尝试使用本地缓存
            if let cached = viewModel.loadCachedVersions() {
                versions = cached
                operationStatus = "⚠️ 已使用本地缓存"
                isLoading = false
            } else {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
    
    @ViewBuilder
    private func versionRow(_ version: ChatViewModel.BackupVersion) -> some View {
        NavigationLink {
            BackupPreviewView(viewModel: viewModel, version: version)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: version.version == 0 ? "doc.fill" : "clock")
                            .font(.caption)
                            .foregroundColor(version.version == 0 ? .blue : .secondary)
                        Text(version.displayName)
                            .font(.body)
                    }
                    Text(version.displaySubtitle)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "eye")
                    .font(.caption)
                    .foregroundColor(.cyan)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            // 左滑：重命名 (新增)
            Button {
                renamingVersion = version
            } label: {
                Label("重命名", systemImage: "pencil")
            }
            .tint(.orange)
            
            // 左滑：删除（仅历史版本）
            if version.version > 0 {
                Button(role: .destructive) {
                    Task {
                        do {
                            try await viewModel.deleteBackupVersion(key: version.key)
                            await MainActor.run { viewModel.cachedVersions = nil }
                            await loadVersions(forceRefresh: true)
                            operationStatus = "✅ 已删除 \(version.label)"
                        } catch {
                            operationStatus = "❌ 删除失败: \(error.localizedDescription)"
                        }
                    }
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            // 右滑：恢复
            Button {
                Task {
                    do {
                        try await viewModel.restoreBackupVersion(key: version.key, mode: .overwrite)
                        operationStatus = "✅ 已恢复 \(version.label)"
                    } catch {
                        operationStatus = "❌ 恢复失败: \(error.localizedDescription)"
                    }
                }
            } label: {
                Label("恢复", systemImage: "arrow.counterclockwise")
            }
            .tint(.blue)
        }
    }
}

// MARK: - v1.12: 备份版本预览详情页
struct BackupPreviewView: View {
    @ObservedObject var viewModel: ChatViewModel
    let version: ChatViewModel.BackupVersion
    @State private var preview: ChatViewModel.BackupPreview? = nil
    @State private var isLoading = true
    @State private var errorMessage: String? = nil
    @State private var showRestoreAlert = false
    @State private var restoreStatus: String? = nil
    
    var body: some View {
        List {
            if isLoading {
                Section {
                    HStack {
                        ProgressView()
                        Text("加载预览...").foregroundColor(.secondary)
                    }
                }
            } else if let error = errorMessage {
                Section {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(error).font(.caption).foregroundColor(.secondary)
                    }
                }
            } else if let p = preview {
                // 基本信息
                Section(header: Text("概览")) {
                    infoRow("大小", value: p.sizeText)
                    infoRow("供应商", value: "\(p.providers ?? 0) 个")
                    infoRow("记忆", value: "\(p.memories ?? 0) 条")
                    infoRow("会话", value: "\(p.sessions ?? 0) 个")
                }
                
                // 配置详情
                if let d = p.details {
                    Section(header: Text("配置详情")) {
                        if let model = d.selectedModel, !model.isEmpty {
                            infoRow("当前模型", value: model)
                        }
                        if let temp = d.temperature {
                            infoRow("温度", value: String(format: "%.1f", temp))
                        }
                        if let count = d.historyCount {
                            infoRow("历史条数", value: "\(count)")
                        }
                        if let thinking = d.thinkingMode {
                            infoRow("思维链", value: thinking ? "开启" : "关闭")
                        }
                        if let memory = d.memoryEnabled {
                            infoRow("记忆功能", value: memory ? "开启" : "关闭")
                        }
                        if let prompt = d.hasCustomPrompt {
                            infoRow("自定义提示词", value: prompt ? "有" : "无")
                        }
                    }
                    
                    // 供应商列表
                    if let names = d.providerNames, !names.isEmpty {
                        Section(header: Text("供应商列表")) {
                            ForEach(names, id: \.self) { name in
                                HStack(spacing: 6) {
                                    Image(systemName: "server.rack")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Text(name)
                                        .font(.caption)
                                }
                            }
                        }
                    }
                }
                
                // 操作
                Section {
                    Button {
                        showRestoreAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "arrow.counterclockwise.circle.fill")
                                .foregroundColor(.blue)
                            Text("恢复此版本")
                                .foregroundColor(.blue)
                        }
                    }
                }
                
                if let status = restoreStatus {
                    Section {
                        Text(status).font(.caption).foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle(version.displayName)
        .task {
            do {
                preview = try await viewModel.previewBackupVersion(key: version.key, uuid: version.uuid)
                isLoading = false
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
        .alert("恢复此版本？", isPresented: $showRestoreAlert) {
            Button("取消", role: .cancel) { }
            Button("覆盖恢复", role: .destructive) {
                Task {
                    do {
                        try await viewModel.restoreBackupVersion(key: version.key, mode: .overwrite)
                        restoreStatus = "✅ 已恢复 \(version.label)"
                    } catch {
                        restoreStatus = "❌ 恢复失败: \(error.localizedDescription)"
                    }
                }
            }
        } message: {
            Text("将用 \(version.label) (\(version.sizeText)) 覆盖本地所有数据。")
        }
    }
    
    @ViewBuilder
    private func infoRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}

// MARK: - v1.12: 云备份设置视图
struct CloudBackupSettingsView: View {
    @ObservedObject var viewModel: ChatViewModel
    @State private var draftURL: String = ""
    @State private var draftKey: String = ""
    @State private var isTesting = false
    @State private var testResult: (success: Bool, message: String)? = nil
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        List {
            Section(header: Label("R2 备份端点", systemImage: "link"), footer: Text("Cloudflare Workers 的完整 URL，包含文件名。")) {
                TextField("https://example.com/config.json", text: $draftURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 13))
            }
            
            Section(header: Label("认证密钥", systemImage: "key.fill"), footer: Text("对应 Workers 中配置的 AUTH_KEY。")) {
                SecureField("X-Auth-Key", text: $draftKey)
                    .textInputAutocapitalization(.never)
                    .font(.system(size: 13))
            }
            
            // 连接测试
            Section {
                Button {
                    guard !isTesting else { return }
                    isTesting = true
                    // 临时应用 draft 值进行测试
                    let savedURL = viewModel.cloudBackupURL
                    let savedKey = viewModel.cloudBackupAuthKey
                    viewModel.cloudBackupURL = draftURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    viewModel.cloudBackupAuthKey = draftKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    Task {
                        let result = await viewModel.testCloudConnection()
                        testResult = result
                        // 如果测试失败，恢复原值
                        if !result.success {
                            viewModel.cloudBackupURL = savedURL
                            viewModel.cloudBackupAuthKey = savedKey
                        }
                        isTesting = false
                    }
                } label: {
                    HStack {
                        if isTesting {
                            ProgressView()
                                .frame(width: 18, height: 18)
                            Text("测试中...")
                                .foregroundColor(.secondary)
                        } else {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .foregroundColor(.purple)
                            Text("测试连接")
                        }
                    }
                }
                .disabled(isTesting || draftURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                
                // 测试结果
                if let result = testResult {
                    HStack(spacing: 6) {
                        Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(result.success ? .green : .red)
                            .font(.caption)
                        Text(result.message)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // 自动备份设置
            Section(header: Text("自动备份"), footer: Text("开启后每次打开 App 自动静默备份到云端。")) {
                Toggle(isOn: $viewModel.autoBackupEnabled) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise.icloud.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                            .frame(width: 16, alignment: .center)
                        Text("自动备份")
                    }
                }
            }
            
            // 保存
            Section {
                Button {
                    viewModel.cloudBackupURL = draftURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    viewModel.cloudBackupAuthKey = draftKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    dismiss()
                } label: {
                    HStack {
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                        Text("保存")
                        Spacer()
                    }
                }
                .disabled(draftURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .navigationTitle("云备份设置")
        .onAppear {
            draftURL = viewModel.cloudBackupURL
            draftKey = viewModel.cloudBackupAuthKey
        }
    }
}

// MARK: - v1.8: Workers AI URL 编辑视图
struct WorkersAIURLEditView: View {
    @Binding var url: String
    @State private var draftURL: String = ""
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        List {
            Section(header: Text("Workers AI 向量端点")) {
                TextField("https://example.com", text: $draftURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Text("POST {\"text\": \"...\"} 的端点地址")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section {
                Button("保存") {
                    url = draftURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    dismiss()
                }
                .disabled(draftURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .navigationTitle("端点 URL")
        .onAppear { draftURL = url }
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


