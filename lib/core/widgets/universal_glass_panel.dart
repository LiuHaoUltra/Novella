import 'dart:ui';
import 'package:flutter/material.dart';

/// 一个全平台统一渲染的模糊玻璃组件
/// 放弃 iOS 原生 View，强制使用 Flutter 高性能渲染
///
/// 优点：
/// 1. 效果完全一致：Windows、Android、iOS 长得一模一样
/// 2. 性能更好：Flutter 的 BackdropFilter 是 GPU 优化的
/// 3. 完全可控：可以随意调整模糊度和透明度
class UniversalGlassPanel extends StatelessWidget {
  final Widget child;
  final BorderRadius? borderRadius;
  final double blurAmount; // 模糊程度，默认 20 (对应 systemMaterial)

  const UniversalGlassPanel({
    super.key,
    required this.child,
    this.borderRadius,
    this.blurAmount = 20.0, // 可以自己调，10=UltraThin, 20=Material, 30=Thick
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.zero,
      child: Stack(
        children: [
          // 1. 背景模糊层 (核心)
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: blurAmount, sigmaY: blurAmount),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: borderRadius,
                  // 光泽渐变逻辑，让玻璃看起来有质感
                  gradient: _getLiquidGlassGradient(context),
                ),
              ),
            ),
          ),

          // 2. 噪点纹理层 (防止色彩断层，增加磨砂感)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: borderRadius,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: _getGlassOverlayColors(context),
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),

          // 3. 内发光边框 (增加立体感)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: borderRadius,
                border: Border.all(color: _getBorderColor(context), width: 0.5),
              ),
            ),
          ),

          // 4. 内容层
          child,
        ],
      ),
    );
  }

  LinearGradient _getLiquidGlassGradient(BuildContext context) {
    final isDark = MediaQuery.of(context).platformBrightness == Brightness.dark;
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors:
          isDark
              ? [
                Colors.white.withValues(alpha: 0.1),
                Colors.white.withValues(alpha: 0.12),
                Colors.white.withValues(alpha: 0.1),
              ]
              : [
                Colors.white.withValues(alpha: 0.6),
                Colors.white.withValues(alpha: 0.7),
                Colors.white.withValues(alpha: 0.6),
              ],
    );
  }

  List<Color> _getGlassOverlayColors(BuildContext context) {
    final isDark = MediaQuery.of(context).platformBrightness == Brightness.dark;
    if (isDark) {
      return [
        Colors.white.withValues(alpha: 0.01),
        Colors.transparent,
        Colors.black.withValues(alpha: 0.02),
      ];
    } else {
      return [
        Colors.white.withValues(alpha: 0.15),
        Colors.transparent,
        Colors.white.withValues(alpha: 0.08),
      ];
    }
  }

  Color _getBorderColor(BuildContext context) {
    final isDark = MediaQuery.of(context).platformBrightness == Brightness.dark;
    return isDark
        ? Colors.white.withValues(alpha: 0.15)
        : Colors.white.withValues(alpha: 0.6);
  }
}
