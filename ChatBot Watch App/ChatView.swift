import SwiftUI
import PhotosUI

struct ChatView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var viewModel: ChatViewModel // 改为 EnvironmentObject
    @Namespace private var bottomID
    @State private var showHistory = false
    @State private var isAtBottom = true
    
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Spacer().frame(height: 5)
                        
                        if viewModel.currentMessages.isEmpty {
                            EmptyStateView()
                        }
                        
                        ForEach(viewModel.currentMessages) { msg in
                            VStack(alignment: .leading, spacing: 4) {
                                
                                // 编辑模式 UI
                                if viewModel.editingMessageID == msg.id {
                                    VStack(alignment: .leading, spacing: 6) {
                                        TextField("编辑消息", text: $viewModel.editingText)
                                            .textFieldStyle(.plain)
                                            .padding(8)
                                            .background(Color.gray.opacity(0.2))
                                            .cornerRadius(8)
                                        
                                        HStack {
                                            Button(action: { withAnimation { viewModel.cancelEditing() } }) {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.title3)
                                                    .foregroundColor(.gray)
                                            }
                                            .buttonStyle(.plain)
                                            
                                            Spacer()
                                            
                                            Button(action: { withAnimation { viewModel.submitEdit() } }) {
                                                Image(systemName: "arrow.up.circle.fill")
                                                    .font(.title3)
                                                    .foregroundColor(.green)
                                            }
                                            .buttonStyle(.plain)
                                            .disabled(viewModel.editingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                        }
                                    }
                                    .padding(8)
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(12)
                                    
                                } else {
                                    // 正常显示模式
                                    PrettyMessageBubble(message: msg)
                                    
                                    if msg.role == .assistant &&
                                       msg.id == viewModel.currentMessages.last?.id &&
                                       !viewModel.isLoading &&
                                       !msg.text.isEmpty {
                                    HStack {
                                        Button(action: { viewModel.regenerateLastMessage() }) {
                                            HStack(spacing: 4) {
                                                Image(systemName: "arrow.clockwise")
                                                    .font(.system(size: 11))
                                                Text("重新生成")
                                                    .font(.system(size: 11))
                                            }
                                            .foregroundColor(.gray)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.gray.opacity(0.2))
                                            .cornerRadius(8)
                                        }
                                        .buttonStyle(.plain)
                                        Spacer()
                                    }
                                    .padding(.leading, 4)
                                }
                                
                                // 新增：如果是最后一条用户消息，且当前没有在生成，显示重新生成按钮
                                if msg.role == .user &&
                                   !viewModel.isLoading &&
                                   msg.id == viewModel.currentMessages.last(where: { $0.role == .user })?.id {
                                    HStack {
                                        Spacer()
                                        
                                        // 编辑按钮
                                        Button(action: { withAnimation { viewModel.startEditing(message: msg) } }) {
                                            HStack(spacing: 4) {
                                                Image(systemName: "pencil")
                                                    .font(.system(size: 11))
                                                Text("编辑")
                                                    .font(.system(size: 11))
                                            }
                                            .foregroundColor(.blue)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.blue.opacity(0.15))
                                            .cornerRadius(8)
                                        }
                                        .buttonStyle(.plain)
                                        
                                        // 重新生成按钮
                                        Button(action: { viewModel.regenerateLastMessage() }) {
                                            HStack(spacing: 4) {
                                                Image(systemName: "arrow.clockwise")
                                                    .font(.system(size: 11))
                                                Text("重试") // 缩短文案以节省空间
                                                    .font(.system(size: 11))
                                            }
                                            .foregroundColor(.blue)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.blue.opacity(0.15))
                                            .cornerRadius(8)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.trailing, 4)
                                }
                                }
                            }
                            .id(msg.id)
                        }
                        
                        // 输入区域
                        BottomInputArea(viewModel: viewModel)
                            .id(bottomID)
                            .padding(.top, 8)
                            .padding(.bottom, 8)
                            .frame(maxWidth: .infinity, alignment: .center)
                        
                        // 底部检测线
                        GeometryReader { geo in
                            Color.clear
                                .preference(
                                    key: BottomOffsetPreferenceKey.self,
                                    value: geo.frame(in: .global).minY
                                )
                        }
                        .frame(height: 1)
                    }
                    .padding(.horizontal, 8)
                }
                .defaultScrollAnchor(.bottom)
                .onPreferenceChange(BottomOffsetPreferenceKey.self) { minY in
                    let screenHeight = WKInterfaceDevice.current().screenBounds.height
                    let isVisible = minY < screenHeight + 50
                    if isAtBottom != isVisible {
                        isAtBottom = isVisible
                    }
                }
                .onChange(of: viewModel.currentMessages.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(bottomID, anchor: .bottom)
                    }
                }
                .onAppear {
                    proxy.scrollTo(bottomID, anchor: .bottom)
                }
                // 使用 overlay 而非 ZStack，确保按钮在独立的触摸层
                .overlay(alignment: .bottom) {
                    if viewModel.showScrollToBottomButton && !isAtBottom && viewModel.currentMessages.count > 2 {
                        Button {
                            withAnimation(.easeOut(duration: 0.3)) {
                                proxy.scrollTo(bottomID, anchor: .bottom)
                            }
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.blue)
                                .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                                .frame(width: 60, height: 44) // 扩大触控区域
                                .contentShape(Rectangle())   // 整个区域可点击
                        }
                        .buttonStyle(.plain)
                        .padding(.bottom, 4)
                        .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                    }
                }
            }
            .navigationTitle(viewModel.showModelNameInNavBar ? viewModel.currentDisplayModelName : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink(destination: SettingsView(viewModel: viewModel)) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.gray)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showHistory = true } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.blue)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sheet(isPresented: $showHistory) {
            HistoryListView(viewModel: viewModel, isPresented: $showHistory)
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .inactive || newPhase == .background {
                viewModel.stopGeneration()
            }
        }
    }
}



// 底部检测偏移量 PreferenceKey
struct BottomOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

 
// 底部输入区域 (复用代码)
struct BottomInputArea: View {
    @ObservedObject var viewModel: ChatViewModel
    
    var body: some View {
        let hasImage = viewModel.selectedImageData != nil
        let canSend = !viewModel.inputText.isEmpty || hasImage
        
        HStack(spacing: 8) {
            // 图片选择按钮（加载时禁用）
            if !viewModel.isLoading {
                PhotosPicker(selection: $viewModel.selectedImageItem, matching: .images) {
                    ZStack {
                        Circle().fill(Color.gray.opacity(0.3)).frame(width: 36, height: 36)
                        if hasImage {
                            Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundColor(.green)
                        } else {
                            Image(systemName: "photo").font(.system(size: 15)).foregroundColor(.white)
                        }
                    }
                }
                .buttonStyle(.plain)
                .onChange(of: viewModel.selectedImageItem) { viewModel.loadImage() }
            }
            
            // 输入框（加载时显示提示）
            ZStack(alignment: .leading) {
                Capsule().fill(Color.gray.opacity(0.3)).frame(height: 36)
                if viewModel.isLoading {
                    Text("正在生成...")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                        .padding(.horizontal, 12)
                } else {
                    Text(viewModel.inputText.isEmpty ? "发送消息..." : viewModel.inputText)
                        .font(.system(size: 15))
                        .foregroundColor(viewModel.inputText.isEmpty ? .gray : .white)
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                    TextField("placeholder", text: $viewModel.inputText)
                        .textFieldStyle(.plain)
                        .frame(maxWidth: .infinity).frame(height: 36)
                        .opacity(0.02)
                        .contentShape(Rectangle())
                }
            }
            .layoutPriority(1)
            
            // 发送/停止按钮
            if viewModel.isLoading {
                // 停止按钮
                Button(action: { viewModel.stopGeneration() }) {
                    ZStack {
                        Circle().fill(Color.red).frame(width: 36, height: 36)
                        Image(systemName: "stop.fill").font(.system(size: 14, weight: .bold)).foregroundColor(.white)
                    }
                }
                .buttonStyle(.plain)
            } else if canSend {
                // 发送按钮
                Button(action: viewModel.sendMessage) {
                    ZStack {
                        Circle().fill(Color.green).frame(width: 36, height: 36)
                        Image(systemName: "arrow.up").font(.system(size: 16, weight: .bold)).foregroundColor(.black)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.text.bubble.right.fill")
                .font(.largeTitle)
                .foregroundStyle(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                .opacity(0.8)
            Text("ChatBot").font(.headline)
        }.frame(maxWidth: .infinity).padding(.vertical, 30)
    }
}

// 增强版消息气泡：支持思考内容显示
struct PrettyMessageBubble: View {
    let message: ChatMessage
    @State private var isThinkingExpanded: Bool = false
    @State private var showRaw: Bool = false
    
    // 移除文本开头的多余换行符
    private func cleanMessageText(_ text: String) -> String {
        var trimmed = text
        while trimmed.hasPrefix("\n") {
            trimmed.removeFirst()
        }
        return trimmed
    }
    
    // 简单的正则提取 Markdown 图片 URL
    private func extractImageURL(from text: String) -> URL? {
        let pattern = "!\\[.*?\\]\\((https?://.*?)\\)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let nsString = text as NSString
        if let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: nsString.length)) {
            let urlString = nsString.substring(with: match.range(at: 1))
            return URL(string: urlString)
        }
        return nil
    }
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if message.role == .user { Spacer() }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                
                // 1. 用户上传的图片
                if let imgData = message.imageData, let uiImage = UIImage(data: imgData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.2), lineWidth: 1))
                }
                
                // 2. 思考内容 (可折叠显示)
                if let thinking = message.thinkingContent, !thinking.isEmpty, message.role == .assistant {
                    ThinkingContentView(content: thinking, isExpanded: $isThinkingExpanded)
                        .padding(.horizontal, 4)
                }
                
                // 3. 文本内容 (Markdown + LaTeX 公式支持)
                if !message.text.isEmpty {
                    
                    VStack(alignment: .leading, spacing: 4) {
                        
                        if showRaw {
                            // 原始文本模式
                            Text(message.text)
                                .font(.system(size: 14))
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            // 渲染模式
                            let cleanedText = cleanMessageText(message.text)
                            let textWithoutImage = cleanedText.replacingOccurrences(of: "!\\[.*?\\]\\(.*?\\)", with: "", options: .regularExpression)
                            
                            // 渲染 Markdown 图片
                            if let imageURL = extractImageURL(from: cleanedText) {
                                AsyncImage(url: imageURL) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image.resizable().aspectRatio(contentMode: .fit).cornerRadius(8)
                                    case .failure:
                                        HStack { Image(systemName: "photo.badge.exclamationmark"); Text("图片加载失败").font(.caption) }.foregroundColor(.red)
                                    case .empty:
                                        ProgressView().padding()
                                    @unknown default:
                                        EmptyView()
                                    }
                                }
                                .frame(maxWidth: 150)
                                
                                if !textWithoutImage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    MixedContentView(text: textWithoutImage)
                                }
                            } else {
                                // 使用完整 Markdown 渲染器 (支持公式)
                                MixedContentView(text: cleanedText)
                            }
                        }
                        
                        // 底部工具栏：切换原始/渲染视图
                        HStack {
                            Spacer()
                            Button(action: { withAnimation { showRaw.toggle() } }) {
                                Image(systemName: showRaw ? "text.bubble" : "curlybraces")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 4)
                        }
                    }

                    .padding(10)
                    .background(message.role == .user ? Color.green : Color.gray.opacity(0.3))
                    .cornerRadius(12)
                    .foregroundColor(.white)
                }
            }
            
            if message.role == .assistant { Spacer() }
        }
    }
}

// 辅助组件 (保持不变)
struct HistoryListView: View {
    @ObservedObject var viewModel: ChatViewModel
    @Binding var isPresented: Bool
    
    @State private var showDeleteConfirmation = false
    @State private var indexSetToDelete: IndexSet?
    
    var body: some View {
        List {
            Button("新建对话") { viewModel.createNewSession(); isPresented = false }
                .foregroundColor(.blue)
            
            ForEach(viewModel.sessions) { session in
                Button(session.title) { viewModel.selectSession(session); isPresented = false }
            }
            .onDelete { indices in
                indexSetToDelete = indices
                showDeleteConfirmation = true
            }
        }
        .alert(isPresented: $showDeleteConfirmation) {
            Alert(
                title: Text("删除对话"),
                message: Text("确定要删除选中的对话吗？此操作无法撤销。"),
                primaryButton: .destructive(Text("删除")) {
                    if let indices = indexSetToDelete {
                        viewModel.deleteSession(at: indices)
                    }
                    indexSetToDelete = nil
                },
                secondaryButton: .cancel(Text("取消")) {
                    indexSetToDelete = nil
                }
            )
        }
    }
}

// 可折叠的思考内容显示组件
struct ThinkingContentView: View {
    let content: String
    @Binding var isExpanded: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                HStack(spacing: 4) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 12))
                    Text("思考过程")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                }
                .foregroundColor(.purple)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                ScrollView {
                    Text(content)
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 100)
                .padding(6)
                .background(Color.purple.opacity(0.1))
                .cornerRadius(6)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .padding(8)
        .background(Color.purple.opacity(0.05))
        .cornerRadius(10)
    }
}

// MARK: - FlowLayout
struct FlowLayout: Layout {
    var spacing: CGFloat = 0
    var lineSpacing: CGFloat = 4
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrangeSubviews(proposal: proposal, subviews: subviews)
        if rows.isEmpty { return .zero }
        
        var width: CGFloat = 0
        var height: CGFloat = 0
        
        for row in rows {
            width = max(width, row.width)
            height += row.height + lineSpacing
        }
        height -= lineSpacing
        
        return CGSize(width: width, height: height)
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrangeSubviews(proposal: proposal, subviews: subviews)
        
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            // 每一行内的元素垂直居中对齐
            let centerY = y + row.height / 2
            
            for item in row.items {
                let size = item.size
                // 计算垂直居中的 Y 坐标
                let itemY = centerY - size.height / 2
                item.view.place(at: CGPoint(x: x, y: itemY), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }
    
    struct Row {
        var items: [Item] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }
    
    struct Item {
        var view: LayoutSubview
        var size: CGSize
    }
    
    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        // 修改：防止在 Watch 上出现无限宽度导致不换行
        // 获取屏幕宽度，减去两边的 padding (大约 30-40) 以确保安全换行
        // Bubble padding (20) + View padding (16) = 36. Use 40 for safety.
        let screenWidth = WKInterfaceDevice.current().screenBounds.width
        let safeWidth = screenWidth - 40
        
        // 强制限制最大宽度，无论父视图提议多大
        // 如果 proposal.width 为 nil (unspecified) 或 infinity，则使用 safeWidth
        // 如果 proposal.width 是具体值，取 min(proposal, safeWidth)
        let proposed = proposal.width ?? .infinity
        let maxWidth = proposed == .infinity ? safeWidth : min(proposed, safeWidth)
        
        var rows: [Row] = []
        var currentRow = Row()
        
        for subview in subviews {
            // 关键修改：告诉子视图不要超过 maxWidth
            // 这样 Text 如果很长（例如长单词或未切分的句子），会自动换行而不是撑大宽度
            let size = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            
            if currentRow.width + size.width + spacing > maxWidth && !currentRow.items.isEmpty {
                 rows.append(currentRow)
                 currentRow = Row()
            }
            
            currentRow.items.append(Item(view: subview, size: size))
            currentRow.width += size.width + (currentRow.items.count > 1 ? spacing : 0)
            currentRow.height = max(currentRow.height, size.height)
        }
        
        if !currentRow.items.isEmpty {
            rows.append(currentRow)
        }
        
        return rows
    }
}

// MARK: - 数学文本组件
// 智能数学文本组件：自动处理变量斜体、函数正体
struct MathText: View {
    let text: String
    let size: CGFloat
    
    // 已知数学函数 (需要保持正体)
    private let mathFunctions: Set<String> = [
        "sin", "cos", "tan", "cot", "sec", "csc",
        "arcsin", "arccos", "arctan",
        "sinh", "cosh", "tanh",
        "log", "ln", "lg", "lim", "exp",
        "min", "max", "sup", "inf", "det", "dim"
    ]
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(splitMathParts(text), id: \.self) { part in
                if isNumber(part) || mathFunctions.contains(part) || isSymbol(part) {
                    Text(part)
                        .font(.system(size: size, weight: .regular, design: .serif))
                } else {
                    Text(part)
                        .font(.system(size: size, weight: .regular, design: .serif))
                        .italic()
                }
            }
        }
    }
    
    func splitMathParts(_ str: String) -> [String] {
        var result: [String] = []
        var currentBuffer = ""
        
        for char in str {
            if char.isNumber {
                if !currentBuffer.isEmpty && !currentBuffer.last!.isNumber {
                    result.append(currentBuffer); currentBuffer = ""
                }
                currentBuffer.append(char)
            } else if char.isLetter {
                if !currentBuffer.isEmpty && !currentBuffer.last!.isLetter {
                    result.append(currentBuffer); currentBuffer = ""
                }
                currentBuffer.append(char)
            } else {
                if !currentBuffer.isEmpty {
                    result.append(currentBuffer); currentBuffer = ""
                }
                result.append(String(char))
            }
        }
        if !currentBuffer.isEmpty { result.append(currentBuffer) }
        return result
    }
    
    func isNumber(_ str: String) -> Bool { Double(str) != nil }
    func isSymbol(_ str: String) -> Bool { !str.first!.isLetter && !str.first!.isNumber }
}

// MARK: - 消息内容视图 (根据设置选择渲染方式)
struct MessageContentView: View {
    let text: String
    @EnvironmentObject var viewModel: ChatViewModel
    
    var body: some View {
        // Markdown 格式化始终应用
        let markdownProcessed = MarkdownParser.cleanMarkdown(text)
        
        if !viewModel.latexRenderingEnabled {
            // 关闭 LaTeX 渲染：只应用 Markdown 格式化，不转换数学符号
            Text(markdownProcessed)
                .font(.system(size: 14))
                .fixedSize(horizontal: false, vertical: true)
        } else if viewModel.advancedLatexEnabled {
            // 高级模式：使用 FlowLayout + AST 解析
            AdvancedLatexView(text: markdownProcessed)
        } else {
            // 简单模式：Markdown + LaTeX 符号替换
            Text(SimpleLatexConverter.convertLatexOnly(markdownProcessed))
                .font(.system(size: 14))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// 高级 LaTeX 渲染视图 (使用 FlowLayout)
struct AdvancedLatexView: View {
    let text: String
    
    var body: some View {
        let nodes = LaTeXParser.parseToNodes(text)
        
        FlowLayout(spacing: 0, lineSpacing: 6) {
            ForEach(nodes) { node in
                LatexNodeView(node: node)
            }
        }
    }
}

// MARK: - LaTeX 符号转换器 (简单模式)
struct SimpleLatexConverter {
    
    // 静态常量：希腊字母映射
    private static let greekLetters: [String: String] = [
        "\\alpha": "α", "\\beta": "β", "\\gamma": "γ", "\\delta": "δ",
        "\\epsilon": "ε", "\\zeta": "ζ", "\\eta": "η", "\\theta": "θ",
        "\\iota": "ι", "\\kappa": "κ", "\\lambda": "λ", "\\mu": "μ",
        "\\nu": "ν", "\\xi": "ξ", "\\pi": "π", "\\rho": "ρ",
        "\\sigma": "σ", "\\tau": "τ", "\\upsilon": "υ", "\\phi": "φ",
        "\\chi": "χ", "\\psi": "ψ", "\\omega": "ω",
        "\\Gamma": "Γ", "\\Delta": "Δ", "\\Theta": "Θ", "\\Lambda": "Λ",
        "\\Xi": "Ξ", "\\Pi": "Π", "\\Sigma": "Σ", "\\Phi": "Φ",
        "\\Psi": "Ψ", "\\Omega": "Ω"
    ]
    
    // 静态常量：数学运算符映射
    private static let mathSymbols: [String: String] = [
        "\\times": "×", "\\div": "÷", "\\pm": "±", "\\mp": "∓",
        "\\cdot": "·", "\\leq": "≤", "\\le": "≤", "\\geq": "≥", "\\ge": "≥",
        "\\neq": "≠", "\\ne": "≠", "\\approx": "≈", "\\equiv": "≡",
        "\\infty": "∞", "\\propto": "∝",
        "\\sum": "Σ", "\\prod": "Π", "\\int": "∫", "\\oint": "∮",
        "\\partial": "∂", "\\nabla": "∇", "\\forall": "∀", "\\exists": "∃",
        "\\in": "∈", "\\notin": "∉", "\\subset": "⊂", "\\supset": "⊃",
        "\\subseteq": "⊆", "\\supseteq": "⊇", "\\cup": "∪", "\\cap": "∩",
        "\\emptyset": "∅", "\\varnothing": "∅",
        "\\rightarrow": "→", "\\to": "→", "\\Rightarrow": "⇒", "\\implies": "⟹",
        "\\leftarrow": "←", "\\Leftarrow": "⇐",
        "\\leftrightarrow": "↔", "\\Leftrightarrow": "⇔", "\\iff": "⟺",
        "\\because": "∵", "\\therefore": "∴",
        "\\angle": "∠", "\\perp": "⊥", "\\parallel": "∥",
        "\\triangle": "△", "\\circ": "°", "\\sqrt": "√"
    ]
    
    // 静态常量：上标映射
    private static let superscripts: [String: String] = [
        "^{0}": "⁰", "^{1}": "¹", "^{2}": "²", "^{3}": "³", "^{n}": "ⁿ",
        "^0": "⁰", "^1": "¹", "^2": "²", "^3": "³", "^n": "ⁿ", "^m": "ᵐ"
    ]
    
    // 静态常量：下标映射
    private static let subscripts: [String: String] = [
        "_{0}": "₀", "_{1}": "₁", "_{2}": "₂", "_{n}": "ₙ", "_{m}": "ₘ", "_{i}": "ᵢ",
        "_0": "₀", "_1": "₁", "_2": "₂", "_n": "ₙ", "_m": "ₘ", "_i": "ᵢ", "_a": "ₐ", "_b": "ᵦ"
    ]
    
    // 缓存的正则表达式
    private static let fracRegex = try? NSRegularExpression(pattern: "\\\\frac\\{([^}]*)\\}\\{([^}]*)\\}")
    private static let barRegex = try? NSRegularExpression(pattern: "\\\\bar\\{([^}]*)\\}")
    private static let vecRegex = try? NSRegularExpression(pattern: "\\\\vec\\{([^}]*)\\}")
    private static let binomRegex = try? NSRegularExpression(pattern: "\\\\binom\\{([^}]*)\\}\\{([^}]*)\\}")
    private static let commandRegex = try? NSRegularExpression(pattern: "\\\\([a-zA-Z]+)")
    
    /// 转换 LaTeX 数学符号（不处理 Markdown）
    static func convertLatexOnly(_ text: String) -> String {
        var result = text
        
        // 1. 移除数学模式标记 (单个和双个 $)
        result = result.replacingOccurrences(of: "$$", with: "")
        result = result.replacingOccurrences(of: "$", with: "")
        
        // 2. 预处理：先把 \text{内容} 替换为 [内容]，避免花括号干扰
        let textPattern = "\\\\text\\s*\\{([^{}]*)\\}"
        if let regex = try? NSRegularExpression(pattern: textPattern) {
            for _ in 0..<5 {
                let newResult = regex.stringByReplacingMatches(
                    in: result, range: NSRange(result.startIndex..., in: result),
                    withTemplate: "[$1]"
                )
                if newResult == result { break }
                result = newResult
            }
        }
        
        // 3. 处理 \sqrt{} -> √()
        let sqrtPattern = "\\\\sqrt\\s*\\{([^{}]*)\\}"
        if let regex = try? NSRegularExpression(pattern: sqrtPattern) {
            for _ in 0..<5 {
                let newResult = regex.stringByReplacingMatches(
                    in: result, range: NSRange(result.startIndex..., in: result),
                    withTemplate: "√($1)"
                )
                if newResult == result { break }
                result = newResult
            }
        }
        
        // 4. 处理分数 \frac{a}{b} -> (a)/(b)
        // 迭代处理以应对嵌套
        let fracPattern = "\\\\frac\\s*\\{([^{}]*)\\}\\s*\\{([^{}]*)\\}"
        if let regex = try? NSRegularExpression(pattern: fracPattern) {
            for _ in 0..<10 {
                let newResult = regex.stringByReplacingMatches(
                    in: result, range: NSRange(result.startIndex..., in: result),
                    withTemplate: "($1)/($2)"
                )
                if newResult == result { break }
                result = newResult
            }
        }
        
        // 5. 上划线: \bar{x} -> x̄
        let barPattern = "\\\\bar\\s*\\{([^{}]*)\\}"
        if let regex = try? NSRegularExpression(pattern: barPattern) {
            result = regex.stringByReplacingMatches(
                in: result, range: NSRange(result.startIndex..., in: result),
                withTemplate: "$1̄"
            )
        }
        
        // 6. 向量: \vec{x} -> x⃗
        let vecPattern = "\\\\vec\\s*\\{([^{}]*)\\}"
        if let regex = try? NSRegularExpression(pattern: vecPattern) {
            result = regex.stringByReplacingMatches(
                in: result, range: NSRange(result.startIndex..., in: result),
                withTemplate: "$1⃗"
            )
        }
        
        // 7. 组合数: \binom{n}{k} -> C(n,k)
        let binomPattern = "\\\\binom\\s*\\{([^{}]*)\\}\\s*\\{([^{}]*)\\}"
        if let regex = try? NSRegularExpression(pattern: binomPattern) {
            result = regex.stringByReplacingMatches(
                in: result, range: NSRange(result.startIndex..., in: result),
                withTemplate: "C($1,$2)"
            )
        }
        
        // 8. 希腊字母
        for (latex, symbol) in greekLetters {
            result = result.replacingOccurrences(of: latex, with: symbol)
        }
        
        // 9. 数学运算符
        for (latex, symbol) in mathSymbols {
            result = result.replacingOccurrences(of: latex, with: symbol)
        }
        
        // 10. 上下标
        for (latex, symbol) in superscripts {
            result = result.replacingOccurrences(of: latex, with: symbol)
        }
        for (latex, symbol) in subscripts {
            result = result.replacingOccurrences(of: latex, with: symbol)
        }
        
        // 11. 移除剩余的 LaTeX 命令 (保留命令名)
        if let regex = commandRegex {
            result = regex.stringByReplacingMatches(
                in: result, range: NSRange(result.startIndex..., in: result),
                withTemplate: "$1"
            )
        }
        
        // 12. 清理花括号
        result = result.replacingOccurrences(of: "{", with: "")
        result = result.replacingOccurrences(of: "}", with: "")
        
        // 13. 恢复 \text 的方括号为普通文本
        result = result.replacingOccurrences(of: "[", with: "")
        result = result.replacingOccurrences(of: "]", with: "")
        
        return result
    }
}

// 智能分词：处理中英文混排
private func smartTokenize(_ str: String) -> [String] {
    var tokens: [String] = []
    var currentToken = ""
    
    for char in str {
        if char == " " {
            if !currentToken.isEmpty {
                tokens.append(currentToken)
                currentToken = ""
            }
            tokens.append(" ")
        } else if isCJK(char) {
            //如果是中文，先结算之前的 token
            if !currentToken.isEmpty {
                tokens.append(currentToken)
                currentToken = ""
            }
            // 中文单独成 token
            tokens.append(String(char))
        } else {
            // 英文、数字、符号等，累积
            currentToken.append(char)
        }
    }
    
    if !currentToken.isEmpty {
        tokens.append(currentToken)
    }
    
    return tokens
}

// 判断是否为 CJK 字符
private func isCJK(_ char: Character) -> Bool {
    guard let scalar = char.unicodeScalars.first else { return false }
    // 简单的 CJK 范围判断
    return scalar.value >= 0x4E00 && scalar.value <= 0x9FFF
        || scalar.value >= 0x3000 && scalar.value <= 0x303F // 标点
        || scalar.value >= 0xFF00 && scalar.value <= 0xFFEF // 全角
}
             
// MARK: - 递归节点渲染
struct LatexNodeView: View {
    let node: LatexNode
    
    var body: some View {
        switch node {
        case .text(let str):
            // 使用智能分词，确保中文和英文长句都能在 FlowLayout 中正确换行
            ForEach(Array(smartTokenize(str).enumerated()), id: \.offset) { item in
                let token = item.element
                if token == "\n" {
                     // 换行符：使用一个满宽的占位元素强制换行
                     Color.clear
                         .frame(maxWidth: .infinity, minHeight: 1)
                } else if token == " " {
                     // 空格：完全不可见
                     Text("").frame(width: 3)
                } else {
                     Text(token).font(.system(size: 14))
                }
            }
            
        case .inlineMath(let str):
             MathText(text: str, size: 14)
             
        case .mathFunction(let name):
             MathText(text: name, size: 14) // 正体
             
        case .symbol(let sym):
             MathText(text: sym, size: 14)
             
        case .fraction(let num, let den):
             FractionView(numNodes: num, denNodes: den)
                 .padding(.horizontal, 2)
                 
        case .root(let content, let power):
            rootView(content: content, power: power)
            
        case .script(let base, let sup, let sub):
             scriptView(base: base, sup: sup, sub: sub)
             
        case .accent(let type, let content):
             AccentView(type: type, content: content)
             
        case .binom(let n, let k):
             BinomView(nNodes: n, kNodes: k)
                 .padding(.horizontal, 2)
                 
        case .group(let nodes):
             ForEach(nodes) { n in LatexNodeView(node: n) }
        }
    }
    
    // 根号视图构建 (使用 overlay 确保横线与内容同宽)
    @ViewBuilder
    func rootView(content: [LatexNode], power: [LatexNode]?) -> some View {
        HStack(alignment: .bottom, spacing: 0) {
            // 可选的指数 (如 ³√)
            if let p = power {
                HStack(spacing: 0) {
                    ForEach(p) { n in LatexNodeView(node: n).scaleEffect(0.6) }
                }
                .offset(y: -8)
            }
            
            // 根号符号
            Text("√")
                .font(.system(size: 16))
            
            // 内容 + 顶部横线
            HStack(spacing: 0) {
                ForEach(content) { n in LatexNodeView(node: n) }
            }
            .overlay(alignment: .top) {
                // 横线紧贴内容顶部，宽度自动匹配
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(.white)
                    .offset(y: -2)
            }
        }
        .fixedSize()
    }
    
    // 上下标视图构建
    @ViewBuilder
    func scriptView(base: [LatexNode]?, sup: [LatexNode]?, sub: [LatexNode]?) -> some View {
        HStack(spacing: 0) {
            if let b = base {
                ForEach(b) { n in LatexNodeView(node: n) }
            }
            VStack(spacing: 0) {
                if let s = sup {
                    HStack(spacing:0) {
                        ForEach(s) { n in LatexNodeView(node: n).scaleEffect(0.7) }
                    }
                    .offset(y: -4)
                }
                if let s = sub {
                    HStack(spacing:0) {
                        ForEach(s) { n in LatexNodeView(node: n).scaleEffect(0.7) }
                    }
                    .offset(y: 4)
                }
            }
        }
    }
}

// 支持装饰符号 (bar, vec, hat, dot)
struct AccentView: View {
    let type: String
    let content: [LatexNode]
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部符号 - 使用 overlay 确保与内容同宽
            ZStack {
                // 占位，确保宽度
                HStack(spacing: 0) {
                    ForEach(content) { n in LatexNodeView(node: n) }
                }
                .opacity(0) // 隐藏，只占位
                
                // 真正的装饰符号
                if type == "vec" {
                    Image(systemName: "arrow.right").font(.system(size: 8))
                } else if type == "bar" || type == "overline" {
                    Rectangle().frame(height: 1).foregroundColor(.white)
                } else if type == "hat" {
                    Text("^").font(.system(size: 10))
                } else if type == "dot" {
                    Text("·").font(.system(size: 10))
                } else if type == "tilde" || type == "widetilde" {
                    Text("~").font(.system(size: 10))
                }
            }
            .frame(height: 8) // 固定装饰符号高度
            
            // 实际内容
            HStack(spacing: 0) {
                ForEach(content) { n in LatexNodeView(node: n) }
            }
        }
        .fixedSize() // 关键：防止 VStack 扩展到无限宽
    }
}

// 二项式系数视图
struct BinomView: View {
    let nNodes: [LatexNode]
    let kNodes: [LatexNode]
    
    var body: some View {
        HStack(spacing: 0) {
            Text("(").font(.system(size: 14)).scaleEffect(y: 2.0)
            VStack(spacing: 2) {
                HStack(spacing: 0) {
                     ForEach(nNodes) { n in LatexNodeView(node: n).scaleEffect(0.9) }
                }
                HStack(spacing: 0) {
                     ForEach(kNodes) { n in LatexNodeView(node: n).scaleEffect(0.9) }
                }
            }
            Text(")").font(.system(size: 14)).scaleEffect(y: 2.0)
        }
    }
}

// MARK: - 分数视图
struct FractionView: View {
    let numNodes: [LatexNode]
    let denNodes: [LatexNode]
    
    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 0) {
                ForEach(numNodes) { n in LatexNodeView(node: n).scaleEffect(0.9) }
            }
            Rectangle().frame(height: 1).foregroundColor(.white)
            HStack(spacing: 0) {
                ForEach(denNodes) { n in LatexNodeView(node: n).scaleEffect(0.9) }
            }
        }
        .fixedSize()
    }
}

// MARK: - 混合内容视图 (Entry Point)
struct MixedContentView: View {
    let text: String
    
    var body: some View {
        let parts = text.components(separatedBy: "```")
        VStack(alignment: .leading, spacing: 6) {
             ForEach(parts.indices, id: \.self) { i in
                 if i % 2 == 1 {
                     // 代码块
                     VStack(alignment: .leading, spacing: 0) {
                         Text(parts[i].trimmingCharacters(in: .whitespacesAndNewlines))
                             .font(.system(size: 11, design: .monospaced))
                             .foregroundColor(.green.opacity(0.8))
                             .padding(8)
                     }
                     .background(Color.black.opacity(0.4))
                     .cornerRadius(6)
                     .frame(maxWidth: .infinity, alignment: .leading)
                 } else {
                     // 普通文本 (支持公式)
                     let part = parts[i]
                     if !part.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                         MessageContentView(text: part)
                     }
                 }
             }
        }
    }
}
