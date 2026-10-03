---
AIGC:
    Label: "1"
    ContentProducer: 001191440300708461136T1XGW3
    ProduceID: c246678a38a94bf2e839f4ad8865f533_01c0211dbf0111f197eb525400393706
    ReservedCode1: hHJSzKqPr5Ix6szOPYsok1wDo6ICqpYuRaJ/PsB873BWs/q6dKOFI07UDnvOkXhk41GTZSyRjlLN5IsmFQFM9pJVg3KvEZKjfkoNTtB+JMz3W2d6BUmcpz98Shnd017o1jnrbkZKIT6zct8T33k0fV0D7z0gk8PGdLH18Cfv4KWi7208QC0KpdCVpW8=
    ContentPropagator: 001191440300708461136T1XGW3
    PropagateID: c246678a38a94bf2e839f4ad8865f533_01c0211dbf0111f197eb525400393706
    ReservedCode2: hHJSzKqPr5Ix6szOPYsok1wDo6ICqpYuRaJ/PsB873BWs/q6dKOFI07UDnvOkXhk41GTZSyRjlLN5IsmFQFM9pJVg3KvEZKjfkoNTtB+JMz3W2d6BUmcpz98Shnd017o1jnrbkZKIT6zct8T33k0fV0D7z0gk8PGdLH18Cfv4KWi7208QC0KpdCVpW8=
---







# TODO 清单（M0 对话闭环 + P1 主动消息 + P1 局域网同步完成后的剩余项）

> 按 PRD 里程碑规划。标 `TODO(code)` 的项同时已在代码中以 `// TODO` 注释标注。

## M0 完成态说明
- [x] 工程基础（pubspec / analysis_options / main 入口 / 三栏导航）
- [x] API 配置管理骨架（模型 / 页面 / 安全存储封装）
- [x] SQLite 建表与 CRUD 封装（PRD 6.1 六张表 + active_tasks）
- [x] 本地服务器最小可启动实现（端口探测 / 局域网 IP 展示 / `/health`）
- [x] Riverpod Provider 骨架
- [x] 中文 README

## M0 对话闭环（已完成）
- [x] LLM 客户端：OpenAI 兼容 `/chat/completions` 流式（SSE）调用（`lib/services/llm_client.dart`）
- [x] 聊天页消息渲染：接入 `flutter_markdown`（`lib/presentation/widgets/message_bubble.dart`）
- [x] 聊天页真实发送流程：落库 → 流式 → 边流边更新 → 完成/失败/停止三态落库（`chat_page.dart`）
- [x] 会话联动：新会话首次发消息自动创建会话；会话列表刷新最后消息/时间
- [x] 设置页参数联动：temperature / max_tokens / top_p / system_prompt 保存与注入会话
- [x] 错误兜底 UI：网络失败重试、API Key 失效提示（错误气泡 + 重试按钮）
- [x] 未添加 API 引导跳转（聊天页空态；窄屏切设置 Tab / 宽屏打开添加 API 页）

## M0 内待完成（剩余占位）
- [x] 代码块高亮：`flutter_highlight ^0.7.0` 引入；`message_bubble.dart` 用 `HighlightView` 渲染 Markdown 代码块（识别 language 标签，深/浅色自适应，未知语言回退 plaintext）
- [ ] 会话标题重命名（`session_list_page.dart` 菜单已留占位）
- [ ] 会话列表页空态引导卡（`session_list_page.dart` 已留占位）

## P1（主动消息）——本轮已完成 ✅
- [x] `active_tasks` 表 + ActiveTask 模型与仓储（schedule_data 含 frequency/time/weekdays/hourly_interval，computeNextRunAt）
- [x] 主动消息管理页（`active_tasks_page.dart`）与编辑页（`active_task_edit_page.dart`）：创建/编辑/删除/启停，从设置页进入
- [x] 调度器（`active_task_scheduler.dart`）：应用运行期间 Timer Tick 30s，绝对时间比较覆盖跨午夜；到点调 llm_client 非流式生成 → 助手角色写入目标会话（缺失自动新建）→ 刷新列表；失败顺延重试 ≤2 次；速率保护
- [x] 启动补跑：扫描 missed（next_run_at < now）任务补跑最近一次，重新排下一次避免堆积（`HomePage.initState` 启动）
- [x] 本地通知：`flutter_local_notifications ^16.3.2`，生成完成/失败均通知，点击跳转对应会话（`local_notifications_service.dart`；main.dart 初始化并注入跳转处理器）
- [x] 时区：全部系统本地时间，夏令时由 Dart DateTime 构造处理，不依赖网络
- [x] 更新 README（功能说明 + 通知权限配置 + 依赖版本说明）与 TODO 本清单
- [x] `delivery=chat/notification/both` 投递通道开关（默认 both，编辑页三选一；PRD 5.1 完成）
- [x] 静默时段（quiet_start / quiet_end）字段与过滤（HH:mm，支持跨午夜；静默内抑制通知、「仅通知」任务跳过本次并重排下一次；PRD 5.2 完成）
- [x] 数据库迁移 version=2 → 3：`active_tasks` 追加 `quiet_start` / `quiet_end`，旧 `app_internal` 归一化为 `chat`
- [x] 单元测试：`test/active_task_test.dart` 覆盖静默时段判断（含跨午夜）与投递通道行为
- [ ] `workmanager` / `android_alarm_manager_plus` 后台保活（PRD 5.1 方案 B，后续项）

## P1（局域网同步，电脑=服务器权威源）——本轮已完成 ✅
- [x] 数据库迁移：`devices` / `sync_cursors` 表；`messages` 追加 `device_id` / `server_id` / `updated_at` 字段（`app_database.dart` version=2）
- [x] 服务端核心（`local_server_service.dart` 重写）：绑定 `0.0.0.0`（仅局域网可访问）；`/health` 保留；`/v1/info` 返回服务器信息；`/v1/pair` 6 位配对码 + 防猜锁定（连续错误锁定、锁定期输入正确也拒绝）；配对成功写入 `devices` 白名单并下发设备 token
- [x] 增量同步：`/v1/sync` 基于各会话 `server_id` 游标返回增量消息与最新游标；`/v1/messages` 接收手机端批量上传（幂等过滤 + 冲突裁决 + 分配 `server_id`），返回客户端时间戳→`server_id` 映射
- [x] 冲突裁决（`sync_conflict.dart`）：时间戳新的胜 → 设备优先级（电脑 > 手机）→ `server_id` 大者胜；上传按「客户端时间戳 + 设备优先级」排序后插入，`server_id` 即权威顺序
- [x] 实时推送：`/v1/ws` WebSocket 广播新消息 / 主动消息；电脑端本地消息由 30s 周期兜底定时器固化 `server_id` 并广播（不依赖 UI 操作）
- [x] 客户端同步引擎（`sync_engine.dart`）：配对、增量拉取落本地缓存、离线待上传队列补发、前台 WebSocket 实时 + 30s 轮询兜底、断线重连、连接/同步状态回调
- [x] 连接配置页（`sync_setup_page.dart`）：输入电脑局域网 IP / 端口 / 6 位配对码完成配对，展示连接状态
- [x] 服务器管理页（`local_server_page.dart`）：运行状态、端口、局域网 IP（多网卡列表）、二维码占位、配对码展示/复制/刷新、已配对设备列表（可移除）
- [x] 设置页「局域网同步」入口与状态展示（已配对设备数、连接状态、最后同步时间）
- [x] 自动启动：应用启动按 `auto_start` 设置自动拉起服务器（端口探测 8787 起顺延），按 `sync_enabled` 自动恢复同步引擎（`home_page.dart`）
- [x] 同步 JSON 共用模块（`sync_json.dart`）与白名单设备模型（`sync_device.dart`）
- [x] 单元测试：`test/sync_test.dart` 覆盖 PairGuard 防猜锁定 / SyncConflict 裁决 / SyncJson 往返（analyze 0 issue、test 16/16 通过）
- [x] 更新 README（双端同步使用说明）与 TODO 本清单
- [ ] 服务器访问控制增强：WebSocket 通道鉴权、HTTPS 建议、异常设备熔断（PRD 7.5 后续项；当前 `/v1/sync` `/v1/messages` 已走白名单 token 校验）

## P2 / 远期
- [ ] 多语言（i18n）、深色模式细节打磨
- [ ] 导入/导出备份（JSON / SQLite 文件复制，PRD 6.1.3）
- [ ] 数据统计面板、提示词市场
- [ ] P2 端到端加密同步（PRD 7.6，非 M0/M1 范围）
*（内容由AI生成，仅供参考）*
*（内容由AI生成，仅供参考）*
*（内容由AI生成，仅供参考）*
*（内容由AI生成，仅供参考）*
