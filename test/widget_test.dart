// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// 竹笌 App Widget 测试
//
// 测试内容：
//   - 按 main() 的方式初始化（Hive + ProviderScope）后启动 App
//   - 验证启动页上能找到品牌文字 "竹  笌"
//
// 运行命令：
//   flutter test
//
// ── 为什么初始化要写成现在这样（踩坑记录，勿改回）──────
//
// 原实现直接 `await Hive.initFlutter()` 后 `pumpWidget`，在无头环境会**永久挂起**
// （表现为 10 分钟超时、did not complete）。根因有两条，缺一不可：
//
//   1. `Hive.initFlutter()` 内部通过 path_provider 的 MethodChannel 向平台索取
//      文档目录，而无头测试环境没有平台端应答，该 Future 永不完成。
//      → 本测试改用 `Hive.init(显式临时目录)`，**完全绕开 MethodChannel**，
//        因此不需要为 path_provider 注册 mock handler。
//
//   2. `Hive.openBox()` / `BackendConfig.init()` 是真实文件 IO，其 Future 由
//      真实事件循环完成；而 testWidgets 的 body 运行在 FakeAsync 中，真实 IO
//      不会被 FakeAsync 推进。
//      → 所有涉及真实 IO 的 await 必须包在 `tester.runAsync()` 内。
//
// 未 mock 的生产依赖（无需 mock，也不应为测试开后门）：
//   - `routerProvider` / `themeProvider`：ZhuyApp 只依赖这两个 Provider，均为纯
//     Dart 实现，不发起网络请求、不触碰平台通道，故不做 ProviderScope.overrides。
//   - `SyncEngine`：main() 里会 `SyncEngine.instance.start()`，本测试**不启动**它
//     （它监听联网恢复并自动补发，属副作用，不在本测试验证意图内）。
//   注意：本测试验证的是「App 能正常 pump 起来、首帧渲染成功、不抛异常」，
//   不覆盖 SyncEngine / TTS / 音频 / VRM 等运行时行为。
//
// 已知限制（TODO: 待确认）：
//   - 启动页 SplashPage 的 `_floatController` 使用 `repeat(reverse: true)` 无限动画，
//     故本测试**绝不能使用 `tester.pumpAndSettle()`**（会永久等待动画静止）；
//     改在 tearDown 中卸载 widget tree 以停掉动画控制器。
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:zhuyapp/main.dart';
import 'package:zhuyapp/core/config.dart';

void main() {
  testWidgets('竹笌 App 启动测试', (WidgetTester tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();

    // 用一次性临时目录承接 Hive 数据，避免污染真实应用目录，也绕开 path_provider。
    final Directory hiveDir = Directory.systemTemp.createTempSync(
      'zhuyapp_test_hive',
    );

    // 真实文件 IO 必须跳出 FakeAsync，否则 Future 永不完成。
    await tester.runAsync(() async {
      Hive.init(hiveDir.path); // 同步 API，不走 MethodChannel
      await Hive.openBox('settings');
      await Hive.openBox('messages');
      await Hive.openBox('memory');
      await BackendConfig.instance.init();
    });

    // 收尾：卸载 widget tree（停掉 SplashPage 的无限循环动画控制器，
    // 避免 pending ticker）→ 关闭 Hive → 删除临时目录。
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async => Hive.close());
      if (hiveDir.existsSync()) {
        hiveDir.deleteSync(recursive: true);
      }
    });

    // 加载根 Widget（与 main() 一致，包在 ProviderScope 内）
    await tester.pumpWidget(const ProviderScope(child: ZhuyApp()));
    // 等待首帧构建完成
    await tester.pump();

    // 断言：启动页上存在且仅存在一个 "竹  笌" 文本
    expect(find.text('竹  笌'), findsOneWidget);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
