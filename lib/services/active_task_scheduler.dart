import 'dart:async';

import '../../core/constants.dart';
import '../../data/secure_storage/api_key_store.dart';
import '../../domain/models/active_task.dart';
import '../../domain/models/active_task_log.dart';
import '../../domain/models/active_task_schedule.dart';
import '../../domain/models/api_config.dart';
import '../../domain/models/conversation.dart';
import '../../domain/models/message.dart';
import '../../domain/repositories/active_task_repository.dart';
import '../../domain/repositories/api_config_repository.dart';
import '../../domain/repositories/conversation_repository.dart';
import '../../domain/repositories/message_repository.dart';
import '../../domain/repositories/settings_repository.dart';
import 'llm_client.dart';
import 'local_notifications_service.dart';

/// 主动消息调度器（PRD 5.1 方案 A：本地定时器 + 本地通知）。
///
/// 职责：
/// - 应用运行期间周期性 tick（每 30 秒）检查到点任务（`next_run_at <= now`），
///   跨午夜由绝对时间比较天然覆盖；
/// - 启动时补跑：扫描错过任务（`next_run_at < now`），按 PRD 5.4 补跑最近一次
///   （避免堆积：补跑后直接从当前时间排下一次）；
/// - 到点任务调用 LLM 非流式生成（超时 60s，PRD 5.5.2），写入目标会话
///   （不存在则新建），消息以助手角色落库并刷新会话列表；
/// - 失败顺延：失败后 10 分钟重试，最多 2 次（PRD 5.5.3）；
/// - 速率保护：执行间隔不小于任务周期的 50%（PRD 5.5.4）；
/// - 投递通道（PRD 5.1）：按 `delivery` 决定是否写入目标会话（chat/both）
///   与是否发本地通知（notification/both）；
/// - 静默时段（PRD 5.2）：静默时段内统一抑制通知；`notification` 任务
///   跳过本次投递（重新排下一次，lastStatus='skipped'），`chat` / `both`
///   任务不受影响，仅不通知；支持跨午夜时段（如 23:00-06:00）；
/// - 通知：生成完成/失败均发本地通知（静默时段除外），点击可跳转对应会话。
///
/// 时区：全部基于系统本地时间（不依赖网络），夏令时由 Dart DateTime 构造处理。
class ActiveTaskScheduler {
  ActiveTaskScheduler({
    required ActiveTaskRepository activeTaskRepository,
    required ApiConfigRepository apiConfigRepository,
    required ConversationRepository conversationRepository,
    required MessageRepository messageRepository,
    required SettingsRepository settingsRepository,
    required LocalNotificationsService notifications,
    required LlmClient llmClient,
    required Future<void> Function() onTasksChanged,
    required Future<void> Function() onConversationsChanged,
  })  : _activeTaskRepository = activeTaskRepository,
        _apiConfigRepository = apiConfigRepository,
        _conversationRepository = conversationRepository,
        _messageRepository = messageRepository,
        _settingsRepository = settingsRepository,
        _notifications = notifications,
        _llmClient = llmClient,
        _onTasksChanged = onTasksChanged,
        _onConversationsChanged = onConversationsChanged;

  final ActiveTaskRepository _activeTaskRepository;
  final ApiConfigRepository _apiConfigRepository;
  final ConversationRepository _conversationRepository;
  final MessageRepository _messageRepository;
  final SettingsRepository _settingsRepository;
  final LocalNotificationsService _notifications;
  final LlmClient _llmClient;
  final Future<void> Function() _onTasksChanged;
  final Future<void> Function() _onConversationsChanged;

  Timer? _timer;
  bool _started = false;

  /// 正在执行的任务 id（防重入）。
  final Set<int> _running = {};

  /// 失败重试计数（内存态：任务失败后顺延 10 分钟，最多重试 2 次）。
  final Map<int, int> _failCounts = {};

  static const Duration _tickInterval = Duration(seconds: 30);
  static const Duration _retryDelay = Duration(minutes: 10);
  static const int _maxRetries = 2;

  void start() {
    if (_started) return;
    _started = true;
    // 先补跑（错过任务），再进入周期调度。
    unawaited(_catchUpMissed().then((_) => _scheduleTick()));
  }

  void stop() {
    _started = false;
    _timer?.cancel();
    _timer = null;
  }

  void _scheduleTick() {
    _timer?.cancel();
    _timer = Timer.periodic(_tickInterval, (_) => unawaited(tick()));
  }

  /// 周期检查：执行所有到点任务。
  Future<void> tick() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final tasks = await _activeTaskRepository.getDueTasks(now);
    for (final task in tasks) {
      await _executeIfAllowed(task);
    }
  }

  /// 启动补跑：enabled 且 next_run_at < now 的任务补执行最近一次。
  ///
  /// 补跑后 `next_run_at` 从当前时间重新计算下一次，中间错过的多个周期
  /// 不堆积（PRD 5.4「避免堆积」）。
  Future<void> _catchUpMissed() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final missed = await _activeTaskRepository.getMissedTasks(now);
    for (final task in missed) {
      await _executeWithQuietCheck(task);
    }
  }

  /// 到点任务执行前的统一守卫：防重入 + 速率保护 + 静默时段。
  Future<void> _executeIfAllowed(ActiveTask task) async {
    if (task.id == null || _running.contains(task.id)) return;
    // 速率保护（PRD 5.5.4）：距上次执行不足周期 50% 时跳过本轮。
    final lastRun = task.lastRunAt;
    if (lastRun != null) {
      final schedule = ActiveTaskSchedule.fromJson(
        task.scheduleData,
        taskType: task.taskType,
      );
      final cycle = schedule.cycleMillis();
      if (cycle > 0) {
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - lastRun < cycle ~/ 2) return;
      }
    }
    await _executeWithQuietCheck(task);
  }

  /// 静默时段守卫（PRD 5.2）：
  /// - `notification`（仅通知）任务在静默时段内**跳过本次投递**：不生成、
  ///   不通知，仅重新排下一次（lastStatus='skipped'）；
  /// - `chat` / `both` 任务不受静默时段影响（聊天通道照常写入，仅抑制通知，
  ///   由 [_runTask] 内的 shouldNotifyDuring 决策）。
  Future<void> _executeWithQuietCheck(ActiveTask task) async {
    final taskId = task.id;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (taskId == null || _running.contains(taskId)) return;
    if (task.shouldSkipRun(DateTime.now())) {
      final schedule = ActiveTaskSchedule.fromJson(
        task.scheduleData,
        taskType: task.taskType,
      );
      final nextRun = schedule.computeNextRunAt(DateTime.now());
      await _activeTaskRepository.update(task.copyWith(
        lastStatus: 'skipped',
        nextRunAt: nextRun,
      ));
      await _writeLog(taskId, nowMs, 'skipped', '静默时段内跳过本次执行');
      _failCounts.remove(taskId);
      await _notifyChanged();
      return;
    }
    await _runTask(task);
  }

  /// 执行单个任务：生成 → 落库 → 更新任务状态 → 通知。
  Future<void> _runTask(ActiveTask task) async {
    final taskId = task.id;
    if (taskId == null) return;
    if (!_running.add(taskId)) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    // 静默时段判定（chat / both 任务不受静默影响；通知统一抑制）。
    final quiet = task.inQuietPeriod(DateTime.fromMillisecondsSinceEpoch(nowMs));

    try {
      final config = await _resolveApiConfig(task);
      final apiKey = config == null
          ? null
          : await ApiKeyStore.read(config.apiKeyRef);
      if (config == null || apiKey == null || apiKey.isEmpty) {
        throw const LlmException(LlmErrorType.auth, '未配置 API 或 API Key 缺失，请先到设置页添加 API 配置');
      }
      final model = task.modelId.isNotEmpty
          ? task.modelId
          : (config.modelIds.isNotEmpty ? config.modelIds.first : '');
      if (model.isEmpty) {
        throw const LlmException(LlmErrorType.model, '当前 API 配置未填写模型，请到设置页补充');
      }

      final settings = await _settingsRepository.getAll();
      final temperature = _doubleSetting(
          settings, AppConstants.settingTemperature, AppConstants.defaultTemperature);
      final maxTokens = _intSetting(
          settings, AppConstants.settingMaxTokens, AppConstants.defaultMaxTokens);
      final topP = _doubleSetting(
          settings, AppConstants.settingTopP, AppConstants.defaultTopP);
      final systemPrompt = settings[AppConstants.settingSystemPrompt];

      final messages = _buildMessages(task, systemPrompt);
      final result = await _llmClient.chat(
        baseUrl: config.baseUrl,
        apiKey: apiKey,
        model: model,
        messages: messages,
        temperature: temperature,
        maxTokens: maxTokens,
        topP: topP,
      );

      // 投递通道（PRD 5.1）：chat / both 写入目标会话；notification 仅通知不写聊天。
      int? conversationId = task.targetConversationId;
      if (task.shouldWriteChat) {
        var conversation = await _resolveOrCreateConversation(task, config, model);
        if (conversation.id == null) {
          throw const LlmException(LlmErrorType.server, '会话创建失败，请重试');
        }
        conversationId = conversation.id!;

        // 助手消息落库。
        await _messageRepository.insert(ChatMessage(
          conversationId: conversationId,
          role: 'assistant',
          content: result.content,
          status: 'done',
          modelId: model,
          promptTokens: result.promptTokens,
          completionTokens: result.completionTokens,
          createdAt: nowMs,
        ));

        // 刷新会话摘要与时间。
        await _conversationRepository.update(conversation.copyWith(
          lastMessage: _summarize(result.content),
          updatedAt: nowMs,
        ));
      }

      // 更新任务：last_run_at / last_status / next_run_at（once 执行后自动停用）。
      final schedule =
          ActiveTaskSchedule.fromJson(task.scheduleData, taskType: task.taskType);
      final nextRun = schedule.computeNextRunAt(DateTime.now());
      var updated = task.copyWith(
        targetConversationId: conversationId,
        lastRunAt: nowMs,
        lastStatus: 'ok',
        nextRunAt: nextRun,
        enabled: task.taskType == 'once' ? false : task.enabled,
      );
      await _activeTaskRepository.update(updated);
      _failCounts.remove(taskId);

      // 完成通知（PRD 5.3 + 5.2 联动）：静默时段内统一抑制通知。
      if (task.shouldNotifyDuring(quiet)) {
        await _notifications.showActiveTaskResult(
          taskName: task.taskName,
          body: _summarize(result.content),
          conversationId: conversationId ?? -1,
        );
      }

      await _notifyChanged();
    } catch (e) {
      await _handleFailure(task, nowMs, e, quiet);
    } finally {
      _running.remove(taskId);
    }
  }

  /// 失败处理：顺延 10 分钟重试，最多 2 次；超过后按正常周期排下一次。
  Future<void> _handleFailure(
      ActiveTask task, int nowMs, Object error, bool quiet) async {
    final taskId = task.id;
    if (taskId == null) return;
    final count = (_failCounts[taskId] ?? 0) + 1;
    _failCounts[taskId] = count;

    int? nextRun;
    if (count <= _maxRetries) {
      nextRun = nowMs + _retryDelay.inMilliseconds;
    } else {
      _failCounts.remove(taskId);
      final schedule =
          ActiveTaskSchedule.fromJson(task.scheduleData, taskType: task.taskType);
      nextRun = schedule.computeNextRunAt(DateTime.now());
    }
    final message = error is LlmException
        ? error.message
        : '生成失败：$error';
    await _activeTaskRepository.update(task.copyWith(
      lastRunAt: nowMs,
      lastStatus: 'failed',
      nextRunAt: nextRun,
    ));

    if (task.shouldNotifyDuring(quiet)) {
      await _notifications.showActiveTaskResult(
        taskName: task.taskName,
        body: '任务执行失败：${_summarize(message)}',
        conversationId: task.targetConversationId ?? -1,
      );
    }
    await _notifyChanged();
  }

  /// 组装 LLM 请求消息：system（全局 + 当前时间） + user（任务 prompt）。
  List<Map<String, String>> _buildMessages(
      ActiveTask task, String? globalSystemPrompt) {
    final now = DateTime.now();
    final timeText = '当前本地时间：${now.year}年${now.month.toString().padLeft(2, '0')}月'
        '${now.day.toString().padLeft(2, '0')}日 '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}'
        '（星期${'一二三四五六日'[now.weekday - 1]}）。';
    final system = [
      if (globalSystemPrompt != null && globalSystemPrompt.trim().isNotEmpty)
        globalSystemPrompt.trim(),
      '你是一个主动消息助手。$timeText 请按下面的任务指令直接生成一条消息内容，'
          '不要附加解释或 Markdown 代码块。',
    ].join('\n\n');

    return [
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': task.prompt},
    ];
  }

  /// 解析任务关联的 API 配置：任务指定 > 启用配置 > 第一个。
  Future<ApiConfig?> _resolveApiConfig(ActiveTask task) async {
    if (task.apiConfigId != 0) {
      final byId = await _apiConfigRepository.getById(task.apiConfigId);
      if (byId != null) return byId;
    }
    final all = await _apiConfigRepository.getAll();
    for (final config in all) {
      if (config.enabled) return config;
    }
    return all.isEmpty ? null : all.first;
  }

  /// 目标会话：任务指定则读取，否则新建（标题=任务名，绑定 API/模型）。
  Future<Conversation> _resolveOrCreateConversation(
      ActiveTask task, ApiConfig config, String model) async {
    if (task.targetConversationId != null) {
      final existing =
          await _conversationRepository.getById(task.targetConversationId!);
      if (existing != null) return existing;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = await _conversationRepository.insert(Conversation(
      title: task.taskName,
      apiConfigId: config.id,
      modelId: model,
      updatedAt: now,
      createdAt: now,
    ));
    final created = await _conversationRepository.getById(id);
    if (created == null) {
      throw const LlmException(LlmErrorType.server, '会话创建失败，请重试');
    }
    return created;
  }

  Future<void> _notifyChanged() async {
    await _onTasksChanged();
    await _onConversationsChanged();
  }

  double _doubleSetting(Map<String, String> settings, String key, double fallback) {
    final v = settings[key];
    if (v == null) return fallback;
    return double.tryParse(v) ?? fallback;
  }

  int _intSetting(Map<String, String> settings, String key, int fallback) {
    final v = settings[key];
    if (v == null) return fallback;
    return int.tryParse(v) ?? fallback;
  }

  /// 写入任务执行日志（R16，v1.0.15）：成功 / 失败 / 跳过均留痕。
  Future<void> _writeLog(int taskId, int runAtMs, String status, String summary) async {
    try {
      await _activeTaskRepository.insertLog(ActiveTaskLog(
        taskId: taskId,
        runAt: runAtMs,
        status: status,
        summary: summary,
        createdAt: runAtMs,
      ));
    } catch (_) {
      // 日志写入失败不影响任务主流程。
    }
  }

  /// 会话列表摘要：去 Markdown 标记后的纯文本，截断 40 字。
  String _summarize(String text) {
    var plain = text
        .replaceAll(RegExp(r'```[\s\S]*?```'), ' ')
        .replaceAll(RegExp(r'`[^`]*`'), ' ')
        .replaceAll(RegExp(r'[#>*_~\[\]()!|-]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (plain.length > 40) plain = plain.substring(0, 40);
    return plain;
  }
}
