import 'dart:js_interop';

/// Web 平台：在新窗口打开 URL（基于 dart:js_interop，避免 dart:html 弃用）。
@JS('window.open')
external JSAny? _windowOpen(String url, String target);

Future<void> openExternalUrl(String url) async {
  _windowOpen(url, '_blank');
}
