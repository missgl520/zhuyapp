// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// 竹笌对话服务（直连 Agnes API，【已废弃】）
//
// 废弃说明（2026-08-03）：
// 本服务绕过后端直连 Agnes API，记忆（RAG）功能从未生效。
// 新代码请使用 BackendService（统一走 /chat/v2，后端处理 RAG + 情绪 + 好感度）。
// 本类仅保留用于兼容旧代码，未来版本将删除。
//
// 上游：无新调用方（保留仅为兼容）。
// 下游：Agnes 开放平台 HTTP 接口、Hive 'settings'（agnesUseCN 偏好）。
//
// 关键点：直连模式下记忆（RAG）不生效，这也是本服务被废弃的根本原因。
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;

/// 【已废弃】直连 Agnes 平台的对话服务。
///
/// 新代码请改用 BackendService（统一走后端 `/chat/v2`），
/// 由后端负责 RAG 记忆、情绪识别与好感度计算。
class AgnesService {
  // 单例
  static AgnesService? _instance;

  /// 懒加载单例访问器。
  static AgnesService get instance => _instance ??= AgnesService._();

  /// 私有构造：读取上次保存的 CN/国际版偏好。
  AgnesService._() {
    // 启动时读取上次的服务器偏好（避免每次都要重新选）
    try {
      final box = Hive.box('settings');
      _useCN = box.get('agnesUseCN', defaultValue: true) as bool;
    } catch (_) {
      _useCN = true; // 默认国内版
    }
  }

  // Agnes 国际版
  static const _apiIntl = 'https://apihub.agnes-ai.com/v1/chat/completions';
  // Agnes 国内版
  // Agnes CN 2026-07-29 迁移后用 apihub.agnes-ai.cn/v1（旧 platform.agnes-ai.cn 已废弃）
  static const _apiCN = 'https://apihub.agnes-ai.cn/v1/chat/completions';

  // 当前选中的 API（由 App 在设置页控制）
  bool _useCN = true; // 默认国内版

  String? _runtimeApiKey;

  /// 运行时设置 API Key
  void setApiKey(String key) => _runtimeApiKey = key;

  /// 切换 CN/国际版
  void setUseCN(bool cn) => _useCN = cn;

  bool get useCN => _useCN;

  String get _baseUrl => _useCN ? _apiCN : _apiIntl;

  // ━━━━━━━━━━━━━━━ 同步对话 ━━━━━━━━━━━━━━━

  /// 一次返回完整回复（非流式）。
  ///
  /// [history]      历史消息，元素形如 `{'role': 'user', 'content': '...'}`。
  /// [systemPrompt] 角色设定，为空则不下发 system 消息。
  /// [saveToMemory] 直连模式下无意义，仅保持签名兼容。
  ///
  /// 非 200 响应会抛 [Exception]。
  Future<String> chat({
    required String message,
    List<Map<String, String>> history = const [],
    String? systemPrompt,
    double temperature = 0.7,
    bool saveToMemory = true, // 直连模式：忽略，由 App 本地处理
  }) async {
    final body = <String, dynamic>{
      'model': 'agnes-2.0-flash',
      'messages': _buildMessages(message, history, systemPrompt),
      'max_tokens': 2000,
      'temperature': temperature,
      'stream': false,
    };

    final response = await http.post(
      Uri.parse(_baseUrl),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${_runtimeApiKey ?? ''}',
      },
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      throw Exception('Agnes API 错误 ${response.statusCode}：${response.body}');
    }

    final data = jsonDecode(response.body);
    return data['choices'][0]['message']['content'] as String;
  }

  // ━━━━━━━━━━━━━━━ 流式对话（打字机） ━━━━━━━━━━━━━━━

  /// 流式返回（SSE）：每个 chunk 是一个字/词，可直接驱动打字机效果。
  ///
  /// 返回 `Stream<String>`；遇到 `data: [DONE]` 时自动结束。
  /// 非 200 响应会抛 [Exception]。
  Stream<String> chatStream({
    required String message,
    List<Map<String, String>> history = const [],
    String? systemPrompt,
    double temperature = 0.7,
    bool saveToMemory = true,
  }) async* {
    final body = <String, dynamic>{
      'model': 'agnes-2.0-flash',
      'messages': _buildMessages(message, history, systemPrompt),
      'max_tokens': 2000,
      'temperature': temperature,
      'stream': true,
    };

    final request = http.Request('POST', Uri.parse(_baseUrl));
    request.headers['Content-Type'] = 'application/json';
    request.headers['Authorization'] = 'Bearer ${_runtimeApiKey ?? ''}';
    request.body = jsonEncode(body);

    final streamedResponse = await http.Client().send(request);

    if (streamedResponse.statusCode != 200) {
      final body = await streamedResponse.stream.bytesToString();
      throw Exception('Agnes API 错误 ${streamedResponse.statusCode}：$body');
    }

    String buffer = '';
    await for (final chunk in streamedResponse.stream.transform(utf8.decoder)) {
      buffer += chunk;

      while (buffer.contains('\n')) {
        final lineEnd = buffer.indexOf('\n');
        String line = buffer.substring(0, lineEnd).trim();
        buffer = buffer.substring(lineEnd + 1);

        if (!line.startsWith('data: ')) continue;
        final data = line.substring(6).trim();
        if (data == '[DONE]') return;

        try {
          final json = jsonDecode(data);
          final content = json['choices']?[0]?['delta']?['content'];
          if (content != null && content.toString().isNotEmpty) {
            yield content.toString();
          }
        } catch (_) {
          // 非 JSON 行跳过
        }
      }
    }
  }

  // ━━━━━━━━━━━━━━━ 工具方法 ━━━━━━━━━━━━━━━

  /// 拼接 OpenAI 风格的 messages 数组：system + history + 当前 user 消息。
  List<Map<String, String>> _buildMessages(
    String message,
    List<Map<String, String>> history,
    String? systemPrompt,
  ) {
    final messages = <Map<String, String>>[];
    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      messages.add({'role': 'system', 'content': systemPrompt});
    }
    for (final h in history) {
      messages.add({
        'role': h['role'] ?? 'user',
        'content': h['content'] ?? '',
      });
    }
    messages.add({'role': 'user', 'content': message});
    return messages;
  }
}
