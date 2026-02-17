// MemoryView.swift
// ChatBot Watch App
// v1.7: 记忆管理界面

import SwiftUI

struct MemoryView: View {
    @ObservedObject var viewModel: ChatViewModel
    @State private var showAddSheet = false
    @State private var newMemoryText = ""
    @State private var showClearConfirm = false
    
    var body: some View {
        List {
            // 顶部统计
            Section {
                HStack {
                    Image(systemName: "brain.head.profile")
                        .foregroundColor(.purple)
                    Text("共 \(viewModel.memories.count) 条记忆")
                        .font(.caption)
                    Spacer()
                    let longCount = viewModel.memories.filter { $0.type == .longTerm }.count
                    let shortCount = viewModel.memories.filter { $0.type == .shortTerm }.count
                    Text("长\(longCount)/200 临\(shortCount)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            // 记忆列表
            if viewModel.memories.isEmpty {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "brain")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text("暂无记忆")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("对话后自动提取")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
            } else {
                Section(header: Text("记忆内容")) {
                    ForEach(viewModel.memories) { memory in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(memory.content)
                                .font(.caption)
                                .lineLimit(3)
                            
                            HStack {
                                if let source = memory.source {
                                    Text(source)
                                        .font(.system(size: 9))
                                        .foregroundColor(.blue)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Text(memory.createdAt, style: .date)
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .onDelete { offsets in
                        viewModel.deleteMemories(at: offsets)
                    }
                }
            }
            
            // 操作按钮
            Section {
                Button {
                    showAddSheet = true
                } label: {
                    Label("手动添加", systemImage: "plus.circle")
                }
                
                if !viewModel.memories.isEmpty {
                    Button(role: .destructive) {
                        showClearConfirm = true
                    } label: {
                        Label("清除全部", systemImage: "trash")
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .navigationTitle("记忆管理")
        .sheet(isPresented: $showAddSheet) {
            NavigationStack {
                VStack(spacing: 12) {
                    Text("添加记忆")
                        .font(.headline)
                    
                    TextField("如：我喜欢日本文化", text: $newMemoryText)
                        .textFieldStyle(.plain)
                    
                    Button("保存") {
                        viewModel.addMemory(newMemoryText)
                        newMemoryText = ""
                        showAddSheet = false
                    }
                    .disabled(newMemoryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
        }
        .alert("确认清除", isPresented: $showClearConfirm) {
            Button("清除", role: .destructive) {
                viewModel.clearAllMemories()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将删除所有 \(viewModel.memories.count) 条记忆")
        }
    }
}
