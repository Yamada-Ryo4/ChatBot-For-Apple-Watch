# ChatBot for Apple Watch ⌚️🤖

<p align="center">
  <img src="https://img.shields.io/badge/Platform-watchOS_10.0+-lightgrey.svg?style=flat" alt="Platform watchOS">
  <img src="https://img.shields.io/badge/Language-Swift-orange.svg?style=flat" alt="Language Swift">
  <img src="https://img.shields.io/badge/License-MIT-yellow.svg?style=flat" alt="License">
</p>

**ChatBot for Apple Watch** 是一款专为 Apple Watch 打造的终极 AI 伴侣。它不仅仅是一个简单的 API 调用工具，而是一个针对腕上交互进行深度打磨、功能完备的智能终端。

无论您是开发者、学生还是 AI 爱好者，都能通过它在手腕上随时随地连接最强大的大语言模型。

---

## 🔥 核心特性 (Detailed Features)

### 1. 极致的对话与交互体验
*   **🚀 实时流式响应 (Real-time Streaming)**:
    *   采用 Server-Sent Events (SSE) 技术，实现打字机效果，毫秒级响应。
    *   彻底告别“转圈等待”，即时获取每一个 Token。
*   **⚡️ 智能上下文管理**:
    *   **自动修剪**: 智能保留最近 20 条对话记录，确保多轮对话连贯性的同时，防止 Watch 内存溢出 (OOM)。
    *   **Token 节省**: 超出限制的旧消息自动丢弃，既省钱又稳定。
*   **🛠 强大的消息控制**:
    *   **行内编辑 (Inline Edit)**: 发错消息或想微调 Prompt？直接点击气泡上的 ✏️ 按钮，原地修改，AI 自动重新生成。
    *   **重新生成 (Regenerate)**: 对回答不满意？点击用户消息下方的 🔄 按钮，立即换个角度回答。
    *   **随时中断 (Stop Generation)**: 发现苗头不对或内容太长？点击输入框旁的 ⏹️ 按钮，立即终止生成。
*   **⌨️ 原生级输入优化**:
    *   **键盘协同 (Continuity Keyboard)**: 完美解决 Apple Watch 与 iPhone 键盘连接不稳定的问题，打字不再“吞字”。
    *   **Draft State 模式**: 采用临时草稿态设计，防止视图刷新打断输入流程。

### 2. 桌面级渲染引擎 (Desktop-class Rendering)
在 40mm/44mm 的小屏幕上，也能获得不输桌面的阅读体验。
*   **📝 Markdown 全解析**:
    *   支持 **粗体**、*斜体*、`代码片段`、[链接](https://) 等标准语法。
    *   **代码高亮**: 支持多种编程语言的语法高亮显示。
*   **📊 表格 (Tables)**:
    *   专为手表优化的 "Vertical Bar" 排版风格。
    *   使用短分隔符 (`────`)，确保在小屏幕上也能清晰查看复杂数据表。
*   **➗ 专业数学公式 (LaTeX)**:
    *   内置高性能 LaTeX 解析器，无需联网即可渲染。
    *   支持 **矩阵 (Matrix)**、**向量 (Vector)**、**嵌套分数**、**根号**、**积分** 等。
    *   完美还原物理公式（如 `\hat{i}`, `\vec{F}`）和行内公式。
*   **🧐 源码/预览切换 (Raw Toggle)**:
    *   每条消息右下角提供 `{}` 按钮。
    *   一键切换“渲染视图”和“原始 Markdown 文本”，方便复制 Prompt 或检查公式源码。

### 3. 多模态与环境感知 (Multimodal & Context)
*   **� 视觉模型 (Vision)**:
    *   支持 GPT-4o、Gemini-1.5-Pro 等视觉模型。
    *   直接从手表相册选择图片发送，让 AI 帮你“看图说话”。
*   **📍 环境注入 (Environment Injection)**:
    *   **时间感知**: 自动将当前准确时间注入 System Prompt，AI 再也不会问“今年是哪一年”。
    *   **位置感知**: (可选) 获取当前地理位置坐标注入 Prompt，提供更精准的本地化服务（如天气查询）。

### 4. WatchOS 原生集成
深度融合 Apple Watch 系统特性，像原生 App 一样自然。
*   **🧩 表盘复杂功能 (Complications)**:
    *   支持角标、圆形等多种表盘位置。
    *   抬腕即可点击图标，一键唤醒 AI。
*   **🥞 智能叠放组件 (Smart Stack Widget)**:
    *   在表盘下滚动的智能叠放中查看 **最后一条消息** 和 **对话标题**。
    *   提供“新对话”快捷入口。
    *   *特别优化*: 采用轻量级数据读取机制，极低内存占用，永不崩溃。
*   **📳 触觉反馈 (Haptics)**:
    *   发送成功、收到回复、报错震动、停止生成... 每一个操作都有细腻的震动反馈。
*   **🌙 沉浸式 UI**:
    *   全黑背景设计，完美契合 OLED 屏幕，省电且护眼。
    *   支持动态字体 (Dynamic Type)。

### 5. 全面的模型生态
不再受限于单一厂商，把全世界的 AI 模型装进手表。
*   **🌍 预设主流厂商**:
    *   **OpenAI** (GPT-3.5, GPT-4, GPT-4o)
    *   **Google Gemini** (Gemini-Pro, Flash, 1.5)
    *   **DeepSeek** (深度求索 V3/R1)
    *   **Zhipu AI** (智谱 GLM-4)
    *   **Aliyun Qwen** (通义千问)
    *   **SiliconFlow** (硅基流动 - 聚合 DeepSeek/Qwen 等开源模型)
    *   **ModelScope** (魔搭社区)
    *   **OpenRouter** (聚合平台)
*   **🔧 高级自定义**:
    *   **自定义模型 ID**: 只要服务商支持，任何新出的模型 (如 `gpt-4o-2029-xx`) 都能手动填写 ID 使用。
    *   **自建代理 (BYOL)**: 支持任何兼容 OpenAI 格式的接口（如 OneAPI、NewAPI）。
    *   **本地模型**: 连接你电脑上的 **Ollama** 服务，实现完全离线的本地 AI 对话。

### 6. 隐私与安全
*   **🔒 数据本地化**: 
    *   所有聊天记录 (`UserDefaults`) 和 API Key 仅存储在您的 Apple Watch 本地。
    *   绝不上传至任何中间服务器或第三方统计平台。
*   **🛡 网络安全**:
    *   遵循 Apple ATS (App Transport Security) 标准。
    *   支持 HTTPS 安全连接。

---

## 🚀 安装与部署

### 方式一：直接安装 (IPA)
我们提供了预编译的 `.ipa` 文件，这是最简单的安装方式。
1.  前往 **[Releases](https://github.com/Yamada-Ryo4/ChatBot-For-Apple-Watch/releases)** 下载最新版本。
2.  使用 **TrollStore** (推荐)、**AltStore**、**Sideloadly** 或 ** 爱思助手** 进行签名安装。

### 方式二：源码编译 (Xcode)
如果您担心隐私或需要调试，可以从源码自行编译。
1.  **环境准备**: macOS + Xcode 15+ + Apple Watch (watchOS 10+).
2.  **克隆代码**: `git clone https://github.com/Yamada-Ryo4/ChatBot-For-Apple-Watch.git`
3.  **项目配置**:
    *   打开 Xcode，新建一个 watchOS App 项目。
    *   将 `ChatBot Watch App` 目录下的所有文件拖入新项目。
    *   **关键**: 移除新项目自动生成的 `ContentView.swift` 和 `App.swift`，确保使用本项目的 `ChatBotApp.swift` 作为 `App` 入口。
4.  **权限设置**:
    *   在 `Info.plist` 中添加 `Privacy - Photo Library Usage Description` (用于发图片功能)。
    *   若使用非 HTTPS 自建节点，需配置 `App Transport Security Settings` -> `Allow Arbitrary Loads` = YES。
5.  **编译**: 选择您的手表作为目标，点击 Run (⌘R)。

---

## ⚙️ 使用指南

1.  **配置服务**:
    *   打开 App，在首页左滑进入 **Settings** (设置)。
    *   点击 **Model Provider**，选择您的服务商 (如 OpenAI 或 DeepSeek)。
    *   输入您的 `API Key` (从各官网获取)。
    *   *(可选)* 点击 **Verify** 验证连通性。

2.  **选择模型**:
    *   在设置页点击 **Model**。
    *   您可以从 **Saved Models** (已保存) 列表中选择。
    *   也可以点击 **Add Custom Model** 手动输入模型 ID (如 `deepseek-chat`)。

3.  **开始对话**:
    *   回到首页，点击 **New Chat**。
    *   支持语音转文字、手写或键盘输入。
    *   点击右下角相册图标可发送图片。

4.  **管理对话**:
    *   在首页历史列表中，**左滑**某个对话可进行删除 (含二次确认)。
    *   点击历史对话可无缝恢复上下文。

---

## ⚖️ 常见问题 (FAQ)

*   **Q: 为什么生成的公式显示乱码？**
    *   A: 请点击气泡右下角的 `{}` 按钮查看原始文本。如果原始文本是标准的 LaTeX，通常是渲染器的限制。我们已针对绝大多数常用数学符号进行了适配。
*   **Q: Widget 显示空白或崩溃？**
    *   A: 请确保您已更新到最新版本。我们已在 v1.2 中重构了 Widget 的数读取逻辑，彻底修复了内存溢出问题。
*   **Q: 如何连接本地 Ollama？**
    *   A: 确保您的电脑和手表在同一局域网。将 API Base URL 设置为 `http://YOUR_PC_IP:11434/v1`，并在 Info.plist 中允许 HTTP 请求。

---

## ⚠️ 免责声明 (Disclaimer)
*   本项目仅为客户端工具，不提供任何 AI 模型服务。
*   请遵守您所在地区关于 AI 使用的相关法律法规。
*   API Key 存储在本地，请勿在公共设备上通过截图等方式泄露 Key。

## 📄 License
MIT License
