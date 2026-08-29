// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// ASR 语音识别服务（Automatic Speech Recognition）
//
// 底层依赖：speech_to_text，调用系统语音引擎
// - Android：Google 语音识别 / 小米语音
// - iOS：Apple Speech Framework
//
// 工作流程：
//   用户长按 → startListening() → 系统录音+识别 → onResult 回调
//   用户松开 → stopListening() → 返回最终识别文字
//
// 注意：
// - 需要麦克风权限（permission_handler）
// - 部分设备/语言需联网才能识别
//
// 上游：对话页（长按说话按钮）。
// 下游：speech_to_text 插件 → 系统语音引擎。
//
// 关键点：
//   1. 无语音引擎的设备（模拟器、无 GMS 机型）会在 initialize() 抛
//      PlatformException，必须捕获并降级为纯文字输入，否则 initState 阶段红屏。
//   2. 每次 startListening 前若已在监听，会先 stop，避免叠加会话。
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

import 'package:speech_to_text/speech_to_text.dart';

/// 语音识别服务：封装 speech_to_text，向 UI 提供「说话转文字」能力。
class AsrService {
  final SpeechToText _stt = SpeechToText();

  bool _isInitialized = false;
  bool _isListening = false;

  /// 当前是否正在收音。
  bool get isListening => _isListening;

  /// init() 时缓存的设备可用语种列表；未初始化时为空。
  List<LocaleName> _availableLocales = [];

  // ── 初始化 ──
  /// 拉取设备支持的语种列表。重复调用幂等。
  ///
  /// 设备无语音引擎时静默失败，保持未初始化状态，由调用方降级。
  Future<void> init() async {
    if (_isInitialized) return;
    try {
      _availableLocales = await _stt.locales();
      _isInitialized = true;
    } catch (e) {
      // 部分设备/模拟器没有语音识别引擎，locales() 会抛 PlatformException。
      // 捕获后保持未初始化状态，调用方降级为文字输入即可，不阻断 App。
      _isInitialized = false;
    }
  }

  // ── 请求麦克风权限 ──
  // 返回 true = 语音识别可用；false = 设备不支持（如模拟器、无 GMS 机型）。
  // 注意：必须吞掉底层的 PlatformException(recognizerNotAvailable)，否则会在
  // initState 阶段冒泡成 Unhandled Exception 导致红屏。
  ///
  /// 返回 true 表示识别器就绪，可以调用 startListening。
  Future<bool> requestPermission() async {
    try {
      final ok = await _stt.initialize(
        onStatus: (status) {
          _isListening = status == 'listening';
        },
        onError: (error) {
          _isListening = false;
        },
      );
      _isInitialized = ok;
      return ok;
    } catch (e) {
      _isInitialized = false;
      return false;
    }
  }

  // ── 开始监听 ──
  // onResult: 每次识别到文字时回调（中间结果 + 最终结果）
  // 返回值：是否正常启动
  ///
  /// [onResult] 的 `finalResult` 为 true 时表示该句是最终结果，
  /// false 为中间结果（可用于实时上屏）。
  Future<void> startListening({
    required void Function(String text, bool finalResult) onResult,
    String? localeId,
  }) async {
    if (!_isInitialized) await init();
    if (_isListening) await stopListening();

    _isListening = true;

    await _stt.listen(
      onResult: (result) {
        onResult(result.recognizedWords, result.finalResult);
      },
      listenOptions: SpeechListenOptions(
        localeId: localeId ?? 'zh_CN',
        listenMode: ListenMode.dictation,
        cancelOnError: true,
        partialResults: true, // 中间过程也回调（打字效果）
      ),
    );
  }

  // ── 停止监听 ──
  /// 结束本轮收音并触发最后一次结果回调。
  Future<void> stopListening() async {
    await _stt.stop();
    _isListening = false;
  }

  // ── 工具：找中文 localeId ──
  /// 优先返回 `zh_CN`/`zh_Hans_CN`，其次任意 `zh` 开头语种，
  /// 设备完全不支持中文时返回 null。
  String? get zhLocaleId {
    final zhCN = _availableLocales.where(
      (l) => l.localeId == 'zh_CN' || l.localeId == 'zh_Hans_CN',
    );
    if (zhCN.isNotEmpty) return zhCN.first.localeId;
    final zh = _availableLocales.where((l) => l.localeId.startsWith('zh'));
    return zh.isNotEmpty ? zh.first.localeId : null;
  }

  /// 释放识别器。页面 dispose 时调用，避免后台继续占用麦克风。
  void dispose() {
    _stt.cancel();
  }
}
