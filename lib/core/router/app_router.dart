// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// 路由配置（GoRouter）
//
// 声明式路由：路径 → 页面
//
// 路由列表（对齐 zhuyapp-design-2.0.md）：
//   /        → 启动页（SplashPage，2.5s 后自动跳转 /chat）
//   /chat    → 对话页（ChatPage），带淡入+上滑过渡动画
//
// 上游：main.dart（ref.watch(routerProvider) 注入 MaterialApp.router）。
// 下游：pages/* 与 features/music_dog/pet/pet_studio_page.dart 各页面 Widget。
//
// 关键点：
//   1. 全 App 只有一个 GoRouter 实例，页面跳转统一用 context.go/push，
//      禁止再自建 MaterialApp 或 Navigator.push，否则返回栈会割裂。
//   2. /legal 与 /info 通过 query 参数 type 区分子页面，
//      新增子类型时无需加路由。
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../pages/splash/splash_page.dart';
import '../../pages/chat/chat_page.dart';
import '../../pages/settings/memory_history_page.dart';
import '../../pages/settings/settings_page.dart';
import '../../pages/voice/voice_call_page.dart';
import '../../pages/legal/legal_page.dart';
import '../../pages/settings/info_modules_page.dart';
import '../../pages/avatar/avatar_fullscreen_page.dart';
import '../../pages/discover/discover_page.dart';
import '../../pages/profile/profile_page.dart';
// Phase 1 新增页面
import '../../pages/pet/pet_page.dart';
import '../../pages/pet/pet_fullscreen_page.dart';
import '../../pages/pet/pet_library_page.dart';
// 本次合并新增：音乐狗子创作台
import '../../features/music_dog/pet/pet_studio_page.dart';

/// GoRouter 实例 Provider
/// main.dart 用 ref.watch(routerProvider) 注入到 MaterialApp.router
///
/// 全 App 唯一路由表；新增页面时在此追加 GoRoute，不要另建导航栈。
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      // 启动页：/ → SplashPage → 2.5s 后 context.go('/chat')
      GoRoute(
        path: '/',
        name: 'splash',
        builder: (context, state) => const SplashPage(),
      ),

      // 对话页：自定义过渡动画（淡入 + 微微上滑）
      GoRoute(
        path: '/chat',
        name: 'chat',
        pageBuilder: (context, state) => CustomTransitionPage(
          child: const ChatPage(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position:
                    Tween<Offset>(
                      begin: const Offset(0, 0.1),
                      end: Offset.zero,
                    ).animate(
                      CurvedAnimation(parent: animation, curve: Curves.easeOut),
                    ),
                child: child,
              ),
            );
          },
        ),
      ),
      // 实时语音通话页（全屏覆盖）
      GoRoute(
        path: '/voice-call',
        name: 'voice-call',
        builder: (context, state) => const VoiceCallPage(),
      ),
      // 记忆历史页
      GoRoute(
        path: '/memory-history',
        name: 'memory-history',
        builder: (context, state) => const MemoryHistoryPage(),
      ),
      // 法律文档页（隐私政策 / 用户协议）
      GoRoute(
        path: '/legal',
        name: 'legal',
        builder: (context, state) {
          final type = state.uri.queryParameters['type'] ?? 'privacy';
          return LegalPage(type: type);
        },
      ),
      // 信息模块页（个人信息收集 / 第三方共享 / 版本介绍）
      GoRoute(
        path: '/info',
        name: 'info',
        builder: (context, state) {
          final type = state.uri.queryParameters['type'] ?? 'version-intro';
          return InfoModulesPage(type: type);
        },
      ),

      // 设置页（后端地址 / 情感角色 / 唤醒词 / 清除记忆）
      GoRoute(
        path: '/settings',
        name: 'settings',
        builder: (context, state) => const SettingsPage(),
      ),
      // 3D 角色独立全屏页（二级程序：把「狗子」放在独立全屏查看）
      GoRoute(
        path: '/avatar',
        name: 'avatar',
        builder: (context, state) => const AvatarFullscreenPage(),
      ),

      // 首页 · 竹笌聊天唤醒陪伴（聊天页带 3D 竹笌角色）
      GoRoute(
        path: '/home',
        name: 'home',
        builder: (context, state) => const ChatPage(),
      ),

      // 发现页 · 竹林一角（图 2 场景：浅绿背景 + 装饰竹柱 + 左下角小竹笌吉祥物）
      GoRoute(
        path: '/discover',
        name: 'discover',
        builder: (context, state) => const DiscoverPage(),
      ),

      // 我的页（通用：设置 / 记忆 / 隐私等）
      GoRoute(
        path: '/profile',
        name: 'profile',
        builder: (context, state) => const ProfilePage(),
      ),

      // ════════════════════════════════════════════════════
      // Phase 1 新增：音乐狗子 × 音乐创作
      // ════════════════════════════════════════════════════

      // 音乐狗子主页（状态展示 + 交互按钮 + 音乐创作入口）
      GoRoute(
        path: '/pet',
        name: 'pet',
        builder: (context, state) => const PetPage(),
      ),

      // 音乐狗子全屏页（独立全屏查看角色 + 详细状态）
      GoRoute(
        path: '/pet/full',
        name: 'pet-full',
        builder: (context, state) => const PetFullscreenPage(),
      ),

      // 音乐库（歌词库 + 歌曲库 + 生成历史）
      GoRoute(
        path: '/pet/library',
        name: 'pet-library',
        builder: (context, state) => const PetLibraryPage(),
      ),

      // 音乐狗子创作台（本次合并新增路由；Phase 5 挂载真实 PetStudioPage）
      // 约束：仅新增，不改动现有 13 条路由与页面；禁止新增 MaterialApp / Navigator.push
      GoRoute(
        path: '/pet/studio',
        name: 'pet-studio',
        builder: (context, state) => const PetStudioPage(),
      ),
    ],
  );
});
