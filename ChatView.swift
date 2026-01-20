import SwiftUI
import PhotosUI

struct ChatView: View {
    @StateObject var viewModel = ChatViewModel()
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
                                    MarkdownView(text: textWithoutImage)
                                }
                            } else {
                                // 使用完整 Markdown 渲染器
                                MarkdownView(text: cleanedText)
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
    var body: some View {
        List {
            Button("新建对话") { viewModel.createNewSession(); isPresented = false }
            ForEach(viewModel.sessions) { session in
                Button(session.title) { viewModel.selectSession(session); isPresented = false }
            }
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
