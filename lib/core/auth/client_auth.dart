// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// 客户端鉴权（client_auth.dart）
//
// 与后端 auth.py 完全一致的「API Key + 请求签名」实现：
//   - 每个请求携带 X-Api-Key / X-Timestamp / X-Nonce / X-Signature / X-User-Id
//   - 签名串 = HMAC-SHA256(API_KEY, "METHOD\nPATH\nTIMESTAMP\nNONCE\nSHA256(BODY)")
//   - 设备 user_id：按安装生成并持久化，用于后端多用户数据隔离
//
// 生产构建请通过 --dart-define=ZHUYU_API_KEY=<与后端一致的密钥> 注入，
// 切勿把真实密钥硬编码进仓库。
//
// 上游：SigningInterceptor（ Dio 拦截器，自动为所有请求签名）、
//       LiveKitService / MemoryService（手动调用 signedHeaders）。
// 下游：crypto（HMAC-SHA256）、uuid、Hive 'settings'（持久化 deviceUserId）。
//
// 关键点：
//   1. 签名串的分隔符、字段顺序、body 哈希必须与后端 auth.py 逐字节一致，
//      改动任一侧都会导致全量 401。
//   2. 参与签名的 path 只含路径、不含 query（与后端 request.url.path 对齐）。
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

/// 客户端鉴权单例：负责生成本设备 user_id 与请求签名头。
class ClientAuth {
  ClientAuth._();

  /// 全局单例访问器。
  static final ClientAuth instance = ClientAuth._();

  /// 必须与后端 ZHUYU_API_KEY 一致；生产环境用 --dart-define 覆盖。
  static const String apiKey = String.fromEnvironment(
    'ZHUYU_API_KEY',
    defaultValue: 'zhuyu-dev-key-change-me',
  );

  String? _cachedUserId;

  /// 设备 / 用户唯一标识（按安装生成，持久化到 Hive）。
  Future<String> get userId async {
    if (_cachedUserId != null) return _cachedUserId!;
    final box = await Hive.openBox('settings');
    String id = box.get('deviceUserId', defaultValue: '') as String;
    if (id.isEmpty) {
      id = const Uuid().v4();
      await box.put('deviceUserId', id);
    }
    _cachedUserId = id;
    return id;
  }

  /// 计算签名头（与后端 canonical 严格一致）。
  ///
  /// [method]    HTTP 方法，必须大写（GET / POST / PUT / DELETE）。
  /// [path]      请求路径，不含 query string，例如 `/chat/v2`。
  /// [bodyBytes] 请求体原始字节；无 body 时传空列表。
  /// [userId]    设备用户 id，取 [userId] getter。
  ///
  /// 返回可直接塞进 `options.headers` 的五个头字段。
  Map<String, String> signedHeaders({
    required String method,
    required String path,
    required List<int> bodyBytes,
    required String userId,
  }) {
    final ts = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final nonce = const Uuid().v4();
    final bodyHash = sha256.convert(bodyBytes).toString();
    final canonical = '$method\n$path\n$ts\n$nonce\n$bodyHash';
    final sig = Hmac(
      sha256,
      utf8.encode(apiKey),
    ).convert(utf8.encode(canonical)).toString();
    return {
      'X-Api-Key': apiKey,
      'X-Timestamp': ts,
      'X-Nonce': nonce,
      'X-Signature': sig,
      'X-User-Id': userId,
    };
  }
}

/// Dio 拦截器：自动为每个请求附加签名头与 user_id。
///
/// 挂在 BackendService / ChatService 的 Dio 实例上，业务代码无需关心鉴权。
/// 注意 body 需按 `jsonEncode(options.data)` 序列化后参与签名，
/// 与后端收到的原始字节保持一致。
class SigningInterceptor extends Interceptor {
  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final userId = await ClientAuth.instance.userId;
    final method = options.method.toUpperCase();
    final path = options.path; // 不含 query，与后端 request.url.path 对齐

    List<int> bodyBytes = const [];
    if (options.data != null) {
      try {
        bodyBytes = utf8.encode(jsonEncode(options.data));
      } catch (_) {
        bodyBytes = const [];
      }
    }

    final headers = ClientAuth.instance.signedHeaders(
      method: method,
      path: path,
      bodyBytes: bodyBytes,
      userId: userId,
    );
    options.headers.addAll(headers);
    handler.next(options);
  }
}
