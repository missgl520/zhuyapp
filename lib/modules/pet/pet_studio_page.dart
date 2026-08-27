import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'chatty_dog_pet.dart';
import '../../services/pet_api_service.dart';

/// 宠物创作助手页面
/// 3D宠物 + 对话 + 歌词展示 + 音乐生成
class PetStudioPage extends StatefulWidget {
  const PetStudioPage({super.key});

  @override
  State<PetStudioPage> createState() => _PetStudioPageState();
}

class _PetStudioPageState extends State<PetStudioPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final PetApiService _api = PetApiService();
  PetState _petState = PetState(mood: 'happy', love: 50.0, totalBarks: 0, songsCreated: 0);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadPetState();
  }

  Future<void> _loadPetState() async {
    try {
      final state = await _api.getPetState();
      if (mounted) setState(() => _petState = state);
    } catch (e) {
      // 后端未启动时使用默认状态
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _api.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // 顶部宠物状态栏
          _PetStatusBar(state: _petState),

          // Tab: 创作台 / 歌词库 / 关于
          Container(
            color: const Color(0xFFFFF8F0),
            child: TabBar(
              controller: _tabController,
              labelColor: Colors.orange.shade700,
              unselectedLabelColor: Colors.grey,
              indicatorColor: Colors.orange,
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
                _CreationStudio(api: _api, petState: _petState),
                _LyricsLibrary(api: _api),
                _PetAloneScreen(petState: _petState, api: _api),
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
class _PetStatusBar extends StatelessWidget {
  final PetState state;
  const _PetStatusBar({required this.state});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.orange.shade100, Colors.orange.shade50],
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
              color: Colors.orange.shade800,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            PetState.moodEmojis[state.mood] ?? '😄',
            style: const TextStyle(fontSize: 16),
          ),
          const Spacer(),
          // 好感度
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.pink.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.pink.shade200),
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
                      backgroundColor: Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation(Colors.pink),
                      minHeight: 6,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '${state.love.toInt()}',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.pink.shade700,
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
class _CreationStudio extends StatefulWidget {
  final PetApiService api;
  final PetState petState;
  const _CreationStudio({required this.api, required this.petState});

  @override
  State<_CreationStudio> createState() => _CreationStudioState();
}

class _CreationStudioState extends State<_CreationStudio> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<_ChatBubble> _messages = [];
  bool _isLoading = false;

  // 歌词创作状态
  LyricsResult? _lastLyrics;
  MusicResult? _lastMusic;
  bool _isGeneratingMusic = false;

  // 异步创作状态
  String? _pendingTaskId;        // 当前进行中的任务 ID
  int _creationProgress = 0;      // 0-100
  String _creationMsg = '';        // 进度描述
  bool _isCreatingLyrics = false;  // 是否正在创作歌词

  // 快捷语
  static const _quickPrompts = [
    ('写首歌', '帮我写一首关于{}的歌曲'),
    ('治愈系', '我想听疗愈的歌'),
    ('热血', '来一首让人热血沸腾的歌'),
    ('失恋', '帮我写首失恋的歌'),
    ('民谣风', '写首民谣风格的歌'),
  ];

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
      final result = await widget.api.chat([
        ChatMessage(role: 'user', content: text),
      ]);

      if (!mounted) return;

      setState(() {
        _messages.add(_ChatBubble(isUser: false, text: result.reply));
        _isLoading = false;
      });

      // 如果有歌词创作意图，自动调用
      if (result.hasLyricsIntent) {
        final intent = result.lyricsIntent!;
        await _createLyrics(
          theme: intent['主题'] ?? intent['theme'] ?? '自由创作',
          style: intent['风格'] ?? intent['style'] ?? '流行',
          mood: intent['情绪'] ?? intent['mood'] ?? '欢快',
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
          text: '汪……网络出问题了，主人你再试一次？',
        ));
        _isLoading = false;
      });
    }
  }

  Future<void> _createLyrics({
    required String theme,
    required String style,
    required String mood,
  }) async {
    if (_isCreatingLyrics) return;
    setState(() {
      _isCreatingLyrics = true;
      _creationProgress = 0;
      _creationMsg = '汪！收到任务，开始创作...';
      _pendingTaskId = null;
    });

    try {
      // 发起异步任务
      final taskRef = await widget.api.createLyricsAsync(
        theme: theme,
        style: style,
        mood: mood,
        userMood: _detectUserMood(),
      );

      setState(() {
        _pendingTaskId = taskRef.taskId;
        _creationMsg = '创作进行中...';
      });

      // 轮询等待结果（每 1 秒）
      AsyncLyricsTask? task;
      do {
        await Future.delayed(const Duration(seconds: 1));
        task = await widget.api.getLyricsTask(taskRef.taskId);

        if (mounted) {
          setState(() {
            _creationProgress = task!.progress;
            _creationMsg = task.progressMsg ?? _creationMsg;
          });
        }
      } while (task != null && !task.isDone && !task.isFailed);

      if (!mounted) return;

      if (task!.isFailed) {
        setState(() {
          _messages.add(_ChatBubble(
            isUser: false,
            text: task.result?.petReaction ?? '汪呜...创作出了点问题，再试一次吧！',
          ));
          _isCreatingLyrics = false;
        });
      } else {
        // 创作成功，转成 LyricsResult 显示
        final result = task.result!;
        final lyricsResult = LyricsResult(
          lyrics: result.lyrics,
          note: result.note,
          theme: result.theme,
          style: result.style,
          mood: result.mood,
          petReaction: result.petReaction,
          createdAt: DateTime.now().toIso8601String(),
        );

        setState(() {
          _lastLyrics = lyricsResult;
          _messages.add(_ChatBubble(
            isUser: false,
            text: result.petReaction,
            isHighlight: true,
          ));
          _isCreatingLyrics = false;
          _pendingTaskId = null;
          _creationProgress = 100;
          _creationMsg = '完成！';
        });
      }

      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isCreatingLyrics = false;
        _pendingTaskId = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('歌词创作失败: $e')),
      );
    }
  }

  Future<void> _generateMusic({
    required String lyrics,
    required String prompt,
    required int duration,
  }) async {
    setState(() => _isGeneratingMusic = true);

    try {
      final result = await widget.api.generateMusic(
        lyrics: lyrics,
        prompt: prompt,
        duration: duration,
      );

      if (!mounted) return;

      setState(() {
        _lastMusic = result;
        _messages.add(_ChatBubble(
          isUser: false,
          text: result.petReaction,
          isHighlight: true,
        ));
        _isGeneratingMusic = false;
      });
      _scrollToBottom();

      if (result.audioUrl != null) {
        _showMusicPlayer(result.audioUrl!, result.duration);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isGeneratingMusic = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('音乐生成失败: $e')),
      );
    }
  }

  void _showMusicPlayer(String url, int duration) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.orange.shade50,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _MusicPlayer(url: url, duration: duration),
    );
  }

  String? _detectUserMood() {
    // 简单情绪检测
    final lastUserMsg = _messages.lastWhereOrNull((m) => m.isUser)?.text ?? '';
    if (lastUserMsg.contains(RegExp('难过|伤心|痛苦|分手|失去'))) return 'sad';
    if (lastUserMsg.contains(RegExp('开心|高兴|棒|酷'))) return 'happy';
    if (lastUserMsg.contains(RegExp('激动|热血|燃'))) return 'excited';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 歌词预览（正在创作 或 已完成）
        if (_lastLyrics != null || _isCreatingLyrics)
          _LyricsPreview(
            lyrics: _lastLyrics ?? LyricsResult(
              lyrics: '', note: '', theme: '', style: '', mood: '', petReaction: '', createdAt: '',
            ),
            onGenerateMusic: _lastMusic == null && !_isCreatingLyrics && _lastLyrics != null
                ? () => _generateMusic(
                      lyrics: _lastLyrics!.lyrics,
                      prompt: '${_lastLyrics!.style}风格',
                      duration: 30,
                    )
                : null,
            isGenerating: _isGeneratingMusic,
            isCreating: _isCreatingLyrics,
            creationProgress: _creationProgress,
            creationMsg: _creationMsg,
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
                backgroundColor: Colors.orange.shade50,
                side: BorderSide(color: Colors.orange.shade200),
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
                color: Colors.black.withOpacity(0.05),
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
                      fillColor: Colors.grey.shade100,
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
                Container(
                  decoration: BoxDecoration(
                    color: Colors.orange,
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
// 歌词预览卡片（支持创作进度动画）
// ═══════════════════════════════════════════════

class _LyricsPreview extends StatelessWidget {
  final LyricsResult lyrics;
  final VoidCallback? onGenerateMusic;
  final bool isGenerating;
  final bool isCreating;       // 是否正在创作
  final int creationProgress;  // 创作进度 0-100
  final String creationMsg;    // 创作状态描述

  const _LyricsPreview({
    required this.lyrics,
    this.onGenerateMusic,
    required this.isGenerating,
    this.isCreating = false,
    this.creationProgress = 0,
    this.creationMsg = '',
  });

  @override
  Widget build(BuildContext context) {
    if (isCreating) {
      return _CreatingProgressCard(progress: creationProgress, msg: creationMsg);
    }
    return _LyricsCard(lyrics: lyrics, onGenerateMusic: onGenerateMusic, isGenerating: isGenerating);
  }
}

// 创作进度动画
class _CreatingProgressCard extends StatelessWidget {
  final int progress;
  final String msg;

  const _CreatingProgressCard({required this.progress, required this.msg});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.orange.shade50, Colors.yellow.shade50],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                SizedBox(
                  width: 40,
                  height: 40,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: progress / 100,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation(Colors.orange),
                        strokeWidth: 3,
                      ),
                      Text('$progress%', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text('🐕', style: TextStyle(fontSize: 16)),
                          const SizedBox(width: 6),
                          Text('狗子正在创作...',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.orange.shade700)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(msg, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress / 100,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation(Colors.orange),
                minHeight: 6,
              ),
            ),
          ],
        ),
      ),
    ).animate().slideY(begin: -0.1).fadeIn();
  }
}

// 歌词卡片（已完成创作时显示）
class _LyricsCard extends StatelessWidget {
  final LyricsResult lyrics;
  final VoidCallback? onGenerateMusic;
  final bool isGenerating;

  const _LyricsCard({required this.lyrics, this.onGenerateMusic, required this.isGenerating});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF3E8FF), Color(0xFFFFF0F6)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.purple.shade200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 标题栏
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
          child: Row(
            children: [
              Icon(Icons.auto_awesome, color: Colors.purple.shade400, size: 18),
              const SizedBox(width: 6),
              Text('新歌词 · ${lyrics.style} · ${lyrics.mood}',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.purple.shade700)),
              const Spacer(),
              if (onGenerateMusic != null)
                isGenerating
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : IconButton(icon: const Icon(Icons.play_circle_fill, color: Colors.orange), iconSize: 28,
                      tooltip: '生成歌曲', onPressed: onGenerateMusic),
            ],
          ),
        ),
        // 歌词内容
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(lyrics.lyrics, style: const TextStyle(fontSize: 13, height: 1.8, color: Color(0xFF333333)),
            maxLines: 8, overflow: TextOverflow.ellipsis),
        ),
        // 创作手记
        if (lyrics.note.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.7), borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                const Text('💡', style: TextStyle(fontSize: 14)),
                const SizedBox(width: 6),
                Expanded(child: Text(lyrics.note, style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontStyle: FontStyle.italic))),
              ]),
            ),
          ),
      ]),
    ).animate().slideY(begin: -0.2).fadeIn();
  }
}


// ═══════════════════════════════════════════════
// 音乐播放器
// ═══════════════════════════════════════════════
class _MusicPlayer extends StatefulWidget {
  final String url;
  final int duration;
  const _MusicPlayer({required this.url, required this.duration});

  @override
  State<_MusicPlayer> createState() => _MusicPlayerState();
}

class _MusicPlayerState extends State<_MusicPlayer> {
  bool _isPlaying = false;

  @override
  Widget build(BuildContext context) {
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
                color: Colors.orange,
                icon: Icon(_isPlaying ? Icons.pause_circle : Icons.play_circle),
                onPressed: () => setState(() => _isPlaying = !_isPlaying),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '时长: ${widget.duration}秒',
            style: TextStyle(color: Colors.grey.shade600),
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
class _ChatBubble extends StatelessWidget {
  final bool isUser;
  final String text;
  final bool isHighlight;

  const _ChatBubble({
    required this.isUser,
    required this.text,
    this.isHighlight = false,
  });

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
              ? Colors.orange
              : isHighlight
                  ? Colors.purple.shade50
                  : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: isUser ? const Radius.circular(18) : Radius.zero,
            bottomRight: isUser ? Radius.zero : const Radius.circular(18),
          ),
          border: isHighlight ? Border.all(color: Colors.purple.shade200) : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isUser ? 0.1 : 0.05),
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
                  color: isUser ? Colors.white : Colors.black87,
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
class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

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
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4),
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

class _DotBounce extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(3, (i) {
        return Container(
          margin: const EdgeInsets.only(right: 3),
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: Colors.grey.shade400,
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
class _EmptyStudio extends StatelessWidget {
  final void Function(String) onPromptTap;
  const _EmptyStudio({required this.onPromptTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '🐕',
            style: TextStyle(fontSize: 64, color: Colors.orange.shade200),
          ),
          const SizedBox(height: 16),
          Text(
            '汪！主人，想创作什么歌？',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '比如："帮我写首失恋的歌"\n或者："来一首民谣风格的歌"',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade500,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// 歌词库
// ═══════════════════════════════════════════════
class _LyricsLibrary extends StatelessWidget {
  final PetApiService api;
  const _LyricsLibrary({required this.api});

  static const _demoSongs = [
    {
      'title': '心被狗吃了',
      'style': '民谣',
      'mood': '治愈',
      'preview': '路灯拉长了影子\n我在街头数着步子\n你走后世界安静了\n只剩心跳的声音',
    },
    {
      'title': '少年追光',
      'style': '流行',
      'mood': '热血',
      'preview': '逆风的方向\n更适合飞翔\n我不怕万人阻挡\n只怕自己投降',
    },
    {
      'title': '午夜电波',
      'style': 'DJ电音',
      'mood': '欢快',
      'preview': 'Drop the beat now!\n霓虹灯闪烁\n在午夜街头\n我们是最自由的灵魂',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _demoSongs.length,
      itemBuilder: (context, index) {
        final song = _demoSongs[index];
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
                        song['title']!,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Chip(
                      label: Text(song['style']!, style: const TextStyle(fontSize: 11)),
                      backgroundColor: Colors.purple.shade50,
                      side: BorderSide(color: Colors.purple.shade200),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                    const SizedBox(width: 6),
                    Chip(
                      label: Text(song['mood']!, style: const TextStyle(fontSize: 11)),
                      backgroundColor: Colors.orange.shade50,
                      side: BorderSide(color: Colors.orange.shade200),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  song['preview']!,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.play_arrow, color: Colors.grey.shade400, size: 20),
                    const SizedBox(width: 4),
                    Text('播放', style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
                    const SizedBox(width: 16),
                    Icon(Icons.edit, color: Colors.grey.shade400, size: 20),
                    const SizedBox(width: 4),
                    Text('编辑', style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
                    const SizedBox(width: 16),
                    Icon(Icons.share, color: Colors.grey.shade400, size: 20),
                    const SizedBox(width: 4),
                    Text('分享', style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
                  ],
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
class _PetAloneScreen extends StatelessWidget {
  final PetState petState;
  final PetApiService api;
  const _PetAloneScreen({required this.petState, required this.api});

  @override
  Widget build(BuildContext context) {
    return ChattyDogPet(
      triggerMood: _stringToMood(petState.mood),
    );
  }

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
extension ListExtension<T> on List<T> {
  T? get lastWhereOrNull(bool Function(T) test) {
    for (var i = length - 1; i >= 0; i--) {
      if (test(this[i])) return this[i];
    }
    return null;
  }
}
