import SwiftUI

/// 极简 Markdown 解析器 - 纯文本转换
struct MarkdownParser {
    
    static func format(_ text: String) -> String {
        // 核心逻辑：先按 ``` 分割，奇数索引为代码块，偶数索引为普通文本
        // 只有普通文本才进行 Markdown 和 LaTeX 解析
        // 代码块保持原样
        
        let parts = text.components(separatedBy: "```")
        var result = ""
        
        for (index, part) in parts.enumerated() {
            if index % 2 == 1 {
                // --- 代码块部分 ---
                // 保留原样，或者简单美化
                // 移除可能的语言标识符 (如 ```swift\n -> \n)
                var codeContent = part
                if let firstLineEnd = codeContent.firstIndex(of: "\n") {
                    // 如果第一行很短且不包含空格，可能是语言 ID
                    let firstLine = codeContent[..<firstLineEnd]
                    if firstLine.count < 15 && !firstLine.contains(" ") {
                        codeContent.removeSubrange(..<firstLineEnd)
                    }
                }
                
                // 给代码块加一个视觉标记 (如果需要)
                result += "───\n\(codeContent)\n───"
            } else {
                // --- 普通文本部分 ---
                // 正常解析 LaTeX 和 Markdown
                result += formatNormalText(part)
            }
        }
        
        return result
    }
    
    // 原有的解析逻辑，封装为私有方法
    private static func formatNormalText(_ text: String) -> String {
        // 1. 先进行 LaTeX 解析
        var r = LaTeXParser.parse(text)
        
        // 2. 表格处理
        if r.contains("|") {
            var lines = r.components(separatedBy: "\n")
            var inTable = false
            for i in 0..<lines.count {
                let line = lines[i].trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("|") || (line.contains("|") && line.contains("-")) {
                    inTable = true
                    
                    // 分割线处理：短分割线，防折行
                    if line.contains("---") {
                        lines[i] = "──────" 
                    } else {
                        // 内容行：恢复竖线分隔，用全角竖线或带空格的竖线
                        var formatted = line.replacingOccurrences(of: "|", with: " │ ")
                        // 清理首尾
                        if formatted.hasPrefix(" │ ") { formatted.removeFirst(3) }
                        if formatted.hasSuffix(" │ ") { formatted.removeLast(3) }
                        lines[i] = " " + formatted.trimmingCharacters(in: .whitespaces)
                    }
                } else {
                    inTable = false
                }
            }
            r = lines.joined(separator: "\n")
        }
        
        // 标题简化
        r = r.replacingOccurrences(of: "\n#### ", with: "\n• ")
        r = r.replacingOccurrences(of: "\n### ", with: "\n▪ ")
        r = r.replacingOccurrences(of: "\n## ", with: "\n▌")
        r = r.replacingOccurrences(of: "\n# ", with: "\n【")
        if r.hasPrefix("# ") { r = "【" + r.dropFirst(2) }
        
        // 列表符号
        r = r.replacingOccurrences(of: "\n- [ ] ", with: "\n☐ ")
        r = r.replacingOccurrences(of: "\n- [x] ", with: "\n☑ ")
        r = r.replacingOccurrences(of: "\n- [X] ", with: "\n☑ ")
        r = r.replacingOccurrences(of: "\n- ", with: "\n• ")
        r = r.replacingOccurrences(of: "\n* ", with: "\n• ")
        r = r.replacingOccurrences(of: "\n> ", with: "\n┃ ")
        
        // 分割线
        r = r.replacingOccurrences(of: "\n---\n", with: "\n──────\n")
        r = r.replacingOccurrences(of: "\n***\n", with: "\n──────\n")
        
        // 行内格式 (简单移除标记)
        r = r.replacingOccurrences(of: "**", with: "")
        r = r.replacingOccurrences(of: "~~", with: "")
        // 注意：不移除行内代码 `，因为它通常很短，不会造成混淆，或者可以视情况保留
        r = r.replacingOccurrences(of: "`", with: "") 
        
        return r
    }
}

/// 简单 Markdown 视图
struct MarkdownView: View {
    let text: String
    
    var body: some View {
        Text(MarkdownParser.format(text))
            .font(.system(size: 15))
    }
}
