import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// 宠物 API 服务
/// 连接 Flutter 前端 和 FastAPI 后端
class PetApiService {
  /// 生产环境请改成实际部署地址
  /// 如：https://your-backend.example.com
  static String get baseUrl => const String.fromEnvironment(
    'PET_API_URL',
    defaultValue: 'http://localhost:8000',
  );

  final String _baseUrl;
  final http.Client _client;
  String _userId;

  PetApiService({
    String? userId,
    http.Client? client,
  })  : _baseUrl = baseUrl,
        _client = client ?? http.Client(),
        _userId = userId ?? 'default_user';

  void setUserId(String id) => _userId = id;

  // ═══════════════════════════════════════════════
  // 宠物状态
  // ═══════════════════════════════════════════════
  Future<PetState> getPetState() async {
    final resp = await _client.get(Uri.parse('$_baseUrl/pet/state/$_userId'));
    if (resp.statusCode != 200) throw Exception('获取宠物状态失败');
    return PetState.fromJson(jsonDecode(resp.body));
  }

  // ═══════════════════════════════════════════════
  // 宠物交互
  // ═══════════════════════════════════════════════
  Future<InteractionResult> interact(String action) async {
    final resp = await _client.post(
      Uri.parse('$_baseUrl/pet/interact/$_userId?action=$action'),
    );
    if (resp.statusCode != 200) throw Exception('交互失败');
    return InteractionResult.fromJson(jsonDecode(resp.body));
  }

  // ═══════════════════════════════════════════════
  // AI 对话
  // ═══════════════════════════════════════════════
  Future<ChatResult> chat(List<ChatMessage> messages, {String? petMood}) async {
    final body = {
      'messages': messages.map((m) => {'role': m.role, 'content': m.content}).toList(),
      'user_id': _userId,
      if (petMood != null) 'pet_mood': petMood,
    };

    final resp = await _client.post(
      Uri.parse('$_baseUrl/chat'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    if (resp.statusCode != 200) throw Exception('对话失败: ${resp.body}');
    final data = jsonDecode(resp.body);
    return ChatResult.fromJson(data);
  }

  // ═══════════════════════════════════════════════
  // 歌词创作
  // ═══════════════════════════════════════════════
  Future<LyricsResult> createLyrics({
    required String theme,
    required String style,
    required String mood,
    String? additional,
    String? userMood,
  }) async {
    final body = {
      'theme': theme,
      'style': style,
      'mood': mood,
      'user_id': _userId,
      if (additional != null) 'additional': additional,
      if (userMood != null) 'user_mood': userMood,
    };

    final resp = await _client.post(
      Uri.parse('$_baseUrl/lyrics'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    if (resp.statusCode != 200) throw Exception('歌词创作失败');
    return LyricsResult.fromJson(jsonDecode(resp.body));
  }

  // ═══════════════════════════════════════════════
  // 音乐生成
  // ═══════════════════════════════════════════════
  Future<MusicResult> generateMusic({
    required String lyrics,
    required String prompt,
    int duration = 30,
    String language = 'zh',
  }) async {
    final body = {
      'lyrics': lyrics,
      'prompt': prompt,
      'duration': duration,
      'language': language,
      'user_id': _userId,
    };

    final resp = await _client.post(
      Uri.parse('$_baseUrl/generate'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    if (resp.statusCode != 200) throw Exception('音乐生成失败');
    return MusicResult.fromJson(jsonDecode(resp.body));
  }

  void dispose() => _client.close();
}

// ═══════════════════════════════════════════════
// 数据模型
// ═══════════════════════════════════════════════
class PetState {
  final String mood;
  final double love;
  final int totalBarks;
  final int songsCreated;
  final String? lastSongTitle;

  PetState({
    required this.mood,
    required this.love,
    required this.totalBarks,
    required this.songsCreated,
    this.lastSongTitle,
  });

  factory PetState.fromJson(Map<String, dynamic> j) {
    return PetState(
      mood: j['mood'] ?? 'happy',
      love: (j['love'] ?? 50.0).toDouble(),
      totalBarks: j['total_barks'] ?? 0,
      songsCreated: j['songs_created'] ?? 0,
      lastSongTitle: j['last_song_title'],
    );
  }

  PetState copyWith({
    String? mood,
    double? love,
    int? totalBarks,
    int? songsCreated,
    String? lastSongTitle,
  }) {
    return PetState(
      mood: mood ?? this.mood,
      love: love ?? this.love,
      totalBarks: totalBarks ?? this.totalBarks,
      songsCreated: songsCreated ?? this.songsCreated,
      lastSongTitle: lastSongTitle ?? this.lastSongTitle,
    );
  }

  static const moods = ['happy', 'excited', 'sleepy', 'hungry', 'confused', 'angry'];
  static const moodEmojis = {
    'happy': '😄',
    'excited': '🤩',
    'sleepy': '😴',
    'hungry': '🤤',
    'confused': '😕',
    'angry': '😠',
  };
  static const moodNames = {
    'happy': '开心',
    'excited': '兴奋',
    'sleepy': '犯困',
    'hungry': '饥饿',
    'confused': '困惑',
    'angry': '生气',
  };
}

class InteractionResult {
  final String dialogue;
  final String mood;
  final double love;
  InteractionResult({required this.dialogue, required this.mood, required this.love});
  factory InteractionResult.fromJson(Map<String, dynamic> j) => InteractionResult(
    dialogue: j['dialogue'] ?? '',
    mood: j['mood'] ?? 'happy',
    love: (j['love'] ?? 50.0).toDouble(),
  );
}

class ChatMessage {
  final String role; // 'user' | 'assistant' | 'system'
  final String content;
  ChatMessage({required this.role, required this.content});
  Map<String, dynamic> toJson() => {'role': role, 'content': content};
}

class ChatResult {
  final String reply;
  final Map<String, dynamic>? lyricsIntent;
  final Map<String, dynamic>? musicIntent;
  final PetState petState;

  ChatResult({
    required this.reply,
    this.lyricsIntent,
    this.musicIntent,
    required this.petState,
  });

  factory ChatResult.fromJson(Map<String, dynamic> j) => ChatResult(
    reply: j['reply'] ?? '',
    lyricsIntent: j['lyrics_intent'],
    musicIntent: j['music_intent'],
    petState: PetState.fromJson(j['pet_state'] ?? {}),
  );

  bool get hasLyricsIntent => lyricsIntent != null && lyricsIntent!.isNotEmpty;
  bool get hasMusicIntent => musicIntent != null && musicIntent!.isNotEmpty;
}

class LyricsResult {
  final String lyrics;
  final String note;
  final String theme;
  final String style;
  final String mood;
  final String petReaction;
  final String createdAt;

  LyricsResult({
    required this.lyrics,
    required this.note,
    required this.theme,
    required this.style,
    required this.mood,
    required this.petReaction,
    required this.createdAt,
  });

  factory LyricsResult.fromJson(Map<String, dynamic> j) => LyricsResult(
    lyrics: j['lyrics'] ?? '',
    note: j['note'] ?? '',
    theme: j['theme'] ?? '',
    style: j['style'] ?? '',
    mood: j['mood'] ?? '',
    petReaction: j['pet_reaction'] ?? '',
    createdAt: j['created_at'] ?? '',
  );
}

class MusicResult {
  final String? audioUrl;
  final String? metadata;
  final int duration;
  final String petReaction;
  final PetState petState;

  MusicResult({
    this.audioUrl,
    this.metadata,
    required this.duration,
    required this.petReaction,
    required this.petState,
  });

  factory MusicResult.fromJson(Map<String, dynamic> j) => MusicResult(
    audioUrl: j['audio_url'],
    metadata: j['metadata'],
    duration: j['duration'] ?? 30,
    petReaction: j['pet_reaction'] ?? '汪！生成好了！',
    petState: PetState.fromJson(j['pet_state'] ?? {}),
  );
}
