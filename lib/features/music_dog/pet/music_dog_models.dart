// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// 音乐狗子创作台：状态模型 + 业务 Provider + 聊天桥接
//
// 本文件统一音乐狗子创作台用到的主 App 状态模型与后端桥接，
// 替换原副 App 的 PetApiService / ApiPetState / LocalChatRepository /
// TtsService / LyricsResult / MusicResult，全部走主 App 现有后端契约
// （/pet/state /chat/v2 /lyrics /music/generate /music/jobs）。
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zhuyapp/core/services/backend_service.dart';

/// 主 App 宠物状态（字段严格对齐后端 /pet/state）
/// 仅使用主 App 字段：mood / energy / bond / hunger / happiness / level / exp
/// 副 App 的 love / totalBarks / songsCreated 不直接写入本模型。
class ZhuyPetState {
  final String mood;
  final double energy;
  final double bond;
  final double hunger;
  final double happiness;
  final int level;
  final int exp;

  const ZhuyPetState({
    this.mood = 'neutral',
    this.energy = 80,
    this.bond = 10,
    this.hunger = 30,
    this.happiness = 60,
    this.level = 1,
    this.exp = 0,
  });

  factory ZhuyPetState.fromBackend(Map<String, dynamic> data) {
    if (data.isEmpty) return const ZhuyPetState();
    double num_(dynamic v, double d) => (v is num) ? v.toDouble() : d;
    int int_(dynamic v, int d) => (v is num) ? v.toInt() : d;
    return ZhuyPetState(
      mood: (data['mood'] as String?) ?? 'neutral',
      energy: num_(data['energy'], 80),
      bond: num_(data['bond'], 10),
      hunger: num_(data['hunger'], 30),
      happiness: num_(data['happiness'], 60),
      level: int_(data['level'], 1),
      exp: int_(data['exp'], 0),
    );
  }

  /// 副 App 状态栏展示用的「好感度」映射到主 App 的 bond（仅读取，不双写）
  double get love => bond;

  static const Map<String, String> moodEmojis = {
    'happy': '😄',
    'excited': '🤩',
    'sleepy': '😴',
    'hungry': '🤤',
    'sad': '😢',
    'angry': '😠',
    'confused': '😕',
    'neutral': '🐕',
    'playful': '😋',
    'love': '🥰',
  };
}

/// 歌词创作结果（UI 本地模型，字段对应后端 /lyrics 条目）
class LyricsResult {
  final int? id;
  final String lyrics;
  final String style;
  final String mood;
  final String note;
  final String petReaction;

  const LyricsResult({
    this.id,
    required this.lyrics,
    this.style = '',
    this.mood = '',
    this.note = '',
    this.petReaction = '',
  });
}

/// 音乐生成结果（UI 本地模型，字段对应 /music/jobs 条目）
class MusicResult {
  final String petReaction;
  final String? audioUrl;
  final int duration;

  const MusicResult({
    this.petReaction = '',
    this.audioUrl,
    this.duration = 0,
  });
}

/// 宠物状态 Provider：从主 App 后端 /pet/state 读取，统一为 ZhuyPetState。
final petStateProvider = FutureProvider<ZhuyPetState>((ref) async {
  final data = await BackendService.instance.getPetState();
  return ZhuyPetState.fromBackend(data);
});

/// 创作台聊天回复（替代副 App 的 ChatResult）。
class ChatReply {
  final String reply;
  final Map<String, String>? lyricsIntent;
  final Map<String, String>? musicIntent;

  const ChatReply(this.reply, {this.lyricsIntent, this.musicIntent});

  bool get hasLyricsIntent => lyricsIntent != null;
  bool get hasMusicIntent => musicIntent != null;
}

/// 调用主 App /chat/v2 SSE 与狗子对话，流式累积回复文本。
/// 歌词/音乐意图从用户消息中启发式识别（后端无结构化意图接口）。
Future<ChatReply> askDog(String message) async {
  final buffer = StringBuffer();
  try {
    await BackendService.instance.streamChat(
      message: message,
      history: const <Map<String, String>>[],
      onText: (t) => buffer.write(t),
    );
  } catch (_) {
    // 网络异常由调用方统一处理错误气泡
  }
  final reply = buffer.toString().trim();
  return ChatReply(
    reply.isEmpty ? '汪…（没听清）' : reply,
    lyricsIntent: _detectLyricsIntent(message),
    musicIntent: _detectMusicIntent(message),
  );
}

/// 从用户消息启发式提取歌词创作意图（主题/风格/情绪）。
Map<String, String>? _detectLyricsIntent(String msg) {
  if (!RegExp(r'歌词|写首?歌|创作|谱词|作歌|写词').hasMatch(msg)) return null;
  String style = '流行';
  if (RegExp(r'民谣').hasMatch(msg)) {
    style = '民谣';
  } else if (RegExp(r'古风|国风').hasMatch(msg)) {
    style = '古风';
  } else if (RegExp(r'说唱|rap|嘻哈', caseSensitive: false).hasMatch(msg)) {
    style = '说唱';
  } else if (RegExp(r'摇滚').hasMatch(msg)) {
    style = '摇滚';
  } else if (RegExp(r'电子|电音|dj', caseSensitive: false).hasMatch(msg)) {
    style = '电音';
  }
  String mood = '欢快';
  if (RegExp(r'失恋|难过|伤心|痛苦|分手').hasMatch(msg)) {
    mood = '伤感';
  } else if (RegExp(r'热血|燃|激昂').hasMatch(msg)) {
    mood = '热血';
  } else if (RegExp(r'治愈|温柔|安静').hasMatch(msg)) {
    mood = '治愈';
  }
  String theme = msg.replaceAll(RegExp(r'[，。！?？、\s]'), '');
  final m = RegExp(r'(?:关于|写首?关于|一首关于)(.+?)(?:的?歌|的?歌曲)').firstMatch(msg);
  if (m != null) theme = m.group(1)!;
  return {
    '主题': theme.isEmpty ? '自由创作' : theme,
    '风格': style,
    '情绪': mood,
  };
}

/// 从用户消息启发式提取音乐生成意图（描述/时长）。
Map<String, String>? _detectMusicIntent(String msg) {
  if (!RegExp(r'生成音乐|作曲|谱曲|做首?歌|来一首|生成一首|写首?曲').hasMatch(msg)) return null;
  return {'描述': msg, '时长': '30'};
}
