# ChatBot for Apple Watch ⌚️🤖

<p align="center">
  <img src="https://img.shields.io/badge/Platform-watchOS_10.0+-lightgrey.svg?style=flat" alt="Platform watchOS">
  <img src="https://img.shields.io/badge/Language-Swift-orange.svg?style=flat" alt="Language Swift">
  <img src="https://img.shields.io/badge/License-MIT-yellow.svg?style=flat" alt="License">
</p>

**ChatBot for Apple Watch** 是首个专为 Apple Watch 设计的现代化、全功能大语言模型（LLM）客户端。

它打破了单一模型应用的限制，构建了一个通用的 AI 交互平台。无论您是习惯使用 **OpenAI**、**Google Gemini**，还是偏好国内的 **DeepSeek**、**智谱 AI**、**通义千问**，亦或是自建的 **Ollama** 服务，都可以通过此 App 在手腕上无缝调用。

App 采用原生的 SwiftUI 构建，针对 watchOS 的小屏幕进行了深度交互优化，支持流式响应、多模态输入以及高度的个性化配置，是您腕上的全能 AI 助手。

## ✨ 核心功能

### 🚀 极致体验
* **⚡️ 极速流式响应 (Streaming)**: 采用 Server-Sent Events (SSE) 技术，像打字机一样实时显示 AI 回复，拒绝转圈等待，提供丝滑的对话体验。
* **🖼️ 多模态视觉支持**: 支持从手表相册选择图片发送给 AI 进行分析（需模型本身支持 Vision 能力，如 GPT-4o, Gemini Pro Vision 等）。
* **📝 原生 Markdown 渲染**: 完美支持粗体、斜体、列表、代码块，甚至可以直接渲染 AI 返回的 **Markdown 图片链接**。

### 🌍 全面的模型支持
内置了主流大模型服务商的预设配置，支持一键切换，开箱即用：
* **国际主流**:
    * OpenAI (官方 API)
    * Google Gemini (原生 API，自动处理 URL 路径)
    * OpenRouter (聚合服务)
* **国内精选**:
    * DeepSeek (深度求索)
    * 智谱 AI (BigModel / GLM-4)
    * 阿里云百炼 (通义千问 / Qwen)
    * 硅基流动 (SiliconFlow)
    * 魔搭社区 (ModelScope)

### 🛠️ 高度可定制化
* **自定义 Base URL**: 轻松连接自建代理（如 OneAPI、NewAPI）或企业内部的中转服务。
* **自定义模型 ID**: 不仅仅局限于预设模型！您可以在每个供应商下手动添加任意模型 ID（如 `gpt-4o-2024-05-13` 或微调模型 ID），并为其设置专属备注。
* **收藏夹管理**: 将常用的模型加入收藏，在首页快速切换，无需反复查找。

### 🔒 安全与隐私
* **BYOK 模式 (Bring Your Own Key)**: 我们不提供公共服务，您需要使用自己的 API Key。
* **本地存储**: 所有的 API Key 和聊天记录仅存储在您的 Apple Watch 本地（UserDefaults），绝不上传至任何第三方服务器，最大程度保障您的隐私安全。

## 🚀 安装与运行

* 由于本项目是一个开源客户端，您需要通过 Xcode 编译安装到您的手表上。
* Release中提供了ipa安装包可供安装

### 环境要求
* **macOS**: 运行 macOS Sonoma 或更高版本。
* **Xcode**: 15.0+ (建议使用最新版本)。
* **watchOS**: 11.5+ (项目使用了 watchOS 10 的最新 SwiftUI API，不支持旧版本，性能占用较大，建议使用s7以上设备)。
* **Swift**: 5.9+。

### 编译步骤
1.  **克隆项目**:
    打开终端，执行以下命令将项目克隆到本地：
    ```bash
    git clone https://github.com/Yamada-Ryo4/ChatBot-For-Apple-Watch.git
    ```
2.  **打开项目**:
    使用 Xcode 打开 `ChatBot.xcodeproj` 文件。
3.  **配置签名**:
    * 在左侧导航栏点击项目根节点。
    * 选择 `TARGETS` -> `ChatBot Watch App`。
    * 点击 `Signing & Capabilities` 选项卡。
    * 在 `Team` 下拉菜单中选择您的 Apple ID 开发团队。
    * 修改 `Bundle Identifier` 为唯一的 ID (例如 `com.yourname.chatbot`) 以避免冲突。
4.  **运行**:
    * 将您的 Apple Watch 连接到 Mac（或选择 watchOS 模拟器）。
    * 点击 Xcode 左上角的运行按钮 (或按 `Cmd + R`)。

## ⚙️ 使用指南

### 1. 配置供应商 (Provider)
App 首次启动时会预设一系列主流供应商。
1.  在首页向右滑动或点击左上角图标进入 **设置** 页面。
2.  在 **"供应商配置"** 列表中，选择您想要使用的服务商（例如 `DeepSeek`）。
3.  **填写 API Key**: 输入您在该服务商平台申请的 API Key（通常以 `sk-` 开头）。
4.  **验证**: 点击 **"验证 Key 并获取模型"** 按钮。App 会尝试连接服务器并拉取可用模型列表。
5.  **启用模型**: 验证成功后，下方会出现模型列表。点击您想要使用的模型右侧的星星图标 ⭐，将其加入收藏。

### 2. 添加自定义模型
如果预设列表中没有您想要使用的特殊模型（例如某个刚发布的预览版模型）：
1.  进入对应的供应商详情页。
2.  点击 **"手动添加自定义模型"**。
3.  **模型 ID**: 输入模型在 API 中的准确 ID (例如 `gemini-1.5-pro-latest`)。
4.  **备注名称**: 起一个好记的名字 (例如 `Gemini 1.5 Pro`)。
5.  点击保存，该模型将自动加入收藏列表并在首页可用。

### 3. 连接自建代理 / OneAPI
如果您使用 OneAPI、NewAPI 或其他中转服务：
1.  在设置页点击底部的 **"添加自定义供应商"**。
2.  **名称**: 给您的服务起个名字 (如 `我的 OneAPI`)。
3.  **接口类型**: 选择 **"OpenAI 兼容"**。
4.  **Base URL**: 输入您的代理地址 (例如 `https://api.my-domain.com/v1`)。
5.  **API Key**: 输入您的令牌。
6.  保存后，按上述步骤验证并添加模型。

## 🏗️ 技术细节

* **UI 框架**: 完全基于 **SwiftUI** 构建，采用了 NavigationStack 和 ScrollViewReader 实现流畅的聊天流。
* **网络层**: 基于 `URLSession` 和 Swift Concurrency (`async/await`)。
* **流式处理**: 使用 `AsyncThrowingStream` 手动解析 Server-Sent Events (SSE) 数据流，实现打字机效果。
* **架构模式**: 遵循 MVVM (Model-View-ViewModel) 设计模式，逻辑与视图分离，易于维护和扩展。
* **数据持久化**: 使用 `UserDefaults` 配合 `Codable` 协议存储轻量级配置数据。

## ⚠️ 免责声明

* 本项目是非官方的开源客户端，与 OpenAI、Google、DeepSeek 等公司无任何关联。
* 请妥善保管您的 API Key，不要将其泄露给他人。
* App 自身不提供任何 AI 服务，使用过程中产生的 API 调用费用由您直接向对应的服务商支付。

## 📄 开源协议

本项目采用 [MIT License](LICENSE) 协议开源。欢迎提交 Issue 和 Pull Request 共同改进！
