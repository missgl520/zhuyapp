// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// 同步引擎（Sync Engine）
//
// 位于：core/sync/sync_engine.dart
// 职责：离线优先的"同步基础设施"——把发件箱里的待发消息补发给后端。
//
// 触发时机：
//   - 网络状态从无网 → 有网（Connectivity 监听）
//   - App 启动且当前有网
//   - 定时兜底（后端挂了但网络在，无状态变化事件时仍能补发）
//
// 幂等：重发时带 client_msg_id，后端可去重；本地每条 outbox 只发一次，
//   成功即删除，天然不重复。
//
// 重试：指数退避（1s → 2s → 4s … 上限 30s），避免压垮客户端/服务端。
//
// 上游：main.dart（启动）、UI（通过 syncStream 感知同步完成）。
// 下游：ChatLocalDataSource（读写发件箱）、ChatService（补发请求）、
//       connectivity_plus（网络状态）。
//
// 关键点：
//   1. _syncing 标志做并发保护，定时器与网络回调同时触发时只跑一个 flush。
//   2. 补发时携带原始 client_msg_id，后端可去重；成功后立即删除发件箱条目。
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../data/datasources/chat_local_data_source.dart';
import '../../data/services/chat_service.dart';

/// 离线优先同步引擎：把发件箱里未送达的用户消息补发给后端。
class SyncEngine {
  SyncEngine._();

  /// 全局单例访问器。
  static final SyncEngine instance = SyncEngine._();

  final Connectivity _connectivity = Connectivity();
  final ChatService _service = ChatService();
  final ChatLocalDataSource _local = ChatLocalDataSource.instance;

  final StreamController<void> _syncCtrl = StreamController<void>.broadcast();

  /// 同步完成通知（flush 成功后触发，供 UI 刷新刚同步回来的消息）
  Stream<void> get syncStream => _syncCtrl.stream;

  bool _started = false;
  bool _syncing = false;

  /// 启动同步引擎：注册网络监听 + 立即尝试一次 + 30s 定时兜底。
  ///
  /// 在 main() 中调用一次即可；重复调用会被 _started 挡住。
  Future<void> start() async {
    if (_started) return;
    _started = true;

    // 联网状态变化 → 只要出现任一非 none 连接即补发
    _connectivity.onConnectivityChanged.listen((results) {
      if (results.any((r) => r != ConnectivityResult.none)) _flush();
    });

    // 启动即尝试一次（若当前有网）
    final current = await _connectivity.checkConnectivity();
    if (current.any((r) => r != ConnectivityResult.none)) _flush();

    // 定时兜底：后端挂了但网络在时，无状态变化事件也能补发
    Timer.periodic(const Duration(seconds: 30), (_) => _flush());
  }

  /// 遍历发件箱逐条补发；已在同步中则直接返回。
  Future<void> _flush() async {
    if (_syncing) return;
    _syncing = true;
    try {
      final pending = await _local.getPendingOutbox();
      for (final item in pending) {
        await _resend(item);
      }
    } finally {
      _syncing = false;
    }
  }

  /// 补发单条消息：先按尝试次数退避等待，再带着本地历史重放。
  ///
  /// 成功后写入 AI 回复、标记已同步并通知 UI；失败则累加 attempts。
  Future<void> _resend(OutboxItem item) async {
    // 指数退避：已尝试次数越多，等待越久（上限 30s）
    if (item.attempts > 0) {
      final delayMs = (1000 * (1 << (item.attempts - 1))).clamp(1000, 30000);
      await Future.delayed(Duration(milliseconds: delayMs));
    }

    try {
      // 用该消息之前真实的本地历史作为上下文，保证连贯
      final history = await _local.getHistoryBefore(item.clientMsgId);
      final buf = StringBuffer();

      await _service.streamChat(
        message: item.message,
        history: history,
        clientMsgId: item.clientMsgId,
        onText: (t) => buf.write(t),
        onDone: () {
          // 补发成功：把 AI 回复落本地，标记已同步，触发 UI 刷新
          _local.appendAssistantMessage(
            clientMsgId: item.clientMsgId,
            content: buf.toString(),
          );
          _local.markUserSynced(item.clientMsgId);
          _local.markOutboxSynced(item.clientMsgId);
          _syncCtrl.add(null);
        },
        onError: (err) {
          // 仍失败：保留，增加尝试次数，等退避后下次再试
          _local.incrementAttempt(item.clientMsgId, err);
        },
      );
    } catch (e) {
      _local.incrementAttempt(item.clientMsgId, e.toString());
    }
  }
}
