import 'package:llm_chat_app/data/preset_providers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('presetProviders 数据完整性', () {
    test('共 9 个预设服务商，且名称唯一', () {
      expect(presetProviders.length, 9);
      final names = presetProviders.map((p) => p.name).toSet();
      expect(names.length, presetProviders.length);
    });

    test('每个预设都有合法 baseUrl 与非空模型列表', () {
      for (final p in presetProviders) {
        expect(
          p.baseUrl.startsWith('http://') || p.baseUrl.startsWith('https://'),
          isTrue,
          reason: '${p.name} baseUrl 应以 http(s):// 开头',
        );
        expect(p.baseUrl, isNotEmpty);
        expect(p.modelIds, isNotEmpty, reason: '${p.name} 应内置默认模型');
        expect(p.brandColorArgb, isNot(0), reason: '${p.name} 应有品牌色');
      }
    });

    test('OpenAI 预设包含关键模型且需要 Key', () {
      final openai = presetProviderByName('OpenAI');
      expect(openai, isNotNull);
      expect(openai!.baseUrl, 'https://api.openai.com/v1');
      expect(openai.modelIds, containsAll(['gpt-4o', 'gpt-4o-mini']));
      expect(openai.requiresApiKey, isTrue);
    });

    test('Ollama 本地预设免密钥且指向本机', () {
      final ollama = presetProviderByName('Ollama 本地');
      expect(ollama, isNotNull);
      expect(ollama!.baseUrl, 'http://localhost:11434/v1');
      expect(ollama.requiresApiKey, isFalse);
    });

    test('预设清单包含全部 9 家指定服务商', () {
      const expected = [
        'OpenAI',
        'DeepSeek',
        'SiliconFlow',
        'Kimi',
        '智谱 GLM',
        '通义千问',
        'Ollama 本地',
        'Groq',
        '火山方舟豆包',
      ];
      final names = presetProviders.map((p) => p.name).toList();
      expect(names, containsAll(expected));
    });
  });
}
