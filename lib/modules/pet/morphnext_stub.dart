// Stub: morphnext 不可用时的兜底
// 当 morphnext 未安装时，编译此文件而非真正的 morphnext
import 'package:flutter/material.dart';

// 兜底的 AnimatedMorphIcon：无动画，直接替换图标
class AnimatedMorphIcon extends StatelessWidget {
  final IconData icon;
  final double size;
  final Color color;
  final VoidCallback? onEnd;

  const AnimatedMorphIcon({
    super.key,
    required this.icon,
    this.size = 24,
    this.color = Colors.black,
    this.onEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Icon(icon, size: size, color: color);
  }
}
