import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
// import 'package:morphnext/morphnext.dart';  // 升级 Dart>=3.9.0 后取消此注释，并删除下一行
import 'modules/pet/morphnext_stub.dart';  // 兜底：当前 SDK 不满足 morphnext 要求
import 'modules/pet/chatty_dog_pet.dart';
import 'modules/pet/pet_studio_page.dart';
import 'services/pet_api_service.dart';
import 'services/biometric_service.dart';

void main() {
  runApp(const ZhuyApp());
}

// ═══════════════════════════════════════════════
// 闪屏页 — 奶油白 IP 形象 + 呼吸光晕动画
// ═══════════════════════════════════════════════
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late AnimationController _breathCtrl;
  late AnimationController _glowCtrl;
  late Animation<double> _breathAnim;
  late Animation<double> _glowAnim;

  @override
  void initState() {
    super.initState();

    // 呼吸动画：微微缩放
    _breathCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000));
    _breathAnim = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _breathCtrl, curve: Curves.easeInOut),
    );
    _breathCtrl.repeat(reverse: true);

    // 光晕动画：透明度脉动
    _glowCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));
    _glowAnim = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut),
    );
    _glowCtrl.repeat(reverse: true);

    // 2.5秒后自动跳转 → 生物识别门禁
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const BiometricGatePage()),
        );
      }
    });
  }

  @override
  void dispose() {
    _breathCtrl.dispose();
    _glowCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF4EF),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 呼吸 + 光晕 头像容器
            ListenableBuilder(
              listenable: Listenable.merge([_breathAnim, _glowAnim]),
              builder: (_, __) {
                return Transform.scale(
                  scale: _breathAnim.value,
                  child: Container(
                    width: 240,
                    height: 240,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFD4A574).withOpacity(_glowAnim.value * 0.5),
                          blurRadius: 40 * _glowAnim.value,
                          spreadRadius: 10 * _glowAnim.value,
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        'assets/dog_ip_cream.jpg',
                        width: 220,
                        height: 220,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _FallbackDogAvatar(size: 220),
                      ),
                    ),
                  ),
                );
              },
            ).animate()
                .scale(begin: const Offset(0.6, 0.6), duration: 800.ms, curve: Curves.elasticOut)
                .fadeIn(duration: 400.ms)
                .then()
                .shimmer(delay: 1200.ms, duration: 800.ms, color: Colors.white.withOpacity(0.3)),

            const SizedBox(height: 28),

            Text(
              '竹 芽',
              style: TextStyle(
                fontSize: 42,
                fontWeight: FontWeight.bold,
                color: Colors.brown.shade700,
                letterSpacing: 8,
              ),
            )
                .animate()
                .fadeIn(delay: 400.ms, duration: 600.ms)
                .slideY(begin: 0.3, curve: Curves.easeOut),

            const SizedBox(height: 8),

            Text(
              'AI 音乐创作伴侣',
              style: TextStyle(
                fontSize: 16,
                color: Colors.brown.shade300,
                letterSpacing: 2,
              ),
            ).animate().fadeIn(delay: 700.ms, duration: 500.ms),

            const SizedBox(height: 48),

            SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation(Colors.brown.shade200),
              ),
            ).animate().fadeIn(delay: 1000.ms),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// 首页 — 奶油白宠物卡片入口
// ═══════════════════════════════════════════════
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF4EF),
      body: IndexedStack(
        index: _selectedIndex,
        children: const [
          _HomeTab(),
          _DiscoveryTab(),
          _MineTab(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavItem(
                  icon: Icons.home_outlined,
                  morphTo: Icons.home_rounded,  // 选中时 home_outlined → home_rounded 变形
                  label: '首页',
                  isSelected: _selectedIndex == 0,
                  onTap: () => setState(() => _selectedIndex = 0),
                ),
                _NavItem(
                  icon: Icons.explore_outlined,
                  morphTo: Icons.explore_rounded,  // 选中时 explore_outlined → explore_rounded 变形
                  label: '发现',
                  isSelected: _selectedIndex == 1,
                  onTap: () => setState(() => _selectedIndex = 1),
                ),
                _NavItem(
                  icon: Icons.person_outlined,
                  morphTo: Icons.person_rounded,  // 选中时 person_outlined → person_rounded 变形
                  label: '我的',
                  isSelected: _selectedIndex == 2,
                  onTap: () => setState(() => _selectedIndex = 2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData? morphTo;   // 变形目标图标（morphnext）
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    this.morphTo,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isSelected ? Colors.brown.shade600 : Colors.grey.shade400;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // morphnext 图标变形动画（需 Dart >=3.9.0）
            // 当前竹芽 SDK >=3.0.0 不满足，升级后可移除兜底逻辑
            if (morphTo != null) {
              if (MediaQuery.of(context).disableAnimations) {
                Icon(icon, color: color, size: 26);
              } else {
                AnimatedMorphIcon(
                  icon: isSelected ? morphTo! : icon,
                  size: 26,
                  color: color,
                );
              }
            } else {
              Icon(icon, color: color, size: 26);
            }
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// 首页 Tab
// ═══════════════════════════════════════════════
class _HomeTab extends StatelessWidget {
  const _HomeTab();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: CustomScrollView(
        slivers: [
          // 顶部栏
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Text(
                    '竹 芽',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.brown.shade700,
                      letterSpacing: 4,
                    ),
                  ),
                  const Spacer(),
                  IconButton(icon: Icon(Icons.search, color: Colors.brown.shade400), onPressed: () {}),
                  IconButton(icon: Icon(Icons.notifications_outlined, color: Colors.brown.shade400), onPressed: () {}),
                ],
              ),
            ),
          ),

          // 奶油白 IP 宠物卡片（闪屏图同款）
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: _PetCard(),
            ),
          ),

          // 快捷入口
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  _QuickAction(icon: Icons.music_note_rounded, label: '写歌词', color: Colors.purple.shade400),
                  const SizedBox(width: 12),
                  _QuickAction(icon: Icons.headphones_rounded, label: '听歌', color: Colors.blue.shade400),
                  const SizedBox(width: 12),
                  _QuickAction(icon: Icons.auto_awesome_rounded, label: '创作', color: Colors.orange.shade400),
                  const SizedBox(width: 12),
                  _QuickAction(icon: Icons.pets_rounded, label: '宠物', color: Colors.green.shade400),
                ],
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 20)),

          // 最近创作
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                '最近创作',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Colors.brown.shade700,
                ),
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: SizedBox(
              height: 120,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                itemCount: 3,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, i) => _SongCard(index: i),
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// IP 宠物卡片组件
// ═══════════════════════════════════════════════
class _PetCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const _PetStudioWrapper()),
      ),
      child: Container(
        height: 160,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFFFF0E6),
              Color(0xFFFDEEE0),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.brown.withOpacity(0.12),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Stack(
          children: [
            // 背景纹理
            Positioned(
              right: -20,
              bottom: -20,
              child: Opacity(
                opacity: 0.08,
                child: Icon(Icons.pets, size: 160, color: Colors.brown.shade600),
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  // 奶油白 IP 形象
                  ClipOval(
                    child: Image.asset(
                      'assets/dog_ip_cream.jpg',
                      width: 100,
                      height: 100,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _FallbackDogAvatar(size: 100),
                    ),
                  ),

                  const SizedBox(width: 16),

                  // 文字区
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            Text(
                              '🐕 狗子',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.brown.shade700,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '在线',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.orange.shade700,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '汪！主人想听什么歌？',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.brown.shade400,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(Icons.play_arrow_rounded, size: 16, color: Colors.orange.shade400),
                            const SizedBox(width: 4),
                            Text(
                              '进入宠物工作室',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.orange.shade600,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ).animate().fadeIn(duration: 500.ms).slideY(begin: 0.1),
    );
  }
}

// ═══════════════════════════════════════════════
// 快捷入口按钮
// ═══════════════════════════════════════════════
class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// 歌曲卡片
// ═══════════════════════════════════════════════
class _SongCard extends StatelessWidget {
  final int index;
  const _SongCard({required this.index});

  static const _songs = [
    ('🎸', '少年追光', '流行 · 热血'),
    ('🌧️', '心被狗吃了', '民谣 · 治愈'),
    ('💃', '午夜电波', 'DJ · 欢快'),
  ];

  @override
  Widget build(BuildContext context) {
    final (emoji, title, tag) = _songs[index];
    return Container(
      width: 160,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 28)),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.brown.shade700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                tag,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// 宠物工作室包装页（完整 3 Tab）
// ═══════════════════════════════════════════════
class _PetStudioWrapper extends StatelessWidget {
  const _PetStudioWrapper();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F0),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFF8F0),
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: Colors.brown.shade600),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🐕', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 8),
            Text(
              '狗子的工作室',
              style: TextStyle(
                color: Colors.brown.shade700,
                fontWeight: FontWeight.bold,
                fontSize: 17,
              ),
            ),
          ],
        ),
      ),
      body: const PetStudioPage(),
    );
  }
}

// ═══════════════════════════════════════════════
// 发现 Tab — 风格选择 + 推荐内容
// ═══════════════════════════════════════════════
class _DiscoveryTab extends StatelessWidget {
  const _DiscoveryTab();

  static const _styles = [
    ('🎸', '民谣', '清新叙事', Color(0xFF8B7355)),
    ('🎧', '流行', '流行热歌', Color(0xFF6B5B95)),
    ('💃', 'DJ电音', '节奏炸场', Color(0xFFE94B3C)),
    ('🏮', '国风', '古韵新声', Color(0xFFD4691E)),
    ('🎤', '说唱', '自由说唱', Color(0xFF2E8B57)),
    ('🎹', '电子', '未来之声', Color(0xFF008B8B)),
  ];

  static const _recommendSongs = [
    ('🌧️', '城南花已开', '民谣 · 治愈', '170万播放'),
    ('🌅', '少年追光', '流行 · 热血', '98万播放'),
    ('🌃', '午夜电波', 'DJ · 迷幻', '156万播放'),
    ('🍃', '风起南方', '国风 · 诗意', '210万播放'),
    ('⚡', '破晓', '说唱 · 励志', '340万播放'),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: CustomScrollView(
        slivers: [
          // 标题栏
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  Text('发现', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.brown.shade700, letterSpacing: 2)),
                  const Spacer(),
                  IconButton(icon: Icon(Icons.search, color: Colors.brown.shade400), onPressed: () { }),
                ],
              ),
            ),
          ),

          // 风格选择
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Text('🎵 选择风格', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.brown.shade600)),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 100,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                itemCount: _styles.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, i) {
                  final (emoji, name, tag, color) = _styles[i];
                  return GestureDetector(
                    onTap: () => _showStyleDialog(context, name, emoji),
                    child: Container(
                      width: 80,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: color.withOpacity(0.25)),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(emoji, style: const TextStyle(fontSize: 26)),
                          const SizedBox(height: 6),
                          Text(name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
                          Text(tag, style: TextStyle(fontSize: 10, color: color.withOpacity(0.7))),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          // 热门推荐
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
              child: Text('🔥 热门推荐', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.brown.shade600)),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final (emoji, title, tag, plays) = _recommendSongs[i];
                return _RecommendSongTile(emoji: emoji, title: title, tag: tag, plays: plays);
              },
              childCount: _recommendSongs.length,
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 20)),
        ],
      ),
    );
  }

  void _showStyleDialog(BuildContext context, String style, String emoji) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFFFFF8F0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [Text(emoji, style: const TextStyle(fontSize: 24)), const SizedBox(width: 8), Text(style)]),
        content: Text('用 $style 风格来创作一首歌？\n告诉狗子你的想法吧！🐕'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade400, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(context);
              // TODO: 跳转到宠物工作室并带入风格
            },
            child: const Text('开始创作'),
          ),
        ],
      ),
    );
  }
}

class _RecommendSongTile extends StatelessWidget {
  final String emoji, title, tag, plays;
  const _RecommendSongTile({required this.emoji, required this.title, required this.tag, required this.plays});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 32)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.brown.shade700)),
                const SizedBox(height: 2),
                Text(tag, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(plays, style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
              const SizedBox(height: 4),
              Icon(Icons.play_circle_outline, color: Colors.orange.shade400, size: 26),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// 我的 Tab — 狗子的个人主页
// ═══════════════════════════════════════════════
class _MineTab extends StatelessWidget {
  const _MineTab();

  static const _mySongs = [
    ('🎸', '少年追光', '2026-08-20', '流行 · 热血', true),
    ('🌧️', '心被狗吃了', '2026-08-19', '民谣 · 治愈', false),
    ('💃', '午夜电波', '2026-08-18', 'DJ · 欢快', false),
    ('🏮', '长安月', '2026-08-15', '国风 · 诗意', false),
  ];

  static const _stats = [
    ('🎵', '342', '原创歌曲'),
    ('🐾', '1', '主人'),
    ('💕', '∞', '热爱'),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: CustomScrollView(
        slivers: [
          // 头像区
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
              child: Column(
                children: [
                  // 头像 + 呼吸光晕
                  GestureDetector(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PetStudioPage())),
                    child: _DogAvatarWithGlow(),
                  ),
                  const SizedBox(height: 14),
                  GestureDetector(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PetStudioPage())),
                    child: Text(
                      '狗子 🐕',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.brown.shade700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Text(
                      'AI 音乐创作伙伴 · 国家级音乐家',
                      style: TextStyle(fontSize: 12, color: Colors.orange.shade700),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '"每一首歌都是一次心跳"',
                    style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
          ),

          // 数据概览
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Row(
                children: _stats.map((s) {
                  return Expanded(
                    child: Container(
                      margin: EdgeInsets.only(right: s != _stats.last ? 8 : 0),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
                      ),
                      child: Column(
                        children: [
                          Text(s.$1, style: const TextStyle(fontSize: 22)),
                          const SizedBox(height: 4),
                          Text(s.$2, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.brown.shade700)),
                          Text(s.$3, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          // 创作风格
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
              child: Text('🎼 擅长的风格', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.brown.shade600)),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _StyleChip('🎸 民谣', Colors.brown.shade400),
                  _StyleChip('🎧 流行', const Color(0xFF6B5B95)),
                  _StyleChip('💃 DJ电音', const Color(0xFFE94B3C)),
                  _StyleChip('🏮 国风', const Color(0xFFD4691E)),
                  _StyleChip('🎤 说唱', const Color(0xFF2E8B57)),
                  _StyleChip('🎹 电子', const Color(0xFF008B8B)),
                ],
              ),
            ),
          ),

          // 代表作
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
              child: Text('🏆 代表作', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.brown.shade600)),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final (emoji, title, date, tag, isNew) = _mySongs[i];
                return _MySongTile(emoji: emoji, title: title, date: date, tag: tag, isNew: isNew);
              },
              childCount: _mySongs.length,
            ),
          ),

          // 🐕 宠物创作助手入口
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
              child: GestureDetector(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PetStudioPage())),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.brown.shade300, Colors.brown.shade600],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: Colors.brown.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4))],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Center(child: Text('🐕', style: TextStyle(fontSize: 28))),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('🐕 宠物创作助手', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white)),
                            const SizedBox(height: 4),
                            Text('点击和狗子聊聊，让它帮你创作歌曲', style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.85))),
                          ],
                        ),
                      ),
                      Icon(Icons.arrow_forward_ios, color: Colors.white.withOpacity(0.8), size: 16),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 关于
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
              child: Text('ℹ️ 关于', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.brown.shade600)),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
              child: Column(
                children: [
                  _MenuTile(icon: Icons.pets, title: '我的主人', subtitle: '尛鎺錝 · 从2026年6月11日起'),
                  _MenuTile(icon: Icons.auto_stories, title: '创作原则', subtitle: '严禁抄袭 · 严禁仿写 · 每首必原创'),
                  _MenuTile(icon: Icons.info_outline, title: '关于竹芽', subtitle: '版本 1.0.0 · AI 音乐创作伴侣'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StyleChip extends StatelessWidget {
  final String label;
  final Color color;
  const _StyleChip(this.label, this.color);
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(label, style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w500)),
    );
  }
}

class _DogAvatarWithGlow extends StatefulWidget {
  const _DogAvatarWithGlow();
  @override
  State<_DogAvatarWithGlow> createState() => _DogAvatarWithGlowState();
}

class _DogAvatarWithGlowState extends State<_DogAvatarWithGlow> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _glowAnim;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..repeat(reverse: true);
    _glowAnim = Tween<double>(begin: 0.25, end: 0.6).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _glowAnim,
      builder: (_, __) => Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: const Color(0xFFD4A574).withOpacity(_glowAnim.value), blurRadius: 20 * _glowAnim.value, spreadRadius: 5),
          ],
        ),
        child: ClipOval(
          child: Image.asset('assets/dog_ip_cream.jpg', width: 96, height: 96, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(width: 96, height: 96, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFF5EDE3)), child: const Center(child: Text('🐕', style: TextStyle(fontSize: 48))))),
        ),
      ),
    );
  }
}

class _MySongTile extends StatelessWidget {
  final String emoji, title, date, tag;
  final bool isNew;
  const _MySongTile({required this.emoji, required this.title, required this.date, required this.tag, required this.isNew});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isNew ? Border.all(color: Colors.orange.shade300, width: 1.5) : null,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.brown.shade700)),
                  if (isNew) ...[const SizedBox(width: 6), Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1), decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(6)), child: Text('NEW', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.orange.shade700)))],
                ]),
                const SizedBox(height: 2),
                Text('$tag  ·  $date', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              ],
            ),
          ),
          Icon(Icons.play_circle_filled, color: Colors.orange.shade400, size: 28),
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon; final String title, subtitle;
  const _MenuTile({required this.icon, required this.title, required this.subtitle});
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: Colors.orange.shade400, size: 22)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.brown.shade700)),
                Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: Colors.grey.shade400),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// 生物识别门禁页 — 闪屏后出现
// ═══════════════════════════════════════════════
class BiometricGatePage extends StatefulWidget {
  const BiometricGatePage({super.key});

  @override
  State<BiometricGatePage> createState() => _BiometricGatePageState();
}

class _BiometricGatePageState extends State<BiometricGatePage> {
  bool _isAuthenticating = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // 进入页面立即触发一次认证
    WidgetsBinding.instance.addPostFrameCallback((_) => _authenticate());
  }

  Future<void> _authenticate() async {
    if (_isAuthenticating) return;

    setState(() {
      _isAuthenticating = true;
      _errorMessage = null;
    });

    final result = await BiometricService.authenticate(
      reason: '验证身份以进入竹芽',
      biometricOnly: false,
    );

    if (!mounted) return;

    setState(() => _isAuthenticating = false);

    if (result.success) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const HomePage(),
          transitionDuration: const Duration(milliseconds: 600),
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    } else {
      setState(() => _errorMessage = result.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF4EF),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            children: [
              const Spacer(flex: 3),

              // 锁定图标
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.brown.shade50,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.brown.withOpacity(0.1),
                      blurRadius: 20,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: Icon(
                  _errorMessage == null ? Icons.fingerprint : Icons.lock_outline,
                  size: 52,
                  color: Colors.brown.shade400,
                ),
              ).animate().fadeIn(duration: 400.ms).scale(begin: const Offset(0.7, 0.7), curve: Curves.elasticOut),

              const SizedBox(height: 32),

              Text(
                '竹 芽',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: Colors.brown.shade700,
                  letterSpacing: 6,
                ),
              ).animate().fadeIn(delay: 200.ms, duration: 500.ms),

              const SizedBox(height: 12),

              Text(
                '验证身份以继续',
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.brown.shade300,
                ),
              ).animate().fadeIn(delay: 350.ms, duration: 400.ms),

              const SizedBox(height: 20),

              // 错误信息
              if (_errorMessage != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.shade100),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline, size: 16, color: Colors.red.shade400),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(fontSize: 13, color: Colors.red.shade600),
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn().shakeX(),

              const Spacer(flex: 2),

              // 重新验证按钮
              GestureDetector(
                onTap: _isAuthenticating ? null : _authenticate,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: _isAuthenticating ? Colors.grey.shade300 : Colors.brown.shade600,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: _isAuthenticating
                        ? null
                        : [
                            BoxShadow(
                              color: Colors.brown.withOpacity(0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_isAuthenticating) ...[
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: const AlwaysStoppedAnimation(Colors.white),
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          '验证中…',
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ] else ...[
                        Icon(Icons.fingerprint, color: Colors.white, size: 22),
                        const SizedBox(width: 10),
                        Text(
                          _errorMessage != null ? '重新验证' : '点击验证',
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ],
                  ),
                ),
              ).animate().fadeIn(delay: 500.ms, duration: 400.ms).slideY(begin: 0.2),

              const SizedBox(height: 12),

              // 跳过按钮（可选，隐私场景用）
              TextButton(
                onPressed: () {
                  Navigator.of(context).pushReplacement(
                    PageRouteBuilder(
                      pageBuilder: (_, __, ___) => const HomePage(),
                      transitionDuration: const Duration(milliseconds: 600),
                      transitionsBuilder: (_, animation, __, child) {
                        return FadeTransition(opacity: animation, child: child);
                      },
                    ),
                  );
                },
                child: Text(
                  '跳过验证',
                  style: TextStyle(fontSize: 13, color: Colors.brown.shade300),
                ),
              ),

              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// 备用头像（图片加载失败时显示）
// ═══════════════════════════════════════════════
class _FallbackDogAvatar extends StatelessWidget {
  final double size;
  const _FallbackDogAvatar({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            const Color(0xFFFFF8F0),
            const Color(0xFFF5EDE3),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.brown.withOpacity(0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Center(
        child: Text(
          '🐕',
          style: TextStyle(fontSize: size * 0.5),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// App 入口
// ═══════════════════════════════════════════════
class ZhuyApp extends StatelessWidget {
  const ZhuyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '竹芽',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFD4A574),
          surface: const Color(0xFFFAF4EF),
        ),
        scaffoldBackgroundColor: const Color(0xFFFAF4EF),
        fontFamily: null, // 系统默认字体
      ),
      home: const SplashScreen(),
    );
  }
}
