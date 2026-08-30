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
  // 异步歌词创作（SubAgent 模式）
  // ═══════════════════════════════════════════════
  /// 发起异步歌词创作任务，立刻返回 task_id
  Future<AsyncLyricsTaskRef> createLyricsAsync({
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
      Uri.parse('$_baseUrl/lyrics/async'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    if (resp.statusCode != 200) throw Exception('异步任务创建失败');
    final data = jsonDecode(resp.body);
    return AsyncLyricsTaskRef(
      taskId: data['task_id'],
      status: data['status'],
      message: data['message'],
      streamUrl: data['stream_url'],
    );
  }

  /// 轮询查询任务状态
  Future<AsyncLyricsTask> getLyricsTask(String taskId) async {
    final resp = await _client.get(Uri.parse('$_baseUrl/lyrics/tasks/$taskId'));
    if (resp.statusCode == 404) throw Exception('任务不存在');
    if (resp.statusCode != 200) throw Exception('查询失败');
    return AsyncLyricsTask.fromJson(jsonDecode(resp.body));
  }

  /// 列出用户的异步任务
  Future<List<AsyncLyricsTaskRef>> listUserTasks({int limit = 10}) async {
    final resp = await _client.get(
      Uri.parse('$_baseUrl/lyrics/tasks/$_userId/list?limit=$limit'),
    );
    if (resp.statusCode != 200) throw Exception('查询失败');
    final data = jsonDecode(resp.body);
    return (data['tasks'] as List)
        .map((t) => AsyncLyricsTaskRef(
              taskId: t['task_id'],
              status: t['status'],
              theme: t['theme'],
              style: t['style'],
              progress: t['progress'],
              createdAt: t['created_at'],
              finishedAt: t['finished_at'],
            ))
        .toList();
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

  // ═══════════════════════════════════════════════
  // 情绪状态机（接入 pub-local-jarvis 设计）
  // ═══════════════════════════════════════════════
  Future<MoodFeedResult> feedMood(double emotionScore) async {
    final resp = await _client.post(
      Uri.parse('$_baseUrl/mood/feed'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'user_id': _userId, 'emotion_score': emotionScore}),
    );
    if (resp.statusCode != 200) throw Exception('情绪状态更新失败');
    return MoodFeedResult.fromJson(jsonDecode(resp.body));
  }

  Future<MoodStatus> getMoodStatus() async {
    final resp = await _client.get(Uri.parse('$_baseUrl/mood/status/$_userId'));
    if (resp.statusCode != 200) throw Exception('获取情绪状态失败');
    return MoodStatus.fromJson(jsonDecode(resp.body));
  }

  Future<void> resetMood() async {
    await _client.post(Uri.parse('$_baseUrl/mood/reset/$_userId'));
  }

  // ═══════════════════════════════════════════════
  // 记忆存储（无 DB 依赖，文件型）
  // ═══════════════════════════════════════════════
  Future<void> memoryAppend(String kind, String text, {Map<String, dynamic>? metadata}) async {
    final resp = await _client.post(
      Uri.parse('$_baseUrl/memory/append'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_id': _userId,
        'kind': kind,
        'text': text,
        if (metadata != null) 'metadata': metadata,
      }),
    );
    if (resp.statusCode != 200) throw Exception('写入记忆失败');
  }

  Future<List<MemoryEvent>> memorySearch(String query, {String? kind, int limit = 10}) async {
    final uri = Uri.parse('$_baseUrl/memory/search/$_userId')
        .replace(queryParameters: {'q': query, if (kind != null) 'kind': kind, 'limit': '$limit'});
    final resp = await _client.get(uri);
    if (resp.statusCode != 200) throw Exception('搜索记忆失败');
    final data = jsonDecode(resp.body);
    return (data['results'] as List).map((r) => MemoryEvent.fromJson(r)).toList();
  }

  Future<List<MemoryEvent>> memoryRecent({String? kind, int limit = 20}) async {
    final uri = Uri.parse('$_baseUrl/memory/recent/$_userId')
        .replace(queryParameters: {if (kind != null) 'kind': kind, 'limit': '$limit'});
    final resp = await _client.get(uri);
    if (resp.statusCode != 200) throw Exception('获取记忆失败');
    final data = jsonDecode(resp.body);
    return (data['events'] as List).map((e) => MemoryEvent.fromJson(e)).toList();
  }

  // ═══════════════════════════════════════════════
  // SSE 主动推送（EventSource 接入）
  // ═══════════════════════════════════════════════
  /// 返回 SSE 流 URL，前端用 EventSource(url) 接入
  String get pushStreamUrl => '$_baseUrl/push/stream/$_userId';

  void dispose() => _client.close();

  // ═══════════════════════════════════════════════
  // SSE 流式歌词订阅
  // ═══════════════════════════════════════════════
  Stream<LyricsStreamEvent> streamLyrics(String taskId) async* {
    final url = Uri.parse('$_baseUrl/lyrics/stream/$taskId');
    final req = http.Request('GET', url);
    req.headers['Accept'] = 'text/event-stream';
    req.headers['Cache-Control'] = 'no-cache';
    final stream = await _client.send(req);
    String buffer = '';
    await for (final chunk in stream.stream) {
      buffer += utf8.decode(chunk);
      final lines = buffer.split('\n');
      buffer = lines.removeLast();
      for (final line in lines) {
        if (!line.startsWith('data: ')) continue;
        final jsonStr = line.substring(6).trim();
        if (jsonStr.isEmpty) continue;
        try {
          yield LyricsStreamEvent.fromJson(jsonDecode(jsonStr));
        } catch (_) {}
      }
    }
  }
}

// ═══════════════════════════════════════════════
// SSE 流事件
// ═══════════════════════════════════════════════
class LyricsStreamEvent {
  final String event; // 'progress' | 'done' | 'failed' | 'error' | 'heartbeat'
  final int? progress;
  final String? msg;
  final AsyncLyricsResult? result;
  final String? error;

  LyricsStreamEvent({
    required this.event,
    this.progress,
    this.msg,
    this.result,
    this.error,
  });

  factory LyricsStreamEvent.fromJson(Map<String, dynamic> j) => LyricsStreamEvent(
    event: j['event'] ?? '',
    progress: j['progress'],
    msg: j['msg'],
    result: j['result'] != null ? AsyncLyricsResult.fromJson(j['result']) : null,
    error: j['error'],
  );

  bool get isDone => event == 'done';
  bool get isFailed => event == 'failed';
  bool get isProgress => event == 'progress';
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

// ═══════════════════════════════════════════════
// 情绪状态机 + 记忆存储模型（pub-local-jarvis 设计）
// ═══════════════════════════════════════════════

/// 情绪状态机的输入结果
class MoodFeedResult {
  final String currentMood;
  final bool isActive;
  final bool changed;
  final String? changeFrom;
  final String? changeTo;
  final bool shouldPush;
  final String pushReason;
  final String? recommendation;
  final String? pushTone;

  MoodFeedResult({
    required this.currentMood,
    required this.isActive,
    required this.changed,
    this.changeFrom,
    this.changeTo,
    required this.shouldPush,
    required this.pushReason,
    this.recommendation,
    this.pushTone,
  });

  factory MoodFeedResult.fromJson(Map<String, dynamic> j) => MoodFeedResult(
    currentMood: j['current_mood'] ?? 'neutral',
    isActive: j['is_active'] ?? false,
    changed: j['changed'] ?? false,
    changeFrom: j['change_from'],
    changeTo: j['change_to'],
    shouldPush: j['should_push'] ?? false,
    pushReason: j['push_reason'] ?? '',
    recommendation: j['recommendation'],
    pushTone: j['push_tone'],
  );
}

/// 当前情绪状态快照
class MoodStatus {
  final String currentMood;
  final bool isActive;
  final String recommendation;
  final String pushTone;
  final int consecutiveNegative;

  MoodStatus({
    required this.currentMood,
    required this.isActive,
    required this.recommendation,
    required this.pushTone,
    required this.consecutiveNegative,
  });

  factory MoodStatus.fromJson(Map<String, dynamic> j) => MoodStatus(
    currentMood: j['current_mood'] ?? 'neutral',
    isActive: j['is_active'] ?? false,
    recommendation: j['recommendation'] ?? '',
    pushTone: j['push_tone'] ?? '',
    consecutiveNegative: j['consecutive_negative'] ?? 0,
  );
}

/// 记忆事件
class MemoryEvent {
  final String id;
  final String kind;
  final String text;
  final double score;
  final String timestamp;
  final Map<String, dynamic> metadata;

  MemoryEvent({
    required this.id,
    required this.kind,
    required this.text,
    required this.score,
    required this.timestamp,
    required this.metadata,
  });

  factory MemoryEvent.fromJson(Map<String, dynamic> j) => MemoryEvent(
    id: j['id'] ?? '',
    kind: j['kind'] ?? '',
    text: j['text'] ?? '',
    score: (j['score'] ?? 0.0).toDouble(),
    timestamp: j['timestamp'] ?? '',
    metadata: Map<String, dynamic>.from(j['metadata'] ?? {}),
  );
}

// ═══════════════════════════════════════════════
// 异步歌词创作模型
// ═══════════════════════════════════════════════

/// 异步任务引用（创建后立即返回）
class AsyncLyricsTaskRef {
  final String taskId;
  final String status;
  final String? message;
  final String? streamUrl;
  final String? theme;
  final String? style;
  final int? progress;
  final String? createdAt;
  final String? finishedAt;

  AsyncLyricsTaskRef({
    required this.taskId,
    required this.status,
    this.message,
    this.streamUrl,
    this.theme,
    this.style,
    this.progress,
    this.createdAt,
    this.finishedAt,
  });
}

/// 异步任务详情（轮询返回）
class AsyncLyricsTask {
  final String taskId;
  final String status; // pending | running | done | failed
  final int progress;
  final String? progressMsg;
  final AsyncLyricsResult? result;
  final String? error;
  final String? createdAt;
  final String? finishedAt;

  AsyncLyricsTask({
    required this.taskId,
    required this.status,
    required this.progress,
    this.progressMsg,
    this.result,
    this.error,
    this.createdAt,
    this.finishedAt,
  });

  factory AsyncLyricsTask.fromJson(Map<String, dynamic> j) => AsyncLyricsTask(
    taskId: j['task_id'],
    status: j['status'],
    progress: j['progress'] ?? 0,
    progressMsg: j['progress_msg'],
    result: j['result'] != null ? AsyncLyricsResult.fromJson(j['result']) : null,
    error: j['error'],
    createdAt: j['created_at'],
    finishedAt: j['finished_at'],
  );

  bool get isPending => status == 'pending';
  bool get isRunning => status == 'running';
  bool get isDone => status == 'done';
  bool get isFailed => status == 'failed';
}

/// 异步创作结果
class AsyncLyricsResult {
  final String lyrics;
  final String note;
  final String theme;
  final String style;
  final String mood;
  final String petReaction;
  final String? lyricId;

  AsyncLyricsResult({
    required this.lyrics,
    required this.note,
    required this.theme,
    required this.style,
    required this.mood,
    required this.petReaction,
    this.lyricId,
  });

  factory AsyncLyricsResult.fromJson(Map<String, dynamic> j) => AsyncLyricsResult(
    lyrics: j['lyrics'] ?? '',
    note: j['note'] ?? '',
    theme: j['theme'] ?? '',
    style: j['style'] ?? '',
    mood: j['mood'] ?? '',
    petReaction: j['pet_reaction'] ?? '汪！写好了！',
    lyricId: j['lyric_id']?.toString(),
  );
}
