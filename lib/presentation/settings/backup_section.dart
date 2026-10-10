import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/active_tasks_provider.dart';
import '../../application/providers/api_configs_provider.dart';
import '../../application/providers/conversations_provider.dart';
import '../../application/providers/database_provider.dart';
import '../../application/providers/prompt_templates_provider.dart';
import '../../application/providers/settings_provider.dart';
import '../../data/database/app_database.dart';
import '../../services/backup/backup_file.dart';
import '../../services/backup/backup_models.dart';
import '../../services/backup/backup_service.dart';

/// 设置页「数据备份」分区（v1.2.14）。
///
/// - 导出备份：生成 .talkroom-backup.json（不含 API Key 真身与同步凭据）；
/// - 导入备份：自动识别本应用备份 JSON 或 Chatbox 备份 zip，
///   解析后展示摘要确认，事务性写入并汇报结果。
class BackupSection extends ConsumerWidget {
  const BackupSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        const Divider(),
        _sectionHeader(context, '数据备份'),
        ListTile(
          leading: const Icon(Icons.file_upload_outlined),
          title: const Text('导出备份'),
          subtitle: const Text(
            '将会话、消息、模型配置、Prompt 模板、全局设置与主动任务导出为备份文件（不含 API Key 与同步凭据）',
          ),
          onTap: () => _exportBackup(context, ref),
        ),
        ListTile(
          leading: const Icon(Icons.file_download_outlined),
          title: const Text('导入备份'),
          subtitle: const Text(
            '支持导入本应用备份（.talkroom-backup.json）或 Chatbox 备份（.zip）',
          ),
          onTap: () => _importBackup(context, ref),
        ),
      ],
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }

  // ---------------------------------------------------------------
  // 导出
  // ---------------------------------------------------------------

  Future<void> _exportBackup(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final db = ref.read(appDatabaseProvider);
      final jsonMap = await BackupService.buildBackupJson(
        settingsRepository: db.settingsRepository,
        apiConfigRepository: db.apiConfigRepository,
        conversationRepository: db.conversationRepository,
        messageRepository: db.messageRepository,
        promptTemplateRepository: db.promptTemplateRepository,
        activeTaskRepository: db.activeTaskRepository,
      );
      final jsonText = const JsonEncoder.withIndent('  ').convert(jsonMap);
      final suggested =
          'llm_chat_backup_${DateTime.now().millisecondsSinceEpoch}$kBackupFileSuffix';
      final path = await BackupFileIO.exportBackup(jsonText, suggestedName: suggested);
      if (path == null) return; // 用户取消保存
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('备份已导出：$path')));
    } catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('导出备份失败：$e')));
    }
  }

  // ---------------------------------------------------------------
  // 导入
  // ---------------------------------------------------------------

  Future<void> _importBackup(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    Uint8List bytes;
    try {
      final picked = await BackupFileIO.pickBackupFile();
      if (picked == null) return; // 用户取消
      bytes = picked;
    } catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('选择备份文件失败：$e')));
      return;
    }

    try {
      final type = BackupService.detectBackupType(bytes);
      final db = ref.read(appDatabaseProvider);
      switch (type) {
        case BackupFileType.talkroom:
          final backup = BackupService.parseBackupJson(
            BackupService.decodeUtf8(bytes),
          );
          if (!context.mounted) return;
          final confirmed = await _confirmTalkroom(context, ref, backup);
          if (confirmed != true || !context.mounted) return;
          await _runImport(context, ref, db, backup, isChatbox: false);
        case BackupFileType.chatboxZip:
          final chatbox = BackupService.parseChatboxZip(bytes);
          if (chatbox.sessions.isEmpty) {
            messenger
              ..hideCurrentSnackBar()
              ..showSnackBar(const SnackBar(content: Text('备份中未找到会话数据')));
            return;
          }
          final localConfigs = ref.read(apiConfigsProvider);
          final mapped = BackupService.mapChatboxToBackup(chatbox, localConfigs);
          final attachmentsSkipped = _countChatboxFiles(chatbox);
          if (!context.mounted) return;
          final confirmed = await _confirmChatbox(
            context,
            chatbox,
            mapped,
            attachmentsSkipped,
          );
          if (confirmed != true || !context.mounted) return;
          await _runImport(context, ref, db, mapped,
              isChatbox: true, attachmentsSkipped: attachmentsSkipped);
        case BackupFileType.unknown:
          messenger
            ..hideCurrentSnackBar()
            ..showSnackBar(const SnackBar(
              content: Text('无法识别的备份文件：请选择本应用备份或 Chatbox 备份'),
            ));
      }
    } catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('解析备份失败：$e')));
    }
  }

  static int _countChatboxFiles(ChatboxZip chatbox) {
    var total = 0;
    for (final s in chatbox.sessions) {
      for (final m in s.messages) {
        total += m.files.length;
      }
    }
    return total;
  }

  Future<bool?> _confirmTalkroom(
    BuildContext context,
    WidgetRef ref,
    BackupData backup,
  ) {
    final messageCount = backup.conversations
        .fold<int>(0, (sum, c) => sum + c.messages.length);
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导入备份'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('识别为 LLM Chat 备份（schema v${backup.schemaVersion}）'),
              const SizedBox(height: 12),
              _statRow('会话', backup.conversations.length),
              _statRow('消息', messageCount),
              _statRow('模型配置', backup.apiConfigs.length),
              _statRow('Prompt 模板', backup.promptTemplates.length),
              _statRow('全局设置', backup.settings.length),
              _statRow('主动任务', backup.activeTasks.length),
              const SizedBox(height: 12),
              const Text(
                '导入不会删除现有数据；同名模型配置 / 模板 / 会话将自动跳过。'
                '导入的模型配置不含 API Key，需在「服务商管理」中手动重填。',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认导入'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _confirmChatbox(
    BuildContext context,
    ChatboxZip chatbox,
    BackupData mapped,
    int attachmentsSkipped,
  ) {
    final providerNames = chatbox.providers.toList()..sort();
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导入 Chatbox 备份'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('识别为 Chatbox 备份：${chatbox.sessions.length} 个会话，'
                  '${chatbox.messagesCount} 条消息'),
              if (providerNames.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('涉及服务商：${providerNames.join('、')}'),
              ],
              if (attachmentsSkipped > 0) ...[
                const SizedBox(height: 8),
                Text(
                  '会话中包含 $attachmentsSkipped 个文件引用，'
                  '备份未含图片二进制，导入时将跳过附件内容。',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
              const SizedBox(height: 8),
              const Text(
                '会话将映射到本地服务商配置（未匹配到相同服务商时使用默认配置），'
                '映射详情见导入报告。导入不会删除现有数据。',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认导入'),
          ),
        ],
      ),
    );
  }

  Widget _statRow(String label, int value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text('$value', style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Future<void> _runImport(
    BuildContext context,
    WidgetRef ref,
    AppDatabase db,
    BackupData backup, {
    required bool isChatbox,
    int attachmentsSkipped = 0,
  }) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    // 导入期间显示阻塞式进度
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('正在导入…'),
              ],
            ),
          ),
        ),
      ),
    );

    ImportReport report;
    try {
      report = await BackupService.importBackup(
        db,
        backup,
        isChatbox: isChatbox,
      );
      if (attachmentsSkipped > 0) {
        report.attachmentsSkipped = attachmentsSkipped;
      }
      // 刷新各状态源
      await Future.wait([
        ref.read(apiConfigsProvider.notifier).load(),
        ref.read(settingsProvider.notifier).load(),
        ref.read(conversationsProvider.notifier).load(),
        ref.read(promptTemplatesProvider.notifier).load(),
        ref.read(activeTasksProvider.notifier).load(),
      ]);
    } catch (e) {
      navigator.pop(); // 关闭进度框
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('导入失败（已回滚）：$e')));
      return;
    }

    if (navigator.mounted) navigator.pop(); // 关闭进度框
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导入完成'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(report.summarize()),
              const SizedBox(height: 8),
              Text(
                '会话去重跳过：${report.conversationsSkipped} · '
                '模型配置跳过：${report.apiConfigsSkipped} · '
                '模板跳过：${report.promptTemplatesSkipped}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              if (report.notes.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Divider(height: 1),
                for (final note in report.notes)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text(
                      '· $note',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.orange,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('完成'),
          ),
        ],
      ),
    );
  }
}
