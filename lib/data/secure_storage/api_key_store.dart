import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// API Key 安全存储封装（PRD 6.2）。
///
/// 原则：明文不落盘。数据库 `api_configs.api_key_ref` 只保存引用键
/// （如 `api_key:<id>`），真正密钥存系统安全存储：
/// macOS Keychain / Windows Credential Manager / Android Keystore / iOS Keychain。
class ApiKeyStore {
  ApiKeyStore._();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  /// 初始化标记键（不敏感，仅用于验证安全存储可用性）。
  static const String _markerKey = 'store_init_marker';

  /// 平台级初始化：对 macOS Keychain / 各平台安全存储做一次可用性探测。
  ///
  /// 探测失败不抛出（不阻断启动），仅记录警告；读写路径本身不依赖本次
  /// 探测结果，Keychain 实际不可用时会由对应读写调用自然失败。
  static Future<void> initialize() async {
    try {
      await _storage.write(key: _markerKey, value: 'ok');
      final check = await _storage.read(key: _markerKey);
      if (check != 'ok') {
        debugPrint('ApiKeyStore: 安全存储初始化校验未通过');
      }
    } catch (e) {
      debugPrint('ApiKeyStore: 安全存储初始化不可用（$e），密钥读写将失败并提示用户');
    }
  }

  /// 生成引用键：`api_key:<id>`
  static String refKeyFor(int apiConfigId) => 'api_key:$apiConfigId';

  /// 生成唯一引用键（新建配置时使用）。
  ///
  /// 修复：旧实现由调用方传入 `now % 100000`（秒级取模），同一秒内保存
  /// 多个配置会得到相同 refKey 并互相覆盖 Keychain 中的密钥。新实现使用
  /// 微秒时间戳 + 随机数，保证同秒多配置互不冲突。
  static String generateRefKey() {
    final ms = DateTime.now().microsecondsSinceEpoch;
    final rand = Random().nextInt(0x7fffffff);
    return 'api_key:${ms}_$rand';
  }

  static Future<String?> read(String refKey) => _storage.read(key: refKey);

  static Future<void> write(String refKey, String value) =>
      _storage.write(key: refKey, value: value);

  static Future<void> delete(String refKey) => _storage.delete(key: refKey);
}
