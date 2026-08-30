// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// 宠物创作助手页（features/music_dog/pet/pet_studio_page.dart）
//
// 职责：音乐狗子模块的「创作台」主页面——整合 3D 宠物展示、对话、歌词库
//       与音乐生成，以 Tab（创作台 / 歌词库 / 关于）组织交互。
//
// 上游：可从宠物入口或底部导航 push 进入。
// 下游：依赖 chatty_dog_pet.dart（宠物 Widget）、backend_service.dart（生成音乐）、
//       tts_service.dart（朗读）、music_dog_models.dart（数据模型）。
//
// 关键点：
//   1. 顶部宠物状态栏由 _PetStatusBar 独立封装，状态来自 petStateProvider。
//   2. 音频地址可能为相对路径，统一经 _absUrl 拼成绝对 URL 再播放。
//   3. 音乐生成走后端 /generate，失败需静默降级（见 tts / backend 三层防御）。
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:just_audio/just_audio.dart';
import 'package:zhuyapp/core/theme/app_theme.dart';
import 'package:zhuyapp/core/services/backend_service.dart';
import 'package:zhuyapp/core/services/tts_service.dart';
import 'package:zhuyapp/core/config.dart';
import 'package:zhuyapp/features/music_dog/pet/chatty_dog_pet.dart';
import 'package:zhuyapp/features/music_dog/pet/music_dog_models.dart';

/// 将后端返回的（可能为相对路径的）音频地址拼成可播放的绝对 URL。
String _absUrl(String url) {
  if (url.startsWith('http://') || url.startsWith('https://')) return url;
  final base = BackendConfig.instance.baseUrl;
  final sep = base.endsWith('/') ? '' : '/';
  return '$base$sep$url';
}

/// 宠物创作助手页面
/// 3D宠物 + 对话 + 歌词展示 + 音乐生成
class PetStudioPage extends ConsumerStatefulWidget {
  const PetStudioPage({super.key});

  @override
  ConsumerState<PetStudioPage> createState() => _PetStudioPageState();
}

/// 创作台页状态：持有 3 段 Tab 的控制器，并按 petStateProvider 渲染顶部状态栏。
class _PetStudioPageState extends ConsumerState<PetStudioPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController; // 创作台/歌词库/宠物 三 Tab 控制器

  /// 初始化 3 段 Tab 控制器，组件挂载时调用。
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  /// 释放 Tab 控制器，组件移除时调用。
  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// 构建页面骨架：顶部宠物状态栏 + TabBar + 三段 TabBarView 内容。
  @override
  Widget build(BuildContext context) {
    final petStateAsync = ref.watch(petStateProvider);
    final petState = petStateAsync.when(
      data: (s) => s,
      loading: () => const ZhuyPetState(),
      error: (_, __) => const ZhuyPetState(),
    );

    return Scaffold(
      body: Column(
        children: [
          // 顶部宠物状态栏
          _PetStatusBar(state: petState),

          // Tab: 创作台 / 歌词库 / 关于
          Container(
            color: AppTheme.surfaceWarm,
            child: TabBar(
              controller: _tabController,
              labelColor: AppTheme.ember,
              unselectedLabelColor: AppTheme.muted,
              indicatorColor: AppTheme.sun,
              tabs: const [
                Tab(icon: Icon(Icons.music_note), text: '创作台'),
                Tab(icon: Icon(Icons.library_music), text: '歌词库'),
                Tab(icon: Icon(Icons.pets), text: '宠物'),
              ],
            ),
          ),

          // Tab 内容
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                const _CreationStudio(),
                const _LyricsLibrary(),
                _PetAloneScreen(petState: petState),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// 宠物状态栏
// ═══════════════════════════════════════════════
/// 创作台顶部宠物状态栏：🐕 图标 + 心情 emoji + 好感度进度条。
class _PetStatusBar extends StatelessWidget {
  /// 当前宠物状态（来自 petStateProvider）。
  final ZhuyPetState state;
  const _PetStatusBar({required this.state});

  /// 构建状态栏：🐕 图标 + 名称 + 心情 emoji + 好感度进度条。
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.sunSoft, AppTheme.sunSoft],
        ),
      ),
      child: Row(
        children: [
          const Text('🐕', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          Text(
            '狗子',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppTheme.ember,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            ZhuyPetState.moodEmojis[state.mood] ?? '😄',
            style: const TextStyle(fontSize: 16),
          ),
          const Spacer(),
          // 好感度
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.sunSoft,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.sun),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('💕', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 4),
                SizedBox(
                  width: 50,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: state.love / 100,
                      backgroundColor: AppTheme.borderSoft,
                      valueColor: AlwaysStoppedAnimation(AppTheme.sun),
                      minHeight: 6,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '${state.love.toInt()}',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.ember,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// 创作台（核心页面）
// ═══════════════════════════════════════════════
/// 创作台核心页：狗子对话 + 歌词创作 + 音乐生成，本地状态自管理。
class _CreationStudio extends StatefulWidget {
  const _CreationStudio();

  @override
  State<_CreationStudio> createState() => _CreationStudioState();
}

/// 创作台状态：维护对话消息列表、输入框、歌词/音乐生成状态与 TTS 朗读。
class _CreationStudioState extends State<_CreationStudio> {
  final _controller = TextEditingController(); // 输入框文本控制器
  final _scrollController = ScrollController(); // 对话列表滚动控制器
  final List<_ChatBubble> _messages = []; // 对话消息列表（用户/狗子气泡）
  bool _isLoading = false; // 是否正在等待狗子/后端回复
  bool _ttsEnabled = true; // 是否开启语音播报

  // 歌词创作状态
  LyricsResult? _lastLyrics;
  MusicResult? _lastMusic;
  bool _isGeneratingMusic = false;

  // TTS 单例（懒加载，复用同一个 AudioPlayer）
  TtsService? _tts;
  TtsService get _ttsService {
    _tts ??= TtsService();
    return _tts!;
  }

  // 快捷语
  static const _quickPrompts = [
    ('写首歌', '帮我写一首关于{}的歌曲'),
    ('治愈系', '我想听疗愈的歌'),
    ('热血', '来一首让人热血沸腾的歌'),
    ('失恋', '帮我写首失恋的歌'),
    ('民谣风', '写首民谣风格的歌'),
  ];

  /// 释放输入/滚动控制器，组件移除时调用。
  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// 发送一条消息给狗子（或快捷语 [presetPrompt]）。
  ///
  /// 流程：调 [askDog] 拿回复 → 气泡展示 → 可选 TTS 朗读 →
  /// 若回复含歌词/音乐意图则自动串起创作链路。网络失败静默降级。
  Future<void> _sendMessage([String? presetPrompt]) async {
    final text = presetPrompt ?? _controller.text.trim();
    if (text.isEmpty) return;

    _controller.clear();
    setState(() {
      _messages.add(_ChatBubble(isUser: true, text: text));
      _isLoading = true;
    });
    _scrollToBottom();

    try {
      final result = await askDog(text);

      if (!mounted) return;

      setState(() {
        _messages.add(_ChatBubble(isUser: false, text: result.reply));
        _isLoading = false;
      });

      // 语音播报（失败静默降级，不影响对话）
      if (_ttsEnabled) {
        _ttsService.speak(result.reply);
      }

      // 如果有歌词创作意图，自动调用
      if (result.hasLyricsIntent) {
        final intent = result.lyricsIntent!;
        await _createLyrics(
          theme: intent['主题'] ?? intent['theme'] ?? '自由创作',
          style: intent['风格'] ?? intent['style'] ?? '流行',
          mood: intent['情绪'] ?? intent['mood'] ?? '欢快',
          content: result.reply,
        );
      }

      // 如果有音乐生成意图
      if (result.hasMusicIntent) {
        final intent = result.musicIntent!;
        if (_lastLyrics != null) {
          await _generateMusic(
            lyrics: _lastLyrics!.lyrics,
            prompt: intent['描述'] ?? intent['prompt'] ?? '流行风格',
            duration: int.tryParse(intent['时长'] ?? intent['duration'] ?? '30') ?? 30,
          );
        }
      }

      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add(_ChatBubble(
          isUser: false,
          text: '汪……网络出问题了，我已经帮你记在小本本上，联网后补发～',
          isError: true,
        ));
        _isLoading = false;
      });
    }
  }

  /// 调用后端 /lyrics 创建一条歌词，并把结果存到 [_lastLyrics]。
  ///
  /// Args:
  ///   theme: 标题/主题。
  ///   style: 风格标签。
  ///   mood: 情绪。
  ///   content: 歌词正文（直接用狗子回复）。
  Future<void> _createLyrics({
    required String theme,
    required String style,
    required String mood,
    required String content,
  }) async {
    setState(() => _isLoading = true);

    try {
      final id = await BackendService.instance.createLyrics(
        title: theme,
        content: content,
        mood: mood,
        tags: [style],
      );

      if (!mounted) return;

      setState(() {
        _lastLyrics = LyricsResult(
          id: id,
          lyrics: content,
          style: style,
          mood: mood,
          petReaction: '已经帮你写好《$theme》的歌词啦～',
          note: '由狗子创作台生成',
        );
        _isLoading = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('歌词创作失败: $e')),
        );
      }
    }
  }

  /// 用已有歌词向后端发起音乐生成并轮询任务，成功后弹出播放器。
  ///
  /// Args:
  ///   lyrics: 歌词正文。
  ///   prompt: 音乐风格描述。
  ///   duration: 期望时长（秒）。
  Future<void> _generateMusic({
    required String lyrics,
    required String prompt,
    required int duration,
  }) async {
    setState(() => _isGeneratingMusic = true);

    final audioUrl = await _pollMusicJob(lyrics: lyrics, prompt: prompt, duration: duration);

    if (!mounted) return;

    if (audioUrl != null) {
      final full = _absUrl(audioUrl);
      setState(() {
        _lastMusic = MusicResult(
          petReaction: '🎵 歌曲生成好啦！',
          audioUrl: full,
          duration: duration,
        );
        _isGeneratingMusic = false;
      });
      _showMusicPlayer(full, duration);
    } else {
      setState(() => _isGeneratingMusic = false);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('音乐生成失败或超时')),
        );
      }
    }
    _scrollToBottom();
  }

  /// 发起音乐生成（异步任务）并轮询状态，返回可播放的绝对音频 URL。
  Future<String?> _pollMusicJob({
    required String lyrics,
    required String prompt,
    required int duration,
  }) async {
    try {
      int? lyricsId = _lastLyrics?.id;
      if (lyricsId == null) {
        lyricsId = await BackendService.instance.createLyrics(
          title: '生成音乐歌词',
          content: lyrics,
          mood: '',
          tags: [],
        );
      }
      final jobId = await BackendService.instance.generateMusic(
        prompt: prompt,
        lyricsId: lyricsId,
        style: prompt,
        title: '',
      );
      if (jobId == null) return null;

      for (var i = 0; i < 30; i++) {
        await Future.delayed(const Duration(seconds: 2));
        final job = await BackendService.instance.getMusicJob(jobId);
        if (job == null) continue;
        final status = (job['status'] as String?) ?? '';
        if (status == 'done') {
          return (job['audio_url'] as String?);
        } else if (status == 'failed') {
          return null;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 以底部弹层展示 [_MusicPlayer] 播放器。
  void _showMusicPlayer(String url, int duration) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.sunSoft,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _MusicPlayer(url: url, duration: duration),
    );
  }

  /// 构建创作台：歌词预览 + 对话列表 + 快捷语 + 输入栏。
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 歌词预览（如果有）
        if (_lastLyrics != null)
          _LyricsPreview(
            lyrics: _lastLyrics!,
            onGenerateMusic: _lastMusic == null
                ? () => _generateMusic(
                      lyrics: _lastLyrics!.lyrics,
                      prompt: '${_lastLyrics!.style}风格',
                      duration: 30,
                    )
                : null,
            isGenerating: _isGeneratingMusic,
          ),

        // 对话列表
        Expanded(
          child: _messages.isEmpty
              ? _EmptyStudio(onPromptTap: _sendMessage)
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: _messages.length + (_isLoading ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (_isLoading && index == _messages.length) {
                      return const _TypingIndicator();
                    }
                    return _messages[index];
                  },
                ),
        ),

        // 快捷语
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _quickPrompts.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final (label, prompt) = _quickPrompts[index];
              return ActionChip(
                label: Text(label),
                avatar: const Icon(Icons.bolt, size: 16),
                backgroundColor: AppTheme.sunSoft,
                side: BorderSide(color: AppTheme.sunSoft),
                onPressed: () => _sendMessage(prompt.replaceAll('{}', '人生')),
              );
            },
          ),
        ),

        // 输入框
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText: '跟狗子说点什么……',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: AppTheme.borderSoft,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(
                    _ttsEnabled ? Icons.volume_up : Icons.volume_off,
                    color: AppTheme.muted,
                  ),
                  tooltip: _ttsEnabled ? '关闭语音播报' : '开启语音播报',
                  onPressed: () => setState(() => _ttsEnabled = !_ttsEnabled),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: AppTheme.sun,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white, size: 20),
                    onPressed: () => _sendMessage(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════
// 歌词预览卡片
// ═══════════════════════════════════════════════
/// 歌词预览卡片：展示刚创作的歌词、风格/情绪，并提供「生成歌曲」入口。
class _LyricsPreview extends StatelessWidget {
  /// 待预览的歌词结果。
  final LyricsResult lyrics;
  /// 点击「生成歌曲」的回调（为 null 时隐藏按钮）。
  final VoidCallback? onGenerateMusic;
  /// 是否正在生成音乐（显示 loading）。
  final bool isGenerating;

  const _LyricsPreview({
    required this.lyrics,
    this.onGenerateMusic,
    required this.isGenerating,
  });

  /// 构建歌词预览卡片。
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.accentSoft, AppTheme.sunSoft],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.accent),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题栏
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
            child: Row(
              children: [
                Icon(Icons.auto_awesome, color: AppTheme.accent, size: 18),
                const SizedBox(width: 6),
                Text(
                  '新歌词 · ${lyrics.style} · ${lyrics.mood}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.accentDeep,
                  ),
                ),
                const Spacer(),
                if (onGenerateMusic != null)
                  isGenerating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : IconButton(
                          icon: const Icon(Icons.play_circle_fill, color: AppTheme.sun),
                          iconSize: 28,
                          tooltip: '生成歌曲',
                          onPressed: onGenerateMusic,
                        ),
              ],
            ),
          ),

          // 歌词内容
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              lyrics.lyrics,
              style: const TextStyle(
                fontSize: 13,
                height: 1.8,
                color: AppTheme.fg2,
              ),
              maxLines: 8,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // 创作手记
          if (lyrics.note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Text('💡', style: TextStyle(fontSize: 14)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        lyrics.note,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.meta,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ).animate().slideY(begin: -0.2).fadeIn();
  }
}

// ═══════════════════════════════════════════════
// 音乐播放器（just_audio 0.9.46 流式 API；单 URL 播放/暂停/拖动进度）
// ═══════════════════════════════════════════════
/// 音乐播放器弹层（基于 just_audio 流式 API）。
class _MusicPlayer extends StatefulWidget {
  /// 可播放的绝对音频 URL（已含 baseUrl）。
  final String url;
  /// 兜底时长（秒），后端未返回时长时使用。
  final int duration;
  const _MusicPlayer({required this.url, required this.duration});

  @override
  State<_MusicPlayer> createState() => _MusicPlayerState();
}

/// 播放器状态：订阅 just_audio 的时长/进度/播放状态流，驱动 UI 与 seek。
class _MusicPlayerState extends State<_MusicPlayer> {
  final AudioPlayer _player = AudioPlayer(); // just_audio 播放器实例
  bool _isPlaying = false; // 当前是否正在播放
  Duration _position = Duration.zero; // 当前播放进度
  Duration _duration = Duration.zero; // 音频总时长（流更新）
  StreamSubscription<Duration>? _posSub; // 进度流订阅
  StreamSubscription<Duration?>? _durSub; // 时长流订阅
  StreamSubscription<PlayerState>? _stateSub; // 播放状态流订阅

  /// 订阅时长/进度/播放状态三个流，挂载时调用。
  @override
  void initState() {
    super.initState();
    _durSub = _player.durationStream.listen((d) {
      if (mounted) setState(() => _duration = d ?? Duration.zero);
    });
    _posSub = _player.positionStream.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _stateSub = _player.playerStateStream.listen((s) {
      if (mounted) setState(() => _isPlaying = s.playing);
    });
  }

  /// 取消流订阅并释放播放器。
  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  /// 播放/暂停切换：首次播放先 [AudioPlayer.setUrl] 再 play，失败静默。
  Future<void> _toggle() async {
    if (_isPlaying) {
      await _player.pause();
      return;
    }
    try {
      await _player.setUrl(widget.url);
      await _player.play();
      if (mounted) setState(() => _isPlaying = true);
    } catch (_) {
      if (mounted) setState(() => _isPlaying = false);
    }
  }

  /// 构建播放器弹层：播放/暂停按钮 + 进度条/时长。
  @override
  Widget build(BuildContext context) {
    final total = _duration.inSeconds > 0 ? _duration.inSeconds : widget.duration;
    final pos = _position.inSeconds;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🎵 歌曲生成完成', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                iconSize: 48,
                color: AppTheme.sun,
                icon: Icon(_isPlaying ? Icons.pause_circle : Icons.play_circle),
                onPressed: _toggle,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (total > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                children: [
                  Slider(
                    value: (pos / total).clamp(0.0, 1.0),
                    min: 0,
                    max: 1,
                    activeColor: AppTheme.sun,
                    inactiveColor: AppTheme.borderSoft,
                    onChanged: (v) async {
                      try {
                        await _player.seek(Duration(seconds: (v * total).toInt()));
                      } catch (_) {}
                    },
                  ),
                  Text('$pos / $total 秒', style: TextStyle(color: AppTheme.meta, fontSize: 12)),
                ],
              ),
            )
          else
            Text(
              '时长: ${widget.duration}秒',
              style: TextStyle(color: AppTheme.meta),
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// 对话气泡
// ═══════════════════════════════════════════════
/// 对话气泡：用户消息靠右（暖色），狗子消息靠左（白色），错误态淡红。
class _ChatBubble extends StatelessWidget {
  /// true=用户消息（靠右）。
  final bool isUser;
  /// 气泡文本。
  final String text;
  /// true=网络/业务错误态（淡红背景）。
  final bool isError;

  const _ChatBubble({
    required this.isUser,
    required this.text,
    this.isError = false,
  });

  /// 构建对话气泡。
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isUser
              ? AppTheme.sun
              : isError
                  ? AppTheme.danger.withValues(alpha: 0.08)
                  : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: isUser ? const Radius.circular(18) : Radius.zero,
            bottomRight: isUser ? Radius.zero : const Radius.circular(18),
          ),
          border: null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isUser ? 0.1 : 0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isUser) ...[
              const Text('🐕', style: TextStyle(fontSize: 14)),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 15,
                  color: isUser ? Colors.white : AppTheme.fg,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ).animate().fadeIn(duration: 200.ms).slideX(begin: isUser ? 0.2 : -0.2),
    );
  }
}

// ═══════════════════════════════════════════════
// 打字指示器
// ═══════════════════════════════════════════════
/// 狗子「正在输入」指示器：头像 + 跳动圆点。
class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  /// 构建「正在输入」指示器。
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomRight: Radius.circular(18),
          ),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🐕', style: TextStyle(fontSize: 14)),
            const SizedBox(width: 6),
            _DotBounce(),
          ],
        ),
      ),
    );
  }
}

/// 三个循环缩放的小圆点，构成打字指示器动画。
class _DotBounce extends StatelessWidget {
  /// 构建三个循环缩放的小圆点。
  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(3, (i) {
        return Container(
          margin: const EdgeInsets.only(right: 3),
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: AppTheme.meta,
            shape: BoxShape.circle,
          ),
        ).animate(onPlay: (c) => c.repeat())
          .scale(
            begin: const Offset(0.5, 0.5),
            end: const Offset(1.0, 1.0),
            duration: 600.ms,
            curve: Curves.easeInOut,
          )
          .then()
          .scale(
            begin: const Offset(1.0, 1.0),
            end: const Offset(0.5, 0.5),
            duration: 600.ms,
          );
      }),
    );
  }
}

// ═══════════════════════════════════════════════
// 空状态
// ═══════════════════════════════════════════════
/// 创作台空状态：大狗子 + 引导文案，点击快捷语触发 [onPromptTap]。
class _EmptyStudio extends StatelessWidget {
  /// 点击引导示例时回调（传入示例文案）。
  final void Function(String) onPromptTap;
  const _EmptyStudio({required this.onPromptTap});

  /// 构建空状态引导视图。
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '🐕',
            style: TextStyle(fontSize: 64, color: AppTheme.sunSoft),
          ),
          const SizedBox(height: 16),
          Text(
            '汪！主人，想创作什么歌？',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.meta,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '比如："帮我写首失恋的歌"\n或者："来一首民谣风格的歌"',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: AppTheme.muted,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// 歌词库（真实数据：后端 /lyrics 列表）
// ═══════════════════════════════════════════════
/// 歌词库 Tab：拉取后端 /lyrics 列表并展示（空态有引导）。
class _LyricsLibrary extends StatefulWidget {
  const _LyricsLibrary();

  @override
  State<_LyricsLibrary> createState() => _LyricsLibraryState();
}

/// 歌词库状态：加载并缓存歌词列表。
class _LyricsLibraryState extends State<_LyricsLibrary> {
  List<Map<String, dynamic>> _songs = []; // 歌词列表（后端返回的原始 Map）
  bool _loading = true; // 是否正在加载歌词列表

  /// 挂载即拉取歌词列表。
  @override
  void initState() {
    super.initState();
    _loadLyrics();
  }

  /// 拉取最近 50 条歌词；失败静默（保留空态），组件卸载则不更新。
  Future<void> _loadLyrics() async {
    try {
      final items = await BackendService.instance.listLyrics(limit: 50);
      if (!mounted) return;
      setState(() {
        _songs = items;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 构建歌词库列表或加载/空状态。
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_songs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('📝', style: TextStyle(fontSize: 56, color: AppTheme.sunSoft)),
            const SizedBox(height: 12),
            Text('还没有歌词', style: TextStyle(color: AppTheme.meta, fontSize: 16)),
            const SizedBox(height: 6),
            Text(
              '在「创作台」跟狗子说“帮我写首歌”吧',
              style: TextStyle(color: AppTheme.muted, fontSize: 13),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _songs.length,
      itemBuilder: (context, index) {
        final song = _songs[index];
        final title = (song['title'] as String?) ?? '无题';
        final tags = song['tags'];
        final style = (tags is List && tags.isNotEmpty) ? tags.first.toString() : '流行';
        final mood = (song['mood'] as String?) ?? '';
        final content = (song['content'] as String?) ?? '';
        final preview = content.split('\n').take(4).join('\n');
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Chip(
                      label: Text(style, style: const TextStyle(fontSize: 11)),
                      backgroundColor: AppTheme.accentSoft,
                      side: BorderSide(color: AppTheme.accent),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                    const SizedBox(width: 6),
                    if (mood.isNotEmpty)
                      Chip(
                        label: Text(mood, style: const TextStyle(fontSize: 11)),
                        backgroundColor: AppTheme.sunSoft,
                        side: BorderSide(color: AppTheme.sunSoft),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  preview,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.meta,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
        ).animate().fadeIn(delay: (index * 100).ms).slideX(begin: 0.1);
      },
    );
  }
}

// ═══════════════════════════════════════════════
// 单独宠物页面
// ═══════════════════════════════════════════════
/// 「宠物」Tab：单独展示可交互狗子，并把后端 mood 字符串映射成 [PetMood]。
class _PetAloneScreen extends StatelessWidget {
  /// 当前宠物状态（来自 petStateProvider）。
  final ZhuyPetState petState;
  const _PetAloneScreen({required this.petState});

  /// 构建「宠物」Tab：挂载可交互狗子并传入映射后的心情。
  @override
  Widget build(BuildContext context) {
    return ChattyDogPet(
      triggerMood: _stringToMood(petState.mood),
    );
  }

  /// 把后端 mood 字符串映射为 [PetMood] 枚举（未知值回退 happy）。
  PetMood _stringToMood(String mood) {
    switch (mood) {
      case 'excited': return PetMood.excited;
      case 'sleepy': return PetMood.sleepy;
      case 'hungry': return PetMood.hungry;
      case 'confused': return PetMood.confused;
      case 'angry': return PetMood.angry;
      default: return PetMood.happy;
    }
  }
}

// ═══════════════════════════════════════════════
// 扩展方法
// ═══════════════════════════════════════════════
/// 列表扩展：补一个「从后往前找首个匹配」的工具方法。
extension ListExtension<T> on List<T> {
  /// 从列表末尾向前返回首个满足 [test] 的元素，无则 null。
  T? lastWhereOrNull(bool Function(T) test) {
    for (var i = length - 1; i >= 0; i--) {
      if (test(this[i])) return this[i];
    }
    return null;
  }
}
