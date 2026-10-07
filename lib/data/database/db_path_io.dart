import 'package:path_provider/path_provider.dart';

/// IO 平台：数据库文件存放于应用支持目录。
Future<String> resolveDatabasePath() async {
  final dir = await getApplicationSupportDirectory();
  return '${dir.path}/llm_chat_app.db';
}
