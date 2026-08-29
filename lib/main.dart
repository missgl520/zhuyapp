// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// 竹笌 App - 主入口
// 负责：Hive 初始化 → 全局 ProviderScope → MaterialApp.router
// 路径：lib/main.dart
//
// 职责：完成启动期的一系列全局初始化，然后挂载根 Widget。
//
// 上游：Flutter 引擎（dart:ui 入口）。
// 下游：BackendConfig（后端地址）、SyncEngine（离线补发）、
//       AppRouter（路由）、AppTheme（主题）、Hive（本地 KV）。
//
// 关键点：
//   1. 初始化顺序不能乱：BackendConfig.init() 必须早于任何 Dio 实例构造，
//      否则 baseUrl 会固化成默认值。
//   2. Hive 的 'settings' / 'messages' / 'memory' 三个盒子要先 open 再用，
//      未 open 就访问会抛异常。
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/sync/sync_engine.dart';
import 'presentation/providers/app_providers.dart';

/// App 入口：串行完成本地存储、后端配置、同步引擎的初始化后启动 UI。
///
/// 任一初始化步骤失败都会向上抛出并终止启动（fail-fast），
/// 避免带着半初始化的状态进入 UI 造成更难排查的问题。
void main() async {
  // Flutter 异步初始化必须调用
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化 Hive 本地存储（类 IndexedDB，用于持久化）
  await Hive.initFlutter();
  await Hive.openBox('settings');
  await Hive.openBox('messages');
  await Hive.openBox('memory');

  // 初始化后端配置（必须先于 App 运行，因为它决定 Dio baseUrl）
  await BackendConfig.instance.init();

  // 启动离线优先同步引擎（监听联网恢复，自动补发发件箱消息）
  await SyncEngine.instance.start();

  // 首次启动：若用户从未改过后端地址，将默认值落库（默认 = 模拟器地址，
  // 生产构建通过 --dart-define=ZHUYU_API_BASE_URL 注入域名后此处即域名）。
  // 用户在设置页手动改过的不覆盖。
  if (Hive.box('settings').get('backendUrl') == null) {
    Hive.box('settings').put('backendUrl', BackendConfig.instance.baseUrl);
  }

  // Riverpod 跨组件状态管理，child 能通过 ref.watch/read 获取 providers
  runApp(const ProviderScope(child: ZhuyApp()));
}

/// 根 Widget：
/// - MaterialApp.router：用 go_router 做声明式路由
/// - 根据 themeProvider 切换亮/暗主题
/// 竹笌 App 根组件，负责主题与全局状态挂载。
///
/// 主题来自 [themeProvider]（Riverpod），用户在设置页切换后会重建本 Widget。
class ZhuyApp extends ConsumerWidget {
  const ZhuyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider); // GoRouter 实例
    final isDarkMode = ref.watch(themeProvider); // true = 暗色主题

    return MaterialApp.router(
      title: '竹笌',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light, // 亮色主题配色
      darkTheme: AppTheme.dark, // 暗色主题配色
      themeMode: isDarkMode ? ThemeMode.dark : ThemeMode.light,
      routerConfig: router, // 注入路由配置
    );
  }
}
