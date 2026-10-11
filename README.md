---
AIGC:
    Label: "1"
    ContentProducer: 001191440300708461136T1XGW3
    ProduceID: c246678a38a94bf2e839f4ad8865f533_5e8dba59c58311f197b3525400248c00
    ReservedCode1: UG+v6meYmyXcXqHbiXHynjtbb6MBjwIVOFgUQ/Ylo783LsTp2FmL6osFSB7lpis4Mfb8M/WAElwqGBWE29a9veZa1XncxzyPY4Fu/dj4VY6ywXNY41KP63usqz4gP1QLqluT6HzD7pVNw3uCqXSK4l/vPysJ61nW+alnUnGqVvBSNGBSzLA5FDwaens=
    ContentPropagator: 001191440300708461136T1XGW3
    PropagateID: c246678a38a94bf2e839f4ad8865f533_5e8dba59c58311f197b3525400248c00
    ReservedCode2: UG+v6meYmyXcXqHbiXHynjtbb6MBjwIVOFgUQ/Ylo783LsTp2FmL6osFSB7lpis4Mfb8M/WAElwqGBWE29a9veZa1XncxzyPY4Fu/dj4VY6ywXNY41KP63usqz4gP1QLqluT6HzD7pVNw3uCqXSK4l/vPysJ61nW+alnUnGqVvBSNGBSzLA5FDwaens=
---



# Talkroom

> 可导入任意 OpenAI 兼容 API 的第三方 LLM 聊天客户端（工程名 `llm_chat_app`）。

Talkroom 是一款基于 Flutter 的跨平台第三方 LLM 对话客户端。微信风格界面，支持任意 OpenAI 兼容的 `/chat/completions` 接口（含 SSE 流式输出），可自由配置模型与参数；除常规多会话聊天外，还支持 LLM 主动发消息、局域网双端配对同步、Chatbox 兼容的数据备份与导入导出。

当前最新正式版为 **v1.2.21**。

---

## 平台支持

| 平台 | 支持情况 |
| --- | --- |
| macOS | ✅ 原生桌面版（推荐，含 Liquid Glass 适配） |
| Android | ✅ 手机 / 平板 |
| iOS | ✅ iPhone / iPad |
| Web | ✅ 浏览器 |
| Windows / Linux | ⚙️ 工程已含桌面目录，可构建 |

## 核心功能

- **多会话聊天**：macOS 桌面端两栏布局（会话列表 + 聊天区，详情面板可展开），窄屏自动切换底部 Tab；SSE 流式输出，Markdown 渲染 + 代码高亮，支持停止生成与失败重试。
- **模型 / API 配置**：可添加任意 OpenAI 兼容 API（自定义 `base_url`、API Key、模型名），支持 `temperature` / `max_tokens` / `top_p` 参数；API Key 仅存入系统安全存储（macOS Keychain / Android Keystore / iOS Keychain 等），不落明文。
- **System Prompt**：全局默认 + 会话级覆盖。
- **主动消息**：定时任务触发 LLM 主动生成内容并写入会话，配合本地通知提醒；支持静默时段与启动补跑。
- **局域网配对同步**：电脑作为本地服务器（SQLite 为权威源），手机 / 电脑同一 Wi-Fi 下扫码或输入配对码完成配对，WebSocket 实时增量同步，支持离线待发队列。
- **数据备份与导入导出**：备份 / 恢复兼容 Chatbox 格式，便于数据迁移。
- **消息搜索**：全局搜索会话与消息内容。
- **性能图表**：消息统计与性能指标可视化。
- **macOS 桌面端体验**：v1.2.21 起设置页重构为「左侧分类导航 + 右侧详情面板」，并完成 Liquid Glass 视觉适配与扫码配对修复。

## 安装方式

从 [GitHub Releases](https://github.com/3310zx/talkroom/releases) 下载对应平台安装包：

- **macOS**：下载 `talkroom_vX.X.X.dmg`，打开后把 Talkroom 拖入「应用程序」文件夹即可。
- **Android**：下载 APK 文件，传输到手机后点击安装（需允许安装未知来源应用）。

## 开发构建

### 环境要求

| 项目 | 要求 |
| --- | --- |
| Flutter SDK | 3.x（Dart SDK >= 3.3） |
| macOS 构建 | Xcode（含 CommandLineTools 亦可编译 macOS） |
| Android 构建 | Android SDK + JDK 17 |

### 常用命令

```bash
flutter pub get          # 安装依赖
flutter run -d macos     # macOS 桌面开发运行
flutter run -d <设备id>  # Android / iOS 开发运行

# 发布构建
flutter build macos --release   # macOS 桌面版（产出 .app，可打包 dmg）
flutter build apk --release     # Android APK
```

## 当前版本状态

**v1.2.21（正式版）** 主要变化：

- 名称统一为 **Talkroom**。
- macOS 桌面端重构：两栏布局 + 详情面板、Liquid Glass 适配、设置页重构（左侧分类导航 + 右侧详情面板）。
- 扫码配对功能修复。

历史里程碑：M0 对话闭环 → P1 主动消息 → P1 局域网同步 → 体验优化与桌面端重构。剩余待办见 [TODO.md](./TODO.md)。
*（内容由AI生成，仅供参考）*
