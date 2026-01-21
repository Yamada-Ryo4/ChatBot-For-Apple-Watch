import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: ChatViewModel
    
    // MARK: - 新增状态变量，用于处理删除确认
    @State private var showDeleteAlert = false
    @State private var pendingDeleteIndexSet: IndexSet?
    
    var body: some View {
        List {
            Section(header: Text("当前对话模型")) {
                if viewModel.allFavoriteModels.isEmpty {
                    Text("暂无模型，请进入下方供应商添加").font(.caption).foregroundColor(.gray)
                } else {
                    Picker("选择模型", selection: $viewModel.selectedGlobalModelID) {
                        Text("请选择").tag("")
                        ForEach(viewModel.allFavoriteModels, id: \.id) { item in
                            Text(item.displayName).tag(item.id)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    .onAppear {
                        let exists = viewModel.allFavoriteModels.contains { $0.id == viewModel.selectedGlobalModelID }
                        if !exists && !viewModel.selectedGlobalModelID.isEmpty { viewModel.selectedGlobalModelID = "" }
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
                    .font(.system(size: 14))
                Toggle("显示回底部按钮", isOn: $viewModel.showScrollToBottomButton)
                    .font(.system(size: 14))
            }
            
            Section {
                Button("清空聊天记录", role: .destructive) { viewModel.clearCurrentChat() }
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
    
    //引入本地临时状态，防止输入过程中触发父视图刷新导致键盘断连
    @State private var draftConfig: ProviderConfig = ProviderConfig(name: "", baseURL: "", apiKey: "", isPreset: false, icon: "")
    
    var body: some View {
        Form {
            Section(header: Text("连接信息")) {
                if !draftConfig.isPreset {
                    TextField("名称", text: $draftConfig.name)
                    Picker("类型", selection: $draftConfig.apiType) { ForEach(APIType.allCases) { type in Text(type.rawValue).tag(type) } }
                } else {
                    HStack { Text("类型"); Spacer(); Text(draftConfig.apiType.rawValue).foregroundColor(.gray) }
                }
                VStack(alignment: .leading) {
                    Text("Base URL").font(.caption).foregroundColor(.gray)
                    TextField("https://...", text: $draftConfig.baseURL).textInputAutocapitalization(.never).disableAutocorrection(true)
                }
                VStack(alignment: .leading) {
                    Text("API Key").font(.caption).foregroundColor(.gray)
                    // 使用 SecureField 并绑定到本地 draftConfig
                    SecureField("sk-...", text: $draftConfig.apiKey)
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
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
            
            if !fetchedOnlineModels.isEmpty || !draftConfig.savedModels.isEmpty {
                Section(header: Text("可用模型 (点击收藏)")) {
                    let displayModels = mergeModels()
                    ForEach(displayModels) { model in
                        Button { toggleDraftModelFavorite(model: model) } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(model.id).font(.caption)
                                    if let display = model.displayName { Text(display).font(.caption2).foregroundColor(.blue) }
                                }
                                Spacer()
                                if draftConfig.savedModels.contains(where: { $0.id == model.id }) { Image(systemName: "star.fill").foregroundColor(.yellow) }
                                else { Image(systemName: "star").foregroundColor(.gray) }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(draftConfig.name.isEmpty ? config.name : draftConfig.name)
        .onAppear {
            self.draftConfig = config
        }
        .onDisappear {
            // 退出页面时将修改同步回 ViewModel
            self.config = draftConfig
            viewModel.saveProviders()
        }
    }
    
    // 需要针对 draftConfig 的本地收藏逻辑
    func toggleDraftModelFavorite(model: AIModelInfo) {
        if let index = draftConfig.savedModels.firstIndex(where: { $0.id == model.id }) {
            draftConfig.savedModels.remove(at: index)
        } else {
            draftConfig.savedModels.append(model)
        }
    }
    
    func mergeModels() -> [AIModelInfo] {
        var set = Set<String>()
        var result = draftConfig.savedModels
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
