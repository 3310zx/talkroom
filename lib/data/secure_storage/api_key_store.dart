import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// API Key 安全存储封装（PRD 6.2）。
///
/// 原则：明文不落盘。数据库 `api_configs.api_key_ref` 只保存引用键
/// （如 `api_key:<id>`），真正密钥存系统安全存储：
/// macOS Keychain / Windows Credential Manager / Android Keystore / iOS Keychain。
class ApiKeyStore {
  ApiKeyStore._();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  /// 预留：可在此处做平台级初始化（如 macOS Keychain 参数），当前无需额外配置。
  static Future<void> initialize() async {
    // TODO(M0 完成态): 如需 macOS Keychain 自定义 service/account 可在此配置。
  }

  /// 生成引用键：`api_key:<id>`
  static String refKeyFor(int apiConfigId) => 'api_key:$apiConfigId';

  static Future<String?> read(String refKey) => _storage.read(key: refKey);

  static Future<void> write(String refKey, String value) =>
      _storage.write(key: refKey, value: value);

  static Future<void> delete(String refKey) => _storage.delete(key: refKey);
}
