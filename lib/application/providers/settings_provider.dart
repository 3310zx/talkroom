import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/repositories/settings_repository.dart';
import 'database_provider.dart';

/// 全局设置状态（PRD 2.2：settingsProvider，key-value 快照）。
final settingsProvider =
    StateNotifierProvider<SettingsNotifier, Map<String, String>>(
  (ref) => SettingsNotifier(ref.watch(appDatabaseProvider).settingsRepository),
);

class SettingsNotifier extends StateNotifier<Map<String, String>> {
  SettingsNotifier(this._repository) : super(const {});

  final SettingsRepository _repository;

  Future<void> load() async {
    state = await _repository.getAll();
  }

  Future<void> set(String key, String value) async {
    await _repository.setValue(key, value);
    state = {...state, key: value};
  }

  String? get(String key) => state[key];
}
