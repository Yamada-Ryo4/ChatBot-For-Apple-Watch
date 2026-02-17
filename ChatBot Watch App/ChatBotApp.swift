import SwiftUI
import ClockKit

@main
struct ChatBotApp: App {
    // 注入 ViewModel 以便处理外部链接
    @StateObject private var viewModel = ChatViewModel()
    
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ChatView()
                .environmentObject(viewModel) // 向下传递
                .onOpenURL { url in
                    print("🔗 Deep Link Received: \(url)")
                    if url.scheme == "chatbot" {
                        if url.host == "new" {
                            // 新建对话
                            viewModel.createNewSession()
                        } else if url.host == "last" {
                            // 默认行为：打开上一次会话（无需操作）
                        }
                    }
                }
                .onChange(of: scenePhase) { newPhase in
                    if newPhase == .active {
                        // App 启动或从后台进入前台时尝试自动备份
                        viewModel.performAutoBackupIfNeeded()
                    }
                }
        }
    }
}

// MARK: - Complication Controller
// TODO: [v2.0] ClockKit 已在 watchOS 9+ 弃用，后续考虑迁移至 WidgetKit
public class ComplicationController: NSObject, CLKComplicationDataSource {
    
    // MARK: - Timeline Configuration
    
    public func getComplicationDescriptors(handler: @escaping ([CLKComplicationDescriptor]) -> Void) {
        let descriptors = [
            CLKComplicationDescriptor(identifier: "complication", displayName: "ChatBot", supportedFamilies: [
                .circularSmall,
                .graphicCircular,
                .graphicCorner,
                .graphicRectangular,
                .modularSmall,
                .modularLarge,
                .utilitarianSmall,
                .utilitarianSmallFlat,
                .utilitarianLarge
            ])
        ]
        
        // 调用 handler 传入描述符
        handler(descriptors)
    }
    
    public func handleSharedComplicationDescriptors(_ complicationDescriptors: [CLKComplicationDescriptor]) {
        // 不需要处理
    }

    // MARK: - Timeline Population
    
    public func getCurrentTimelineEntry(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationTimelineEntry?) -> Void) {
        // 从 UserDefaults 读取最后一条消息
        var headerText = "ChatBot"
        var bodyText = "No messages"
        
        if let data = UserDefaults.standard.data(forKey: "chatSessions_v1"),
           let sessions = try? JSONDecoder().decode([ChatSession].self, from: data),
           let lastSession = sessions.first { // 已经排好序了
            
            // 尝试获取最后一条非 System 消息
            if let lastMsg = lastSession.messages.last(where: { $0.role != .system }) {
                let prefix = lastMsg.role == .user ? "You: " : "AI: "
                bodyText = prefix + lastMsg.text
            } else {
                bodyText = lastSession.title
            }
        }
        
        // 创建模版
        var template: CLKComplicationTemplate?
        
        switch complication.family {
        case .graphicRectangular:
            // 矩形大卡片 (Smart Stack 常用)
            template = CLKComplicationTemplateGraphicRectangularStandardBody(
                headerTextProvider: CLKSimpleTextProvider(text: headerText),
                body1TextProvider: CLKSimpleTextProvider(text: bodyText),
                body2TextProvider: CLKSimpleTextProvider(text: "") // 可选第二行，暂空
            )
        case .modularLarge:
            // 传统大模组
            template = CLKComplicationTemplateModularLargeStandardBody(
                headerTextProvider: CLKSimpleTextProvider(text: headerText),
                body1TextProvider: CLKSimpleTextProvider(text: bodyText)
            )
        case .utilitarianLarge:
            // 长条形
            template = CLKComplicationTemplateUtilitarianLargeFlat(
                textProvider: CLKSimpleTextProvider(text: bodyText)
            )
        case .circularSmall, .graphicCircular, .modularSmall, .utilitarianSmall:
            // 圆形小图标
            template = CLKComplicationTemplateGraphicCircularImage(
                imageProvider: CLKFullColorImageProvider(fullColorImage: UIImage(systemName: "bubble.left.and.bubble.right.fill")!)
            )
        case .graphicCorner:
            // 角落
             template = CLKComplicationTemplateGraphicCornerTextImage(
                textProvider: CLKSimpleTextProvider(text: "Chat"),
                imageProvider: CLKFullColorImageProvider(fullColorImage: UIImage(systemName: "bubble.left.fill")!)
            )
        default:
            template = nil
        }
        
        if let template = template {
            let entry = CLKComplicationTimelineEntry(date: Date(), complicationTemplate: template)
            handler(entry)
        } else {
            handler(nil)
        }
    }
    
    // MARK: - Placeholder
    
    public func getLocalizableSampleTemplate(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationTemplate?) -> Void) {
        var template: CLKComplicationTemplate?
        switch complication.family {
        case .graphicRectangular:
            template = CLKComplicationTemplateGraphicRectangularStandardBody(
                headerTextProvider: CLKSimpleTextProvider(text: "ChatBot"),
                body1TextProvider: CLKSimpleTextProvider(text: "AI: Hello World"),
                body2TextProvider: CLKSimpleTextProvider(text: "")
            )
        case .modularLarge:
             template = CLKComplicationTemplateModularLargeStandardBody(
                 headerTextProvider: CLKSimpleTextProvider(text: "ChatBot"),
                 body1TextProvider: CLKSimpleTextProvider(text: "AI: Hello World")
             )
        case .graphicCircular:
            template = CLKComplicationTemplateGraphicCircularImage(
                imageProvider: CLKFullColorImageProvider(fullColorImage: UIImage(systemName: "bubble.left.and.bubble.right.fill")!)
            )
        default:
            // 其他类型暂略，防止编译太长，核心是 GraphicRectangular
            template = nil
        }
        handler(template)
    }
}
