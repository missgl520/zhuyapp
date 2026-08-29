// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// LiveKit 实时语音服务
//
// 功能：
//   1. 从后端获取连接信息（URL + Token）
//   2. 连接 LiveKit 房间
//   3. 启用麦克风（音频自动发布）
//   4. 订阅 AI Agent 音频（自动播放）
//
// 用法：
//   final svc = LiveKitService();
//   await svc.connect(room: 'zhuyapp-voice');
//   // 麦克风自动发布，AI 音频自动播放
//   await svc.disconnect();
//
// 上游：语音通话页（VoiceCallPage）。
// 下游：后端 /livekit/connect（取 token，需签名）、livekit_client SDK。
//
// 关键点：
//   1. 连接信息必须带签名头请求，后端 /livekit/connect 强制鉴权。
//   2. Android/iOS 音频播放被系统打断（如来电）后需在
//      AudioPlaybackStatusChanged 里手动 startAudio() 恢复。
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:livekit_client/livekit_client.dart';

import '../auth/client_auth.dart';
import '../config.dart';

/// 连接状态
enum LiveKitState {
  /// 未连接（初始态 / 已断开）。
  idle,

  /// 正在握手中。
  connecting,

  /// 已连接，麦克风已发布、AI 音频可订阅。
  connected,

  /// 连接失败，详情见 LiveKitService.errorMessage。
  error,
}

/// LiveKit 实时语音服务
///
/// 负责「取 token → 进房 → 开麦 → 订阅 AI 音频」的完整链路，
/// 状态通过 [state] 只读暴露给 UI。
class LiveKitService {
  Room? _room;
  EventsListener<RoomEvent>? _listener;
  String? _errorMessage;

  LiveKitState _state = LiveKitState.idle;

  // ── Getters ──────────────────────────────────────────

  /// 当前连接状态。
  LiveKitState get state => _state;

  /// 最近一次失败的原因；成功/未失败时为 null。
  String? get errorMessage => _errorMessage;

  /// 是否已成功连接。
  bool get isConnected => _state == LiveKitState.connected;

  // ── 连接 ─────────────────────────────────────────────

  /// 从后端获取 token 并连接 LiveKit 房间。
  ///
  /// [room] 房间名；[userId] 传给后端做身份区分，可为空。
  /// 已在连接/已连接时直接返回（幂等）。失败会 rethrow，状态置为 error。
  Future<void> connect({required String room, String userId = ''}) async {
    if (_state == LiveKitState.connecting || _state == LiveKitState.connected) {
      return;
    }

    _setState(LiveKitState.connecting, null);

    try {
      // 1. 从后端获取连接信息
      final connInfo = await _fetchConnectionInfo(room: room, userId: userId);
      final url = connInfo['livekit_url'] as String;
      final token = connInfo['token'] as String;

      debugPrint('[LiveKit] connecting to $url, room=$room');

      // 2. 创建 Room 实例
      _room = Room(
        roomOptions: RoomOptions(adaptiveStream: true, dynacast: true),
      );

      // 3. 创建事件监听器（示例见 https://docs.livekit.io/client/events/#events）
      _listener = _room!.createListener();
      _listener!
        ..on<RoomDisconnectedEvent>((event) {
          debugPrint('[LiveKit] room disconnected: ${event.reason}');
          _setState(LiveKitState.idle, null);
        })
        ..on<TrackSubscribedEvent>((event) {
          debugPrint('[LiveKit] track subscribed: ${event.track.sid}');
        })
        ..on<ParticipantEvent>((event) {
          debugPrint('[LiveKit] participant event: $event');
        })
        ..on<AudioPlaybackStatusChanged>((event) async {
          debugPrint('[LiveKit] audio playback: ${event.isPlaying}');
          if (!event.isPlaying) {
            await _room?.startAudio();
          }
        });

      // 4. 连接
      await _room!.connect(url, token);
      debugPrint('[LiveKit] connected!');

      // 5. 启用麦克风
      await _room!.localParticipant?.setMicrophoneEnabled(
        true,
        audioCaptureOptions: const AudioCaptureOptions(
          noiseSuppression: true,
          echoCancellation: true,
        ),
      );
      debugPrint('[LiveKit] microphone enabled');

      _setState(LiveKitState.connected, null);
    } catch (e) {
      debugPrint('[LiveKit] connect error: $e');
      _setState(LiveKitState.error, e.toString());
      rethrow;
    }
  }

  /// 主动断开：取消监听、退出房间并回到 idle 状态。
  Future<void> disconnect() async {
    await _listener?.cancelAll();
    _listener = null;
    await _room?.disconnect();
    _room = null;
    _setState(LiveKitState.idle, null);
  }

  /// 切换静音（true = 关闭麦克风）。未连接时为空操作。
  Future<void> setMuted(bool muted) async {
    await _room?.localParticipant?.setMicrophoneEnabled(!muted);
  }

  // ── 内部方法 ─────────────────────────────────────────

  /// 向后端 `/livekit/connect` 换取 `livekit_url` 与 `token`。
  ///
  /// 后端不可用或非 200 时抛 [Exception]。
  Future<Map<String, dynamic>> _fetchConnectionInfo({
    required String room,
    required String userId,
  }) async {
    try {
      final baseUrl = BackendConfig.instance.baseUrl;
      final authUserId = await ClientAuth.instance.userId;
      final headers = ClientAuth.instance.signedHeaders(
        method: 'GET',
        path: '/livekit/connect',
        bodyBytes: const [],
        userId: authUserId,
      );
      final resp = await http.get(
        Uri.parse('$baseUrl/livekit/connect?room=$room&user_id=$userId'),
        headers: headers,
      );
      if (resp.statusCode != 200) {
        throw Exception('获取 LiveKit 连接信息失败: ${resp.statusCode}');
      }
      return jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (e) {
      throw Exception('后端不可用: $e');
    }
  }

  /// 更新状态与错误信息（内部唯一入口，便于后续加通知）。
  void _setState(LiveKitState state, String? error) {
    _state = state;
    _errorMessage = error;
  }
}
