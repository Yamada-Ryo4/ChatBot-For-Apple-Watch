import WidgetKit
import SwiftUI
// MARK: - Timeline Provider (数据源)
struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), lastMessage: "AI: Hello!", title: "ChatBot")
    }
    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        let entry = SimpleEntry(date: Date(), lastMessage: "AI: Weather is nice.", title: "ChatBot")
        completion(entry)
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        // 读取共享数据
        var message = "No messages"
        var title = "ChatBot"
        
        // 尝试从 AppGroup 或 UserDefaults 读取
        // 注意：如果不配置 App Groups，这里读不到主 App 的新数据，只能读到默认值
        if let data = UserDefaults.standard.data(forKey: "chatSessions_v1"),
           let sessions = try? JSONDecoder().decode([ChatSession].self, from: data),
           let first = sessions.first {
            title = first.title
            if let lastMsg = first.messages.last(where: { $0.role != .system }) {
                message = lastMsg.text
            }
        }
        
        let entry = SimpleEntry(date: Date(), lastMessage: message, title: title)
        let timeline = Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(900)))
        completion(timeline)
    }
}
// MARK: - Data Model
struct SimpleEntry: TimelineEntry {
    let date: Date
    let lastMessage: String
    let title: String
}
struct ChatSession: Codable {
    var id: UUID
    var title: String
    var messages: [ChatMessage]
    var lastModified: Date
}
struct ChatMessage: Codable {
    enum Role: String, Codable { case user, assistant, system }
    var id: UUID
    var role: Role
    var text: String
}
// MARK: - Widget View (UI)
struct ChatBotWidgetEntryView : View {
    var entry: Provider.Entry
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // 顶部：最近对话摘要
            Link(destination: URL(string: "chatbot://last")!) {
                VStack(alignment: .leading) {
                    Text(entry.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(entry.lastMessage)
                        .font(.system(size: 12))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            
            Spacer()
            
            // 底部：新对话按钮
            Link(destination: URL(string: "chatbot://new")!) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("New Chat")
                        .fontWeight(.bold)
                }
                .font(.caption)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.2))
                .cornerRadius(8)
            }
        }
        .containerBackground(for: .widget) {
            Color.black
        }
    }
}
// MARK: - Main Widget Configuration
// 注意：移除了 @main，因为它已经在 ChatBotWidgetBundle.swift 中定义了
struct ChatBotWidget: Widget {
    let kind: String = "ChatBotWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            ChatBotWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("ChatBot Quick Access")
        .description("Quickly start a new chat or resume the last one.")
        .supportedFamilies([.accessoryRectangular]) // Smart Stack 主要用这个
    }
}
