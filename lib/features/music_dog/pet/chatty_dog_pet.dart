// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// 话痨狗宠物模块（features/music_dog/pet/chatty_dog_pet.dart）
//
// 职责：定义「音乐狗子」的宠物状态模型（PetState）、情绪与动作枚举
//       （PetMood / PetAction）、随机吠叫语录库（DogBarkLibrary），
//       以及可交互的狗子 Widget（ChattyDogPet）。
//
// 上游：pet_studio_page.dart（创作台页挂载此 Widget）、后端 pet_state 状态。
// 下游：依赖 core/theme/app_theme.dart（配色）、flutter_animate（动画）。
//
// 关键点：
//   1. PetState 是不可变值对象，所有变更走 copyWith，便于 Riverpod 做状态比对。
//   2. 语录库为静态常量，随机取值不依赖外部状态。
//   3. 好感度 loveMeter 取值 0-100，与后端 affinity 概念对齐。
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:zhuyapp/core/theme/app_theme.dart';

/// 话痨狗系宠物模块
/// Chatty Dog Pet Module
/// 
/// 性格：活泼、话多、爱撒娇、随时评论
/// Personality: lively, talkative, loves attention, always commenting

// ═══════════════════════════════════════════════
// 宠物状态
// ═══════════════════════════════════════════════
/// 宠物心情枚举。
///
/// 决定狗子的整体配色（见 [DogPainter._moodColor]）、表情（见 [DogPainter._drawMouth]）
/// 以及吠叫语录（见 [DogBarkLibrary.barkForMood]）。
enum PetMood {
  /// 开心：暖橙配色，微笑吐舌
  happy,
  /// 兴奋：活泼红，张嘴大笑
  excited,
  /// 犯困：慵懒紫，半睁眼
  sleepy,
  /// 饥饿：饥饿黄
  hungry,
  /// 困惑：困惑绿
  confused,
  /// 生气：橙红，撇嘴
  angry,
}
/// 宠物动作枚举，对应 UI 上的交互反馈与动画。
enum PetAction {
  /// 待机：无动作
  idle,
  /// 吠叫
  bark,
  /// 跳跃
  jump,
  /// 摇头/摇晃
  shake,
  /// 睡觉
  sleep,
  /// 进食
  eat,
  /// 撒娇/示爱
  love,
}

/// 宠物当前状态的不可变值对象。
///
/// 所有字段在构造时确定，状态变更统一走 [copyWith]，便于 Riverpod 做
/// 引用相等比对来触发重建。
class PetState {
  /// 当前心情。
  final PetMood mood;
  /// 当前动作。
  final PetAction action;
  /// 当前显示的吠叫文本。
  final String currentBark;
  /// 今天叫了多少次。
  final int barkCount;
  /// 好感度，取值 0-100，与后端 affinity 概念对齐。
  final double loveMeter;

  PetState({
    this.mood = PetMood.happy,
    this.action = PetAction.idle,
    this.currentBark = '',
    this.barkCount = 0,
    this.loveMeter = 50.0,
  });

  /// 返回一份新 [PetState]，仅覆盖传入的非空字段。
  ///
  /// 用于在不修改原对象的前提下更新宠物状态。
  PetState copyWith({
    PetMood? mood,
    PetAction? action,
    String? currentBark,
    int? barkCount,
    double? loveMeter,
  }) {
    return PetState(
      mood: mood ?? this.mood,
      action: action ?? this.action,
      currentBark: currentBark ?? this.currentBark,
      barkCount: barkCount ?? this.barkCount,
      loveMeter: loveMeter ?? this.loveMeter,
    );
  }
}

// ═══════════════════════════════════════════════
// 话痨狗语录库
// ═══════════════════════════════════════════════
/// 话痨狗的随机吠叫语录库。
///
/// 全部语录为静态常量，按场景（基础 / 心情 / 交互反馈）分组；随机取值不依赖
/// 任何外部状态，因此可安全在任意位置调用。
class DogBarkLibrary {
  static final _random = Random();

  // 基础吠叫（随时冒出来）
  static const _randomBarks = [
    '汪汪汪！今天天气真好啊！',
    '主人主人，你在听我说话吗？',
    '我好无聊啊——汪！',
    '嘿！别看手机了，看我看我！',
    '这个音乐好听！汪汪汪！',
    '我饿了——等等你刚喂过我吗？',
    '汪！汪汪！汪汪汪！', // 纯粹想叫
    '主人你今天开心吗？',
    '我想出去玩——汪！',
    '别走别走别走！我还没说完呢！',
    '这首歌的节奏好棒！跟着动起来！',
    '你今天瘦了吗？看起来不一样！',
    '汪呜～我刚才做了个好梦……',
    '主人主人，跟我玩嘛～',
    '我觉得……不对，我觉得这个不对！',
    '等等我有一个很棒的想法——',
  ];

  // 情绪相关吠叫
  static const _happyBarks = [
    '汪汪汪汪！好开心！',
    '今天是最棒的一天！汪！',
    '主人最好了！最最好了！汪汪！',
    '我也爱你！汪呜～',
    '一起跳舞吗？一二三汪！',
  ];

  static const _excitedBarks = [
    '真的吗？！汪汪汪！！',
    '太棒了太棒了太棒了！！！',
    '我要转圈圈！汪！！',
    '等等等等这也太酷了吧！！',
    '主人你简直是个天才！！汪！',
  ];

  static const _sleepyBarks = [
    '汪呜……好困……',
    '我再坚持一下……嗯……',
    'Zzz……汪？',
    '叫我起床……汪……',
    '五分钟……就五分钟……',
  ];

  static const _hungryBarks = [
    '肚子在叫！汪！',
    '有吃的吗？有吗有吗？',
    '汪——我的碗是空的！',
    '主人——饭——汪！',
    '咕噜咕噜咕噜……',
  ];

  static const _confusedBarks = [
    '汪？什么？',
    '等下等下，让我想想……',
    '这个有点复杂啊——汪？',
    '我脑子转不过来了！',
    '汪呜……你说什么？',
  ];

  static const _angryBarks = [
    '汪！！不公平！！',
    '哼！我生气了！汪！',
    '你太过分了！汪汪汪！',
    '我要咬你——开玩笑的汪！',
    '哼唧哼唧！',
  ];

  // 交互反馈
  static const _petBarks = [
    '呜～好舒服～再来一次！',
    '汪呜～喜欢！',
    '摸头杀！我是小可爱！',
    '再摸摸再摸摸！',
    '这感觉……汪呜～幸福～',
  ];

  static const _shakeBarks = [
    '汪汪汪！甩甩更健康！',
    '哎呀别摇了——汪！',
    '我是拖把吗？！汪！',
    '摇摇摇～头好晕——',
    '喂！停下！我要吐了汪！',
  ];

  /// 从基础语录中随机返回一条吠叫。
  static String randomBark() {
    return _randomBarks[_random.nextInt(_randomBarks.length)];
  }

  /// 按给定心情返回对应情绪语录中的随机一条。
  ///
  /// Args:
  ///   mood: 目标心情，switch 穷尽所有枚举值保证有返回值。
  static String barkForMood(PetMood mood) {
    switch (mood) {
      case PetMood.happy:
        return _happyBarks[_random.nextInt(_happyBarks.length)];
      case PetMood.excited:
        return _excitedBarks[_random.nextInt(_excitedBarks.length)];
      case PetMood.sleepy:
        return _sleepyBarks[_random.nextInt(_sleepyBarks.length)];
      case PetMood.hungry:
        return _hungryBarks[_random.nextInt(_hungryBarks.length)];
      case PetMood.confused:
        return _confusedBarks[_random.nextInt(_confusedBarks.length)];
      case PetMood.angry:
        return _angryBarks[_random.nextInt(_angryBarks.length)];
    }
  }

  /// 被抚摸时的反馈吠叫。
  static String petBark() => _petBarks[_random.nextInt(_petBarks.length)];
  /// 被摇晃时的反馈吠叫。
  static String shakeBark() => _shakeBarks[_random.nextInt(_shakeBarks.length)];
}

// ═══════════════════════════════════════════════
// 3D 效果狗子绘制
// ═══════════════════════════════════════════════
/// 用 CustomPaint 手绘的 2D 狗子，按心情与动画偏移渲染。
///
/// 不依赖图片资源，全部用 [Canvas] 图元绘制（阴影/身体/头/耳/眼/脸/尾/腿），
/// 配色由 [_moodColor] 按心情决定，摇摆动画在 [_drawTail] 里用时间驱动。
class DogPainter extends CustomPainter {
  /// 当前心情，决定配色与表情。
  final PetMood mood;
  final double bounceOffset;
  final double rotationY;
  final double scale;

  DogPainter({
    this.mood = PetMood.happy,
    this.bounceOffset = 0,
    this.rotationY = 0,
    this.scale = 1,
  });

  /// 按图层顺序绘制整只狗子：阴影→身体→头→耳→眼→脸→尾→腿。
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 + bounceOffset);
    final radius = size.width / 2.5 * scale;

    // 3D 阴影效果
    _drawShadow(canvas, center, radius);
    
    // 身体（带透视）
    _drawBody(canvas, center, radius);
    
    // 头
    _drawHead(canvas, center, radius);
    
    // 耳朵
    _drawEars(canvas, center, radius);
    
    // 眼睛
    _drawEyes(canvas, center, radius);
    
    // 鼻子和嘴巴
    _drawFace(canvas, center, radius);
    
    // 尾巴（根据心情摆动）
    _drawTail(canvas, center, radius);
    
    // 腿
    _drawLegs(canvas, center, radius);
  }

  void _drawShadow(Canvas canvas, Offset center, double radius) {
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.15)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx, center.dy + radius * 1.4),
        width: radius * 2.2,
        height: radius * 0.4,
      ),
      shadowPaint,
    );
  }

  void _drawBody(Canvas canvas, Offset center, double radius) {
    // 身体渐变（模拟3D球体）
    final bodyPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.3, -0.3),
        colors: [
          _moodColor.withValues(alpha: 0.9),
          _moodColor,
          _moodColor.withValues(alpha: 0.7),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius * 0.9));

    canvas.drawCircle(center, radius * 0.9, bodyPaint);

    // 身体高光
    final highlightPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx - radius * 0.25, center.dy - radius * 0.25),
        width: radius * 0.4,
        height: radius * 0.25,
      ),
      highlightPaint,
    );
  }

  void _drawHead(Canvas canvas, Offset center, double radius) {
    final headCenter = Offset(center.dx, center.dy - radius * 0.3);
    final headRadius = radius * 0.55;

    // 头部渐变
    final headPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.3, -0.3),
        colors: [
          _moodColor.withValues(alpha: 0.95),
          _moodColor,
        ],
      ).createShader(Rect.fromCircle(center: headCenter, radius: headRadius));

    canvas.drawCircle(headCenter, headRadius, headPaint);

    // 脸部白色区域
    final facePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.85);
    
    // 脸部椭圆
    final faceRect = Rect.fromCenter(
      center: Offset(headCenter.dx, headCenter.dy + headRadius * 0.2),
      width: headRadius * 1.3,
      height: headRadius * 1.1,
    );
    canvas.drawOval(faceRect, facePaint);
  }

  void _drawEars(Canvas canvas, Offset center, double radius) {
    final earPaint = Paint()
      ..color = _moodColor.withValues(alpha: 0.85);

    // 左耳
    final leftEarPath = Path()
      ..moveTo(center.dx - radius * 0.5, center.dy - radius * 0.5)
      ..quadraticBezierTo(
        center.dx - radius * 0.9,
        center.dy - radius * 1.2,
        center.dx - radius * 0.6,
        center.dy - radius * 0.7,
      )
      ..close();
    canvas.drawPath(leftEarPath, earPaint);

    // 右耳
    final rightEarPath = Path()
      ..moveTo(center.dx + radius * 0.5, center.dy - radius * 0.5)
      ..quadraticBezierTo(
        center.dx + radius * 0.9,
        center.dy - radius * 1.2,
        center.dx + radius * 0.6,
        center.dy - radius * 0.7,
      )
      ..close();
    canvas.drawPath(rightEarPath, earPaint);

    // 耳内颜色
    final innerEarPaint = Paint()..color = AppTheme.sun.withValues(alpha: 0.5);
    canvas.drawCircle(
      Offset(center.dx - radius * 0.72, center.dy - radius * 0.85),
      radius * 0.12,
      innerEarPaint,
    );
    canvas.drawCircle(
      Offset(center.dx + radius * 0.72, center.dy - radius * 0.85),
      radius * 0.12,
      innerEarPaint,
    );
  }

  void _drawEyes(Canvas canvas, Offset center, double radius) {
    final headCenter = Offset(center.dx, center.dy - radius * 0.3);
    final eyeRadius = radius * 0.12;
    final eyeY = headCenter.dy - radius * 0.1;

    // 左眼
    _drawEye(canvas, Offset(headCenter.dx - radius * 0.22, eyeY), eyeRadius);
    // 右眼
    _drawEye(canvas, Offset(headCenter.dx + radius * 0.22, eyeY), eyeRadius);
  }

  void _drawEye(Canvas canvas, Offset center, double radius) {
    // 眼眶
    final eyeBgPaint = Paint()..color = Colors.white;
    canvas.drawCircle(center, radius * 1.3, eyeBgPaint);

    // 虹膜（根据心情变化）
    final irisColor = _moodColor.withValues(alpha: 0.8);
    final irisPaint = Paint()..color = irisColor;
    canvas.drawCircle(center, radius, irisPaint);

    // 瞳孔
    final pupilPaint = Paint()..color = Colors.black;
    canvas.drawCircle(center, radius * 0.5, pupilPaint);

    // 眼神光
    final highlightPaint = Paint()..color = Colors.white;
    canvas.drawCircle(
      Offset(center.dx - radius * 0.2, center.dy - radius * 0.2),
      radius * 0.25,
      highlightPaint,
    );
  }

  void _drawFace(Canvas canvas, Offset center, double radius) {
    final headCenter = Offset(center.dx, center.dy - radius * 0.3);

    // 鼻子
    final nosePaint = Paint()..color = Colors.black;
    final noseCenter = Offset(headCenter.dx, headCenter.dy + radius * 0.05);
    canvas.drawOval(
      Rect.fromCenter(center: noseCenter, width: radius * 0.2, height: radius * 0.15),
      nosePaint,
    );

    // 鼻子高光
    final noseHighlight = Paint()..color = Colors.white.withValues(alpha: 0.3);
    canvas.drawCircle(
      Offset(noseCenter.dx - radius * 0.03, noseCenter.dy - radius * 0.03),
      radius * 0.04,
      noseHighlight,
    );

    // 嘴巴（根据心情变化）
    _drawMouth(canvas, headCenter, radius);

    // 腮红
    final blushPaint = Paint()..color = AppTheme.sun.withValues(alpha: 0.35);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(headCenter.dx - radius * 0.35, headCenter.dy + radius * 0.1),
        width: radius * 0.2,
        height: radius * 0.12,
      ),
      blushPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(headCenter.dx + radius * 0.35, headCenter.dy + radius * 0.1),
        width: radius * 0.2,
        height: radius * 0.12,
      ),
      blushPaint,
    );
  }

  void _drawMouth(Canvas canvas, Offset headCenter, double radius) {
    final mouthY = headCenter.dy + radius * 0.2;
    final mouthPaint = Paint()
      ..color = AppTheme.ember
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    switch (mood) {
      case PetMood.happy:
        // 开心微笑
        final path = Path()
          ..moveTo(headCenter.dx - radius * 0.15, mouthY)
          ..quadraticBezierTo(
            headCenter.dx,
            mouthY + radius * 0.15,
            headCenter.dx + radius * 0.15,
            mouthY,
          );
        canvas.drawPath(path, mouthPaint);
        // 舌头
        final tonguePaint = Paint()..color = AppTheme.ember;
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(headCenter.dx, mouthY + radius * 0.08),
            width: radius * 0.12,
            height: radius * 0.1,
          ),
          tonguePaint,
        );
        break;
      case PetMood.excited:
        // 张嘴大笑
        final fillPaint = Paint()..color = AppTheme.ember;
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(headCenter.dx, mouthY + radius * 0.05),
            width: radius * 0.25,
            height: radius * 0.18,
          ),
          fillPaint,
        );
        break;
      case PetMood.sleepy:
        // 犯困的嘴
        canvas.drawLine(
          Offset(headCenter.dx - radius * 0.08, mouthY),
          Offset(headCenter.dx + radius * 0.08, mouthY),
          mouthPaint,
        );
        break;
      case PetMood.angry:
        // 生气的嘴
        final path = Path()
          ..moveTo(headCenter.dx - radius * 0.12, mouthY + radius * 0.05)
          ..quadraticBezierTo(
            headCenter.dx,
            mouthY - radius * 0.05,
            headCenter.dx + radius * 0.12,
            mouthY + radius * 0.05,
          );
        canvas.drawPath(path, mouthPaint);
        break;
      default:
        // 普通表情
        final path = Path()
          ..moveTo(headCenter.dx - radius * 0.1, mouthY)
          ..quadraticBezierTo(
            headCenter.dx,
            mouthY + radius * 0.08,
            headCenter.dx + radius * 0.1,
            mouthY,
          );
        canvas.drawPath(path, mouthPaint);
    }
  }

  void _drawTail(Canvas canvas, Offset center, double radius) {
    final tailPaint = Paint()..color = _moodColor.withValues(alpha: 0.85);
    
    // 尾巴位置和摇摆幅度
    final tailStart = Offset(center.dx + radius * 0.7, center.dy + radius * 0.3);
    final tailWag = sin(DateTime.now().millisecondsSinceEpoch / 150.0) * radius * 0.3;
    final tailEnd = Offset(tailStart.dx + radius * 0.5 + tailWag, tailStart.dy - radius * 0.6);

    final tailPath = Path()
      ..moveTo(tailStart.dx, tailStart.dy)
      ..quadraticBezierTo(
        tailStart.dx + radius * 0.3,
        tailStart.dy - radius * 0.3,
        tailEnd.dx,
        tailEnd.dy,
      )
      ..quadraticBezierTo(
        tailStart.dx + radius * 0.2,
        tailStart.dy - radius * 0.15,
        tailStart.dx,
        tailStart.dy + radius * 0.1,
      )
      ..close();

    canvas.drawPath(tailPath, tailPaint);
  }

  void _drawLegs(Canvas canvas, Offset center, double radius) {
    final legPaint = Paint()..color = _moodColor.withValues(alpha: 0.85);
    final legWidth = radius * 0.12;
    final legHeight = radius * 0.35;

    // 前腿
    final frontLegPaint = Paint()..color = _moodColor.withValues(alpha: 0.9);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(center.dx - radius * 0.4, center.dy + radius * 0.7),
          width: legWidth,
          height: legHeight,
        ),
        Radius.circular(legWidth / 2),
      ),
      frontLegPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(center.dx + radius * 0.4, center.dy + radius * 0.7),
          width: legWidth,
          height: legHeight,
        ),
        Radius.circular(legWidth / 2),
      ),
      frontLegPaint,
    );

    // 后腿（微微可见）
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(center.dx - radius * 0.6, center.dy + radius * 0.55),
          width: legWidth,
          height: legHeight * 0.7,
        ),
        Radius.circular(legWidth / 2),
      ),
      legPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(center.dx + radius * 0.6, center.dy + radius * 0.55),
          width: legWidth,
          height: legHeight * 0.7,
        ),
        Radius.circular(legWidth / 2),
      ),
      legPaint,
    );
  }

  /// 根据心情返回狗子主体配色。
  Color get _moodColor {
    switch (mood) {
      case PetMood.happy:
        return const Color(0xFFFFB347);    // 暖橙色
      case PetMood.excited:
        return const Color(0xFFFF6B6B);    // 活泼红
      case PetMood.sleepy:
        return const Color(0xFFB4A7D6);    // 慵懒紫
      case PetMood.hungry:
        return const Color(0xFFFFD93D);    // 饥饿黄
      case PetMood.confused:
        return const Color(0xFF6BCB77);     // 困惑绿
      case PetMood.angry:
        return const Color(0xFFFF8C42);     // 生气橙红
    }
  }

  /// 仅当心情或动画偏移变化时才重绘，避免每帧无谓的 paint 调用。
  @override
  bool shouldRepaint(covariant DogPainter oldDelegate) {
    return oldDelegate.mood != mood ||
        oldDelegate.bounceOffset != bounceOffset ||
        oldDelegate.rotationY != rotationY;
  }
}

// ═══════════════════════════════════════════════
// 宠物气泡（说对话）
// ═══════════════════════════════════════════════
/// 狗子对话气泡：圆角卡片 + 进出场淡入/滑入动画。
///
/// [isLeft] 控制气泡靠左（狗子说）还是靠右（主人说）的对齐与尖角方向。
class SpeechBubble extends StatelessWidget {
  /// 气泡显示的文本。
  final String text;
  /// true=靠左（狗子），false=靠右（主人）。
  final bool isLeft;

  const SpeechBubble({
    super.key,
    required this.text,
    this.isLeft = true,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isLeft ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.7,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: isLeft ? Radius.zero : const Radius.circular(18),
            bottomRight: isLeft ? const Radius.circular(18) : Radius.zero,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 15,
            color: AppTheme.fg2,
            height: 1.4,
          ),
        ),
      ),
    ).animate().fadeIn(duration: 200.ms).slideX(begin: isLeft ? -0.2 : 0.2);
  }
}

// ═══════════════════════════════════════════════
// 好感度进度条
// ═══════════════════════════════════════════════
/// 好感度进度条：💕 图标 + 横向进度 + 百分比文字，值越高颜色越暖。
class LoveMeterBar extends StatelessWidget {
  /// 好感度数值，取值 0-100。
  final double value;

  const LoveMeterBar({super.key, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppTheme.sun.withValues(alpha: 0.2),
            blurRadius: 8,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('💕', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          SizedBox(
            width: 80,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: value / 100,
                backgroundColor: AppTheme.borderSoft,
                valueColor: AlwaysStoppedAnimation(
                  value > 70
                      ? AppTheme.sun
                      : value > 40
                          ? AppTheme.sun
                          : AppTheme.muted,
                ),
                minHeight: 8,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '${value.toInt()}%',
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.meta,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// 交互按钮
// ═══════════════════════════════════════════════
/// 宠物交互按钮：圆形图标 + 文字标签，点击回调 [onTap]。
class PetActionButton extends StatelessWidget {
  /// 按钮图标。
  final IconData icon;
  /// 按钮下方文字。
  final String label;
  /// 点击回调。
  final VoidCallback onTap;
  /// 主题色（图标、边框、文字均以其派生）。
  final Color color;

  const PetActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = AppTheme.sun,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.3), width: 2),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color.withValues(alpha: 0.8),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// 主宠物组件
// ═══════════════════════════════════════════════
/// 可交互的「话痨狗」宠物主组件。
///
/// 自带弹跳/摇晃动画、每 8 秒定时吠叫、气泡对话；并暴露 [triggerBark]/[triggerMood]
/// 供外部（如创作台页）驱动狗子说话或切换心情。点击=抚摸，长按=摇晃。
class ChattyDogPet extends StatefulWidget {
  /// 音乐播放状态回调（用于宠物跟随音乐节奏）
  final bool isPlaying;
  /// 外部触发宠物说话
  final String? triggerBark;
  /// 外部触发心情变化
  final PetMood? triggerMood;

  const ChattyDogPet({
    super.key,
    this.isPlaying = false,
    this.triggerBark,
    this.triggerMood,
  });

  @override
  State<ChattyDogPet> createState() => _ChattyDogPetState();
}

/// 狗子主组件状态：管理弹跳/摇晃动画控制器、定时吠叫定时器与宠物状态。
class _ChattyDogPetState extends State<ChattyDogPet>
    with TickerProviderStateMixin {
  PetState _state = PetState();
  Timer? _barkTimer;
  late AnimationController _bounceController;
  late AnimationController _shakeController;
  late Animation<double> _bounceAnimation;
  String? _currentBubbleText;
  bool _showBubble = false;

  @override
  void initState() {
    super.initState();

    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _bounceAnimation = Tween<double>(begin: -8, end: 8).animate(
      CurvedAnimation(parent: _bounceController, curve: Curves.easeInOut),
    );

    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _startBarkLoop();
  }

  @override
  void didUpdateWidget(ChattyDogPet oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.triggerBark != null && widget.triggerBark != oldWidget.triggerBark) {
      _showSpeech(widget.triggerBark!);
    }

    if (widget.triggerMood != null && widget.triggerMood != oldWidget.triggerMood) {
      _setMood(widget.triggerMood!);
    }
  }

  /// 启动每 8 秒一次的定时吠叫循环：按当前心情选词、气泡显示并 barkCount +1。
  void _startBarkLoop() {
    _barkTimer?.cancel();
    _barkTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (!mounted) return;
      final bark = DogBarkLibrary.barkForMood(_state.mood);
      _showSpeech(bark);
      setState(() {
        _state = _state.copyWith(
          barkCount: _state.barkCount + 1,
        );
      });
    });
  }

  /// 弹出气泡显示 [text]，4 秒后若组件仍在树中则自动收起。
  void _showSpeech(String text) {
    setState(() {
      _currentBubbleText = text;
      _showBubble = true;
    });
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() => _showBubble = false);
      }
    });
  }

  /// 切换狗子心情并立刻用对应情绪语录说一句话。
  void _setMood(PetMood mood) {
    setState(() {
      _state = _state.copyWith(mood: mood);
    });
    final bark = DogBarkLibrary.barkForMood(mood);
    _showSpeech(bark);
  }

  /// 点击宠物：抚摸反馈，好感度 +3 并切回开心心情。
  void _onPet() {
    _showSpeech(DogBarkLibrary.petBark());
    setState(() {
      _state = _state.copyWith(
        loveMeter: (_state.loveMeter + 3).clamp(0, 100),
        mood: PetMood.happy,
      );
    });
  }

  /// 长按摇晃：播放摇晃动画并切到兴奋心情。
  void _onShake() {
    _shakeController.forward(from: 0);
    _showSpeech(DogBarkLibrary.shakeBark());
    setState(() {
      _state = _state.copyWith(mood: PetMood.excited);
    });
  }

  /// 喂食：好感度 +5 并切回开心心情。
  void _onFeed() {
    _showSpeech('汪呜～好吃！谢谢你！');
    setState(() {
      _state = _state.copyWith(
        mood: PetMood.happy,
        loveMeter: (_state.loveMeter + 5).clamp(0, 100),
      );
    });
  }

  /// 手动吠叫：随机语录 + barkCount +1。
  void _onBark() {
    _showSpeech(DogBarkLibrary.randomBark());
    setState(() {
      _state = _state.copyWith(barkCount: _state.barkCount + 1);
    });
  }

  @override
  void dispose() {
    _barkTimer?.cancel();
    _bounceController.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _moodGradientColors[_state.mood]!.first.withValues(alpha: 0.3),
            _moodGradientColors[_state.mood]!.last.withValues(alpha: 0.1),
          ],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // 顶部信息栏
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildMoodChip(),
                  LoveMeterBar(value: _state.loveMeter),
                ],
              ),
            ),

            // 对话气泡区域
            if (_showBubble && _currentBubbleText != null)
              SpeechBubble(text: _currentBubbleText!),

            // 宠物主体
            Expanded(
              child: GestureDetector(
                onTap: _onPet,
                onLongPress: _onShake,
                child: AnimatedBuilder(
                  animation: Listenable.merge([_bounceAnimation, _shakeController]),
                  builder: (context, child) {
                    return Transform.translate(
                      offset: Offset(
                        sin(_shakeController.value * 10) * 10,
                        _bounceAnimation.value,
                      ),
                      child: Transform.scale(
                        scale: 1 + (_shakeController.value * 0.1),
                        child: CustomPaint(
                          size: Size.infinite,
                          painter: DogPainter(
                            mood: _state.mood,
                            bounceOffset: _bounceAnimation.value,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            // 今日统计
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '今日汪汪次数：${_state.barkCount}',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.meta,
                ),
              ),
            ),

            // 交互按钮
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  PetActionButton(
                    icon: Icons.pets,
                    label: '摸摸',
                    onTap: _onPet,
                    color: AppTheme.sun,
                  ),
                  PetActionButton(
                    icon: Icons.restaurant,
                    label: '喂食',
                    onTap: _onFeed,
                    color: AppTheme.sun,
                  ),
                  PetActionButton(
                    icon: Icons.vibration,
                    label: '摇晃',
                    onTap: _onShake,
                    color: Colors.blue,
                  ),
                  PetActionButton(
                    icon: Icons.volume_up,
                    label: '汪汪',
                    onTap: _onBark,
                    color: Colors.green,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建顶部当前心情标签（emoji + 名称 + 配色圆角块）。
  Widget _buildMoodChip() {
    final moodInfo = _moodNames[_state.mood]!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: moodInfo.color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: moodInfo.color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(moodInfo.emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 4),
          Text(
            moodInfo.name,
            style: TextStyle(
              fontSize: 13,
              color: moodInfo.color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  static const _moodNames = {
    PetMood.happy: (name: '开心', emoji: '😄', color: Color(0xFFFFB347)),
    PetMood.excited: (name: '兴奋', emoji: '🤩', color: Color(0xFFFF6B6B)),
    PetMood.sleepy: (name: '犯困', emoji: '😴', color: Color(0xFFB4A7D6)),
    PetMood.hungry: (name: '饥饿', emoji: '🤤', color: Color(0xFFFFD93D)),
    PetMood.confused: (name: '困惑', emoji: '😕', color: Color(0xFF6BCB77)),
    PetMood.angry: (name: '生气', emoji: '😠', color: Color(0xFFFF8C42)),
  };

  static const _moodGradientColors = {
    PetMood.happy: [Color(0xFFFFF3E0), Color(0xFFFFE0B2)],
    PetMood.excited: [Color(0xFFFFEBEE), Color(0xFFFFCDD2)],
    PetMood.sleepy: [Color(0xFFEDE7F6), Color(0xFFD1C4E9)],
    PetMood.hungry: [Color(0xFFFFFDE7), Color(0xFFFFF9C4)],
    PetMood.confused: [Color(0xFFE8F5E9), Color(0xFFC8E6C9)],
    PetMood.angry: [Color(0xFFFBE9E7), Color(0xFFFFCCBC)],
  };
}

// ═══════════════════════════════════════════════
// 使用示例页面
// ═══════════════════════════════════════════════
/// 话痨狗独立演示页：可切换心情、播放/暂停音乐，用于预览宠物组件效果。
class ChattyDogDemo extends StatefulWidget {
  const ChattyDogDemo({super.key});

  @override
  State<ChattyDogDemo> createState() => _ChattyDogDemoState();
}

class _ChattyDogDemoState extends State<ChattyDogDemo> {
  PetMood _currentMood = PetMood.happy;
  bool _isPlaying = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceWarm,
      appBar: AppBar(
        title: const Text('🐕 话痨狗子'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
            onPressed: () => setState(() => _isPlaying = !_isPlaying),
          ),
          PopupMenuButton<PetMood>(
            icon: const Icon(Icons.mood),
            onSelected: (mood) => setState(() => _currentMood = mood),
            itemBuilder: (context) => PetMood.values.map((mood) {
              return PopupMenuItem(
                value: mood,
                child: Text('切换到${_ChattyDogPetState._moodNames[mood]!.name}模式'),
              );
            }).toList(),
          ),
        ],
      ),
      body: ChattyDogPet(
        isPlaying: _isPlaying,
        triggerMood: _currentMood,
        triggerBark: '主人你好！汪！',
      ),
    );
  }
}
