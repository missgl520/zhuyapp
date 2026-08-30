// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// TTS 服务（Text-to-Speech / 文字转语音）
//
// 底层：本地自托管 IndexTTS 2.5 微服务（见 F:/zhuyapp-backend/tts_service/app.py）
// 流程：调用后端 /tts 接口 -> 拿到 WAV 字节 -> just_audio 播放
// 情绪：把聊天情绪(emotion)传给后端，由 IndexTTS 的 emo_text 控制嗓音情绪
// 离线优先：TTS 失败（服务未起 / 网络断开）时静默跳过，不阻断文字对话
//
// 上游：对话页（点「朗读」或自动播报）、音乐狗子相关页。
// 下游：BackendService.tts（后端 /tts）、just_audio、临时目录。
//
// 关键点：
//   1. 三层降级：本地 IndexTTS → 云端（MiniMax / Cartesia）→ 系统 TTS；
//      本类只负责第一层，失败时把 _ttsAvailable 置 false 并静默返回。
//   2. speak() 会等待整段播放完成才返回（60s 超时保护），
//      调用方若不想阻塞可不等 Future。
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

import 'dart:async';
import 'dart:io';

import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:zhuyapp/core/services/backend_service.dart';

/// TTS 服务：把文字交给本地 IndexTTS 合成并用 just_audio 播放。
///
/// 不可用时所有 speak 调用静默返回，绝不阻断文字对话链路。
class TtsService {
  final AudioPlayer _player = AudioPlayer();
  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _ttsAvailable = true;

  /// 当前是否正在播放
  bool get isPlaying => _isPlaying;

  /// 本地 IndexTTS 服务是否可用（不可用时 UI 可据此禁用「朗读」入口）
  bool get ttsAvailable => _ttsAvailable;

  // ── 初始化 ──
  /// 订阅播放状态流以维护 [isPlaying]。重复调用幂等。
  Future<void> init() async {
    if (_isInitialized) return;
    _isInitialized = true;
    try {
      _player.playerStateStream.listen((s) {
        _isPlaying = s.playing;
        if (s.processingState == ProcessingState.completed) _isPlaying = false;
      });
    } catch (_) {
      // 播放器初始化异常时保持「已初始化但不可用」状态，文字照常显示。
      _ttsAvailable = false;
    }
  }

  // ── 朗读文本（经本地 IndexTTS 合成语音）──
  /// [emotion] 情绪标签(happy/sad/shy/cute/...) 驱动嗓音情绪
  /// [lang] 语种(ZH/EN/JA/ES/AR)  [speed] 语速(0.5-2.0)
  Future<void> speak(
    String text, {
    String? emotion,
    String lang = 'ZH',
    double speed = 1.0,
  }) async {
    if (!_isInitialized) await init();
    if (!_ttsAvailable) return; // 不可用，静默跳过，文字仍正常显示
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    try {
      final bytes = await BackendService.instance.tts(
        text: trimmed,
        emotion: emotion,
        lang: lang,
        speed: speed,
      );
      if (bytes == null || bytes.isEmpty) return; // 静默降级
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/zhuyu_tts_${DateTime.now().microsecondsSinceEpoch}.wav',
      );
      await file.writeAsBytes(bytes);
      try {
        await _player.stop();
        await _player.setAudioSource(AudioSource.file(file.path));
        await _player.play();
        // 等待播放结束再返回，保证 finally 块在朗读完成后执行
        final done = Completer<void>();
        late final StreamSubscription<PlayerState> sub;
        sub = _player.playerStateStream.listen((s) {
          if (s.processingState == ProcessingState.completed) {
            sub.cancel();
            if (!done.isCompleted) done.complete();
          }
        });
        await done.future.timeout(
          const Duration(seconds: 60),
          onTimeout: () {
            sub.cancel();
          },
        );
      } finally {
        try {
          await file.delete();
        } catch (_) {}
      }
    } catch (_) {
      // 朗读失败不阻断对话流程
      _isPlaying = false;
    }
  }

  // ── 停止朗读 ──
  /// 打断当前朗读（播放器异常时吞掉，保证状态复位）。
  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (_) {}
    _isPlaying = false;
  }
}
