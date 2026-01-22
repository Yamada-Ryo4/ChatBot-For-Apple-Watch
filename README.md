# ChatBot for Apple Watch ⌚️🤖

<p align="center">
  <img src="https://img.shields.io/badge/Platform-watchOS_10.0+-lightgrey.svg?style=flat" alt="Platform watchOS">
  <img src="https://img.shields.io/badge/Language-Swift-orange.svg?style=flat" alt="Language Swift">
  <img src="https://img.shields.io/badge/License-MIT-yellow.svg?style=flat" alt="License">
</p>

**ChatBot for Apple Watch** 是首个专为 Apple Watch 设计的现代化、全功能大语言模型（LLM）客户端。

它打破了单一模型应用的限制，构建了一个通用的 AI 交互平台。无论您是习惯使用 **OpenAI**、**Google Gemini**，还是偏好国内的 **DeepSeek**、**智谱 AI**、**通义千问**，亦或是自建的 **Ollama** 服务，都可以通过此 App 在手腕上无缝调用。

App 采用原生的 SwiftUI 构建，针对 watchOS 的小屏幕进行了深度交互优化，支持流式响应、多模态输入以及高度的个性化配置，是您腕上的全能 AI 助手。

## ✨ 全功能特性 (Feature Highlights)

### � 极致对话体验
* **⚡️ 极速流式响应 (Streaming)**: 采用 Server-Sent Events (SSE) 技术，像打字机一样实时显示 AI 回复，拒绝转圈等待。
* **✏️ 行内消息编辑 (Inline Edit)**: 发错消息不用重来！直接在气泡上点击编辑按钮，修改后 AI 会自动根据新内容重新生成回复。
* **🔄 一键重新生成 (Regenerate)**: 对 AI 的回答不满意？点击“重新生成”按钮，立即换一种说法。
* **🧠 智能上下文管理**: 自动管理最近 20 条对话记录，既保证了多轮对话的连贯性，又防止了 Watch 内存溢出。
* **🛑 随时中断**: 想要停止生成？点击输入框旁的停止按钮，立刻保存电量和 Token。

### 🖼️ 多模态与渲染引擎
* **📷 视觉模型支持 (Vision)**: 从手表相册选图发送，让 GPT-4o 或 Gemini-3-Pro 帮你识图懂图。
* **📝 强大的 Markdown 渲染**:
    * **代码高亮**: 清晰展示代码块。
    * **表格支持**: 专为手表屏幕优化的表格排版 (Vertical Bar + Short Separator)，小屏幕也能看报表。
    * **图片链接**: 自动渲染 Markdown 中的图片。
* **➗ 专业级 LaTeX 数学公式**:
    * 内置自定义解析器，支持 **矩阵**、**向量**、**嵌套分数**、**根号** 等复杂数学符号。
    * 完美处理物理公式（如 `\hat{i}`, `\vec{F}`）和对齐块。

### ⌨️ 输入与交互优化
* **📱 键盘协同 (Keyboard Sync)**: 优化的输入状态管理，确保使用 iPhone 键盘在手表上打字时不再断连或吞字。
* **⬇️ 快速回到底部**: 向上翻看历史记录时，右下角会自动浮现“回到底部”按钮，一键回到最新消息。
* **📳 触觉反馈 (Haptics)**: 发送、成功、报错、停止生成时都有细腻的震动反馈。
* **🧐 原始/渲染切换**: 点击气泡右下角的 `{}` 图标，瞬间切换渲染视图和原始 Markdown 文本，方便复制或检查源码。

### 🚀 全面的模型支持
* **预设主流服务商**:
    * **OpenAI** (官方 API)
    * **Google Gemini** (原生支持，自动处理路径)
    * **DeepSeek** (深度求索)
    * **智谱 AI** (GLM-4)
    * **阿里云百炼** (通义千问)
    * **硅基流动** (SiliconFlow)
    * **魔搭社区** (ModelScope)
    * **OpenRouter** (聚合平台)
* **自定义模型**: 可以在任意服务商下手动添加 Model ID (如 `gpt-4o-2024-05-13`)。
* **自建代理 (BYOL)**: 支持添加自定义 OpenAI 兼容接口，完美对接 OneAPI、NewAPI 或 Ollama 本地服务。

### 🔒 安全与隐私
* **BYOK 模式**: 仅作为客户端工具，所有 Token 直接发送至服务商。
* **本地存储**: 聊天记录和 API Key 仅保存在 Apple Watch 本地 (UserDefaults)，绝不上传至任何第三方服务器。
* **网络安全**: 遵循系统级网络安全策略 (ATS)，保障数据传输安全。

## 🚀 安装指南

### 方式一：直接安装 IPA (推荐)
前往项目的 **[Releases](https://github.com/Yamada-Ryo4/ChatBot-For-Apple-Watch/releases)** 页面，下载最新的 `.ipa` 文件。
推荐使用 **TrollStore**、**AltStore** 或 **Sideloadly** 等签名工具安装到您的 Apple Watch 上。

### 方式二：源码编译
出于隐私和签名配置的考虑，本仓库**未上传** `ChatBot.xcodeproj` 工程文件。如果您希望从源码编译：

1.  **克隆代码**:
    ```bash
    git clone https://github.com/Yamada-Ryo4/ChatBot-For-Apple-Watch.git
    ```
2.  **重建工程**:
    * 打开 Xcode，创建一个新的 **watchOS App** 项目。
    * 将 `ChatBot Watch App` 文件夹下的所有 `.swift` 文件拖入您的新工程中。
    * 确保删除了新工程默认生成的 `ContentView.swift` 和 `App.swift` (使用本项目的 `ChatBotApp.swift` 作为入口)。
3.  **配置依赖**:
    * 本项目无第三方 Swift Package 依赖，纯原生构建，拖入即用！
4.  **配置权限**:
    * 在 `Info.plist` 中添加 `NSPhotoLibraryUsageDescription` 权限（用于发送图片）。
    * 配置 `App Transport Security Settings` -> `Allow Arbitrary Loads` 为 `YES` (为了支持各种 HTTP/HTTPS 代理)。
5.  **编译运行**:
    * 连接真机或模拟器，开始编译。

## ⚙️ 快速上手

1.  **添加 Key**: 打开 App -> 左滑进入 **设置** -> 选择服务商 -> 填入 `API Key`。
2.  **设置模型**: 点击 **验证** -> 点亮心仪模型右侧的 ⭐ 号。
3.  **开始对话**: 回到首页，点击 **新对话** (New Chat) 即可畅聊！

## ⚠️ 免责声明

* 本项目是非官方开源客户端。
* 请妥善保管您的 API Key。
* 使用 AI 服务产生的费用由您向服务商支付。

## 📄 开源协议

MIT License
