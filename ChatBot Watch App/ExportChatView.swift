import SwiftUI

// MARK: - 聊天导出视图 (v1.5)

struct ExportChatView: View {
    let session: ChatSession
    @State private var exportText: String = ""
    
    var body: some View {
        VStack {
            ScrollView {
                Text(exportText)
                    .font(.system(size: 10, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
            }
            
            ShareLink(item: exportText) {
                Label("分享", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)
        }
        .navigationTitle("导出")
        .onAppear {
            exportText = generateMarkdown()
        }
    }
    
    // 生成 Markdown 格式
    private func generateMarkdown() -> String {
        var md = "# \(session.title)\n\n"
        
        if let note = session.note, !note.isEmpty {
            md += "> 备注: \(note)\n\n"
        }
        
        md += "---\n\n"
        
        for msg in session.messages {
            let roleName = msg.role == .user ? "👤 用户" : "🤖 AI"
            md += "### \(roleName)\n\n"
            md += "\(msg.text)\n\n"
            
            
            // 添加时间统计 (如果有)
            if let genTime = msg.generationTimeMs {
                 md += "*生成耗时: \(String(format: "%.2f", Double(genTime)/1000.0))s*\n\n"
            }
        }
        
        // 汇总统计
        md += "---\n\n"
        md += "**导出时间**: \(Date().formatted())\n"
        
        return md
    }
}

// MARK: - 备注编辑视图
struct NoteEditView: View {
    @Binding var note: String
    let onSave: () -> Void
    
    @State private var editingNote: String = ""
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 12) {
            TextField("添加备注...", text: $editingNote)
                .textFieldStyle(.plain)
            
            HStack {
                Button("取消") {
                    dismiss()
                }
                .foregroundColor(.secondary)
                
                Spacer()
                
                Button("保存") {
                    note = editingNote
                    onSave()
                    dismiss()
                }
                .foregroundColor(.blue)
            }
        }
        .padding()
        .navigationTitle("编辑备注")
        .onAppear {
            editingNote = note
        }
    }
}
