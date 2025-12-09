import SwiftUI
import PhotosUI

struct ChatView: View {
    @StateObject var viewModel = ChatViewModel()
    @Namespace private var bottomID
    @State private var showHistory = false
    
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        Spacer().frame(height: 5)
                        
                        if viewModel.currentMessages.isEmpty {
                            EmptyStateView()
                        }
                        
                        ForEach(viewModel.currentMessages) { msg in
                            PrettyMessageBubble(message: msg)
                                .id(msg.id)
                        }
                        
                        if viewModel.isLoading {
                            ThinkingIndicator()
                        }
                        
                        BottomInputArea(viewModel: viewModel)
                            .id(bottomID)
                            .padding(.top, 10)
                            .padding(.bottom, 10)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .padding(.horizontal, 8)
                }
                .onChange(of: viewModel.currentMessages.count) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo(bottomID, anchor: .bottom)
                    }
                }
                .onChange(of: viewModel.currentMessages.last?.text) {
                    proxy.scrollTo(bottomID, anchor: .bottom)
                }
                .onAppear {
                    proxy.scrollTo(bottomID, anchor: .bottom)
                }
            }
            .navigationTitle(viewModel.currentDisplayModelName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink(destination: SettingsView(viewModel: viewModel)) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.gray)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showHistory = true } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.blue)
                    }
                }
            }
            .sheet(isPresented: $showHistory) {
                HistoryListView(viewModel: viewModel, isPresented: $showHistory)
            }
        }
    }
}

// 底部输入区域
struct BottomInputArea: View {
    @ObservedObject var viewModel: ChatViewModel
    
    var body: some View {
        let hasImage = viewModel.selectedImageData != nil
        
        HStack(spacing: 8) {
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
            
            ZStack(alignment: .leading) {
                Capsule().fill(Color.gray.opacity(0.3)).frame(height: 36)
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
            .layoutPriority(1)
            
            if !viewModel.inputText.isEmpty || hasImage {
                Button(action: viewModel.sendMessage) {
                    ZStack {
                        Circle().fill(Color.green).frame(width: 36, height: 36)
                        Image(systemName: "arrow.up").font(.system(size: 16, weight: .bold)).foregroundColor(.black)
                    }
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
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

// 增强版消息气泡：支持 Markdown 图片显示
struct PrettyMessageBubble: View {
    let message: ChatMessage
    
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
                
                // 2. 文本内容 (增强解析)
                if !message.text.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        // 检测是否包含 Markdown 图片语法: ![alt](url)
                        if let imageURL = extractImageURL(from: message.text) {
                            // 如果检测到图片链接，优先显示图片
                            AsyncImage(url: imageURL) { phase in
                                switch phase {
                                case .success(let image):
                                    image.resizable().aspectRatio(contentMode: .fit)
                                        .cornerRadius(8)
                                case .failure:
                                    HStack {
                                        Image(systemName: "photo.badge.exclamationmark")
                                        Text("图片加载失败").font(.caption)
                                    }.foregroundColor(.red)
                                case .empty:
                                    ProgressView().padding()
                                @unknown default:
                                    EmptyView()
                                }
                            }
                            .frame(maxWidth: 150) // 限制图片最大宽度
                            
                            // 显示剩余的文本（如果有）
                            let textWithoutImage = message.text.replacingOccurrences(of: "!\\[.*?\\]\\(.*?\\)", with: "", options: .regularExpression)
                            if !textWithoutImage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(textWithoutImage)
                                    .font(.system(size: 15))
                            }
                        } else {
                            // 普通文本解析
                            ForEach(Array(message.text.components(separatedBy: "\n").enumerated()), id: \.offset) { index, line in
                                if line.hasPrefix("### ") {
                                    Text(String(line.dropFirst(4))).font(.system(size: 16, weight: .bold))
                                } else {
                                    if line.isEmpty { Text(" ").font(.system(size: 8)) }
                                    else { Text(.init(line)).font(.system(size: 15)) }
                                }
                            }
                        }
                    }
                    .padding(10)
                    .background(message.role == .user ? Color.blue : Color.gray.opacity(0.3))
                    .cornerRadius(12)
                    .foregroundColor(.white)
                }
            }
            
            if message.role == .assistant { Spacer() }
        }
    }
    
    // 简单的正则提取 Markdown 图片 URL
    private func extractImageURL(from text: String) -> URL? {
        // 匹配 ![...](http...)
        let pattern = "!\\[.*?\\]\\((https?://.*?)\\)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let nsString = text as NSString
        if let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: nsString.length)) {
            let urlString = nsString.substring(with: match.range(at: 1))
            return URL(string: urlString)
        }
        return nil
    }
}

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

struct ThinkingIndicator: View {
    var body: some View {
        HStack { Text("Thinking...").font(.caption).foregroundColor(.gray); Spacer() }
    }
}
