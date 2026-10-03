---
AIGC:
    Label: "1"
    ContentProducer: 001191440300708461136T1XGW3
    ProduceID: c246678a38a94bf2e839f4ad8865f533_00e0b36fbf0111f197eb525400393706
    ReservedCode1: 3Nw5aazIArPYkFdTUVW1YmiiHzb8Ms8IOGx+gbTLZVnnuoWyLYrCznMlnxVTy/2hDllITXSTk3OkgFSpiaTUG3PqFfshJc2YV1j7B1lcdTNHmYmG5Sd21YEQhYTepF3aZ84ChGA54nVi55xjIPM7CfCJBo0+boHaTxDrDfQoYJnB+oqELx4JxChnGiQ=
    ContentPropagator: 001191440300708461136T1XGW3
    PropagateID: c246678a38a94bf2e839f4ad8865f533_00e0b36fbf0111f197eb525400393706
    ReservedCode2: 3Nw5aazIArPYkFdTUVW1YmiiHzb8Ms8IOGx+gbTLZVnnuoWyLYrCznMlnxVTy/2hDllITXSTk3OkgFSpiaTUG3PqFfshJc2YV1j7B1lcdTNHmYmG5Sd21YEQhYTepF3aZ84ChGA54nVi55xjIPM7CfCJBo0+boHaTxDrDfQoYJnB+oqELx4JxChnGiQ=
---







# LLM Chat App（Flutter · M0 对话闭环 + P1 主动消息 + P1 局域网同步 + 体验优化）

一个 Flutter 风格的、类似 Chatbox 的第三方 LLM 对话软件：可导入任意 OpenAI 兼容 API，界面模仿微信，支持 LLM 主动发消息（P1），并支持基于局域网的手机/电脑双端同步（P1，电脑作为本地服务器集中存储聊天记录）。

本仓库当前为 **M0 里程碑（对话闭环）+ P1 主动消息 + P1 局域网同步**：已完成「发送消息 → SSE 流式回复 → Markdown 渲染」、「定时任务 → LLM 主动生成 → 写入会话 → 本地通知」与「手机/电脑双端增量同步（电脑端 SQLite 为权威源，WebSocket 实时推送）」；剩余待办见 [TODO.md](./TODO.md)。完整需求见项目上一级目录的 [llm_chat_app_prd.md](../llm_chat_app_prd.md)。

---

## 一、环境要求（零命令行经验也请按顺序做）

| 项目 | 要求 |
| --- | --- |
| 操作系统 | macOS / Windows / Linux（桌面开发）；iOS / Android（移动开发） |
| Flutter SDK | 3.x（本工程要求 Dart SDK >= 3.3） |
| 代码编辑器 | 推荐 VS Code + Flutter 插件，或 Android Studio |

> 本机没有装 Flutter 时，先执行下面「第 0 步」。

### 第 0 步：安装 Flutter SDK（只需一次）

1. 打开浏览器访问 Flutter 官网 <https://docs.flutter.dev/get-started/install>，按你的系统下载 SDK 压缩包。
2. 解压到一个**不含中文和空格**的目录，例如 macOS：`~/development/flutter`；Windows：`C:\src\flutter`。
3. 把 Flutter 的 `bin` 目录加入系统 PATH（官网各系统有图文教程；macOS/Linux 编辑 `~/.zshrc` 或 `~/.bashrc`，Windows 在「系统环境变量」里加）。
4. 终端执行 `flutter doctor`，按提示安装缺失的 Xcode / Android Studio / Visual Studio 组件，直到看到 `Flutter` 一行是绿色的勾。
5. 执行 `flutter --version`，出现版本号即安装成功。

### 第 1 步：补齐各平台目录（重要）

本仓库为了精简，只提交了 `lib/` 代码与工程配置，**没有包含** `android/ ios/ macos/ windows/ linux/ web/` 平台目录。请在项目根目录打开终端执行：

```bash
flutter create .
```

该命令**不会覆盖**你已经写好的 `lib/` 和 `pubspec.yaml`，只会补出各平台的原生工程目录。

### 第 2 步：安装依赖

在项目根目录执行：

```bash
flutter pub get
```

看到 `Got dependencies` 即成功。如果失败，请看文末「常见报错处理」。

> **重要**：本工程后续若新增依赖（如 `pubspec.yaml` 中新增包），需要**重新执行 `flutter pub get`**。本 P1 已新增 `flutter_local_notifications`，拉取代码后请务必先跑一次 `flutter pub get`。

### 第 3 步：运行

```bash
# macOS 桌面
flutter run -d macos

# Windows 桌面
flutter run -d windows

# Linux 桌面
flutter run -d linux

# Android 手机/模拟器
flutter run -d <设备id>

# iOS 模拟器（仅 macOS）
flutter run -d <模拟器id>
```

首次运行桌面端会弹权限请求：**macOS 请允许「网络」与「文件访问」**；若使用 API Key 加密存储，macOS 需要给工程开启 Keychain Sharing（见「常见报错处理」第 5 条）。

### 通知权限配置（P1 主动消息）

- **macOS**：首次启动会弹「通知」授权请求，请点**允许**，否则主动消息完成/失败不会弹系统通知（聊天内仍会正常写入）。macOS 本地通知**无需额外 entitlement**，沙盒应用由系统弹窗管理权限。
- **iOS**：同上，首次启动弹通知授权；若拒绝可在「系统设置 → 通知 → LLM Chat App」中重新开启。
- **Android**：Android 13+ 需要「通知」运行时权限（首次启动自动请求）；请在系统设置允许 LLM Chat App 发送通知。通知渠道名为「主动消息」。
- **静默时段**：任务可设置静默时段（HH:mm，支持跨午夜如 23:00-06:00）；静默时段内不发送通知，「仅通知」任务跳过本次执行并重新排下一次，聊天类任务仍正常写入会话。

### 依赖版本说明（无完整 Xcode 也可编译 macOS）

为兼容未安装完整 Xcode（仅 CommandLineTools）的构建环境，`pubspec.yaml` 中通过 `dependency_overrides` 固定了：

| 包 | 固定版本 | 原因 |
| --- | --- | --- |
| `flutter_local_notifications` | ^16.3.2 | 17.x 引入 `objective_c` native assets，需完整 Xcode |
| `path_provider_foundation` | 2.4.1 | 2.5+ 引入 `objective_c` native assets |
| `sqlite3` | 3.5.2 | 3.x 默认经 hook 从 GitHub 下载预编译库；本项目通过 `hooks: user_defines.sqlite3.source = system` 改用操作系统自带 SQLite，规避离线/内网环境下构建期下载失败 |

若你的环境已安装完整 Xcode，可移除这些固定并升级到最新版。

---

## 二、当前已实现（M0 对话闭环 + P1 主动消息 + P1 局域网同步）

**M0 对话闭环：**

- 三栏导航骨架：会话列表（左） / 聊天（中） / 设置（右），窄屏自动切换为底部 Tab。
- **LLM 客户端（`lib/services/llm_client.dart`）**：OpenAI 兼容 `/chat/completions` SSE 流式调用（dio `ResponseType.stream`，解析 `data:` 行与 `[DONE]`）；支持取消/停止生成（CancelToken）；错误分类中文提示（网络/超时、API Key 无效、模型不存在、限流、服务端错误、数据格式异常）；`temperature` / `max_tokens` / `top_p` 参数透传。
- **聊天页对话闭环（`lib/presentation/chat/chat_page.dart`）**：发送用户消息 → 即时落库并显示 → 调 LLM 流式请求 → 助手气泡边流边更新（`flutter_markdown` 渲染，代码块经 `flutter_highlight` 高亮、识别语言标签、深浅色自适应）→ 完成/失败/停止三态落库；生成中显示停止按钮，失败气泡可一键重试。
- **会话联动**：新会话首次发消息自动创建会话；发送后会话列表刷新最后消息摘要（去 Markdown 标记、截断 40 字）与时间。
- **参数来源**：从 settings 表读取全局默认（temperature=0.7 / max_tokens=2048 / top_p=1.0 / system_prompt），会话级字段覆盖全局；设置页可编辑默认参数。
- **API 选择**：聊天页顶栏显示当前 API 名称与模型名；未配置 API 时给出引导（窄屏切设置 Tab / 宽屏直接打开添加 API 页）。
- API 配置管理：数据模型 + 添加/编辑/删除页面 + `flutter_secure_storage` 加密存储接口封装。
- 本地数据层：SQLite 建表（`api_configs` / `conversations` / `messages` / `active_tasks` / `settings` / `prompt_templates`，按 PRD 6.1 建表 SQL）与基础 CRUD 封装。
- 本地服务器骨架：Dart shelf 服务启动器（端口探测、局域网 IPv4 地址获取与展示），`/health` 健康检查可用；同步/配对逻辑为 `TODO`。
- Riverpod 状态管理：按功能拆分 Provider 文件。
- 中文 README 与 TODO 清单。

**P1 主动消息（LLM 主动发消息，方案 A：本地定时器 + 本地通知）：**

- **主动消息管理页（`lib/presentation/active_tasks/`）**：从设置页「主动消息」进入；支持创建/编辑/删除/启停定时任务。任务字段：名称、触发时刻、重复频率（一次性 / 每天 / 每周指定星期 / 每 N 小时）、prompt 内容、关联 API 配置（默认「自动选择」= 启用配置优先）、目标会话（可选，为空则自动新建会话）。
- **调度器（`lib/services/active_task_scheduler.dart`）**：应用运行期间每 30 秒 Tick，按绝对时间比较天然覆盖跨午夜；到点调用 LLM 非流式生成（超时 60 秒），内容以**助手角色**写入目标会话（不存在则自动新建，标题=任务名），随后刷新会话列表与任务列表；失败顺延 10 分钟重试、最多 2 次，带速率保护（执行间隔不小于任务周期 50%）。
- **启动补跑（PRD 5.4）**：应用启动时扫描错过的任务（如关机错过），补跑**最近一次**（补跑后直接从当前时间排下一次，避免堆积）。
- **本地通知（`lib/services/local_notifications_service.dart`）**：接入 `flutter_local_notifications`；生成完成/失败均发本地通知（静默时段内抑制），点击通知跳转对应会话（三栏选中 + 窄屏切聊天 Tab）。
- **时区**：全部基于系统本地时间，夏令时由 Dart `DateTime` 构造自动处理，调度不依赖网络。
- **测试**：`test/widget_test.dart` 覆盖 ActiveTask / 调度规则序列化往返与 `computeNextRunAt`。

**P1 局域网同步（手机/电脑双端同步，电脑=服务器权威源）：**

- **服务器端（`lib/services/local_server/local_server_service.dart`）**：应用启动按设置自动拉起本地服务器（端口探测 8787 起顺延），绑定 `0.0.0.0` 仅局域网可访问；接口：`/health`（保留）、`/v1/info`（服务器信息）、`/v1/pair`（6 位配对码 + 防猜锁定：连续错误 N 次锁定 5 分钟，锁定期内正确码也拒绝；配对成功写入 `devices` 白名单并下发设备 token）、`/v1/sync`（增量同步，基于各会话 `server_id` 游标返回增量消息与最新游标）、`/v1/messages`（手机端批量上传：幂等过滤 + 冲突裁决 + 分配 `server_id`）、`/v1/ws`（WebSocket 实时推送新消息/主动消息）。
- **消息权威源与迁移（`app_database.dart` version=3）**：新增 `devices`（白名单设备）与 `sync_cursors`（每设备每会话同步游标）表；`messages` 追加 `device_id` / `server_id` / `updated_at` 字段；version=3 为 `active_tasks` 追加 `quiet_start` / `quiet_end` 字段，并将旧 `app_internal` 投递枚举归一化为 `chat`。电脑端 SQLite 为权威，双端各自本地缓存。
- **冲突裁决（`lib/services/local_server/sync_conflict.dart`）**：时间戳新的胜 → 设备优先级（电脑 > 手机）→ `server_id` 大者胜；上传消息按「客户端时间戳 + 设备优先级」排序后插入，`server_id` 即权威顺序。
- **客户端同步引擎（`lib/services/sync/sync_engine.dart`）**：前台 WebSocket 实时 + 30 秒轮询兜底；增量拉取落本地缓存；离线消息写入本地待上传队列，重连后补发；断线自动重连；连接/同步状态回调供 UI 展示。
- **连接配置页（`lib/presentation/sync/sync_setup_page.dart`）**：输入电脑局域网 IP / 端口 / 6 位配对码完成配对，展示连接状态；设置页「消息同步 / 配对」入口。
- **服务器管理页（`lib/presentation/sync/local_server_page.dart`）**：设置页进入，显示运行状态、端口、局域网 IP（多网卡列表）、二维码占位、配对码展示/复制/刷新、已配对设备列表（可移除）。
- **自动启动与状态**：应用启动时按 `auto_start` 设置自动拉起服务器，按 `sync_enabled` 自动恢复同步引擎（`home_page.dart`）；设置页展示已配对设备数、连接状态、最后同步时间。
- **测试**：`test/sync_test.dart` 覆盖 PairGuard 防猜锁定 / SyncConflict 裁决 / SyncJson 往返（analyze 0 issue、test 16/16 通过）。

### 局域网同步使用说明

1. **电脑端**：启动应用 → 设置 → 局域网同步 → 本地服务器，点击「启动服务器」（或保持「自动启动」开启）。记录页面展示的**局域网 IP、端口、6 位配对码**。
2. **手机端**：手机与电脑连接**同一 Wi-Fi** → 设置 → 消息同步 / 配对 → 输入电脑 IP、端口与配对码，点「配对」。配对成功后自动开始同步（WebSocket 实时 + 轮询兜底）。
3. **同步方向**：双端均可发送消息；电脑端为权威源集中存储，手机端离线时消息进入待上传队列，重连后按 `server_id` 游标增量补拉/补发。
4. **解除配对**：手机端可在连接配置页「解除配对」；电脑端可在服务器管理页移除已配对设备。

## 三、工程结构

```
lib/
├── main.dart                     # 入口：初始化 SQLite/Hive/安全存储
├── app.dart                      # MaterialApp + 主题
├── core/                         # 主题、常量
├── domain/
│   ├── models/                   # ApiConfig / Conversation / Message / ActiveTask / SyncDevice / SyncCursor
│   └── repositories/             # 仓储接口
├── data/
│   ├── database/app_database.dart# 建表/迁移（version=2：devices/sync_cursors + messages 同步字段）
│   ├── repositories/             # SQLite 实现
│   └── secure_storage/           # API Key 加密存储
├── application/providers/        # Riverpod Provider（含 local_server / sync）
├── presentation/
│   ├── home_page.dart            # 三栏导航容器（启动自动拉起服务器/同步引擎）
│   ├── session_list/             # 会话列表页
│   ├── chat/                     # 聊天页
│   ├── settings/                 # 设置页
│   ├── api_config/               # API 配置编辑页
│   ├── active_tasks/             # 主动消息管理页（P1）
│   └── sync/                     # 局域网同步：连接配置页 / 服务器管理页（P1）
└── services/
    ├── llm_client.dart           # LLM 调用（OpenAI 兼容 SSE 流式）
    ├── local_server/             # 局域网本地服务器（pair/sync/ws/防猜/冲突裁决）
    └── sync/                     # 客户端同步引擎 + 同步 JSON 共用模块
```

## 四、常见报错处理

| 报错 / 现象 | 原因与解决 |
| --- | --- |
| `command not found: flutter` | PATH 没配好，回到「第 0 步」第 3 条，重新打开终端再试。 |
| `Waiting for another flutter command to release the startup lock` | 上一次 flutter 命令没结束。执行 `flutter pub get` 完成后等几秒再试，或删掉 `bin/cache/lockfile`。 |
| `Because llm_chat_app depends on xxx which depends on yyy` | 依赖版本冲突。先 `flutter clean`，再 `flutter pub get`；仍失败就把报错贴给开发者调整 `pubspec.yaml` 版本。 |
| `Undefined name 'xxx'` / 编译报错 | 代码与 Flutter 版本不匹配。本骨架面向 Flutter 3.x，升级 Flutter 后重新 `flutter pub get`。 |
| macOS 运行时报 Keychain 错误（`-34018` 等） | 工程未开启 Keychain Sharing：在 Xcode 中打开 `macos/Runner/DebugProfile.entitlements` 与 `Release.entitlements`，添加 `com.apple.security.application-groups` 并填入你的应用组 ID；或添加 Keychain 相关 capability。 |
| Windows 运行时报 `Failed to load dynamic library 'sqlite3.dll'` | 桌面端 SQLite 走 FFI：把 `sqlite3.dll` 放到可执行文件旁，或安装 `sqlite3`（推荐 `choco install sqlite` 后用其 dll）。 |
| 安卓构建报 `SDK location not found` | Android Studio 未配置 SDK，或 `android/local.properties` 中 `sdk.dir` 路径不对。 |
| 真机运行总是「未连接设备」 | 开启开发者模式/USB 调试，执行 `flutter devices` 确认设备 id 后 `flutter run -d <id>`。 |

## 五、数据与安全说明

- API Key 只存系统安全存储（macOS Keychain / Windows Credential Manager / Android Keystore / iOS Keychain），数据库仅保存引用键 `api_key:<id>`，不落明文（PRD 6.2）。
- 会话/消息存本地 SQLite；P1 起已支持局域网双端同步，电脑端作为服务器权威源（PRD 第 7 章）：配对码 + 设备白名单 + token 校验，仅局域网（`0.0.0.0`）可访问。
- 生产使用前请确认 `base_url` 走 HTTPS，并做好导出数据脱敏。
*（内容由AI生成，仅供参考）*
*（内容由AI生成，仅供参考）*
*（内容由AI生成，仅供参考）*
*（内容由AI生成，仅供参考）*
