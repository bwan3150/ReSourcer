import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart';
import '../../utils/theme_colors.dart';

/// Neumorphic 风格的镂空悬浮 AppBar
///
/// 页面内容可以从下方穿过，左右各一个可选按钮，中间是大圆角标题栏
///
/// 使用方式：将此组件放置在 Stack 的最上层
///
/// 示例：
/// ```dart
/// Stack(
///   children: [
///     // 页面主要内容
///     YourContent(),
///     // 镂空 AppBar
///     NeumorphicOverlayAppBar(
///       title: '标题',
///       leading: NeumorphicButton(...),
///       trailing: NeumorphicButton(...),
///     ),
///   ],
/// )
/// ```
class NeumorphicOverlayAppBar extends StatelessWidget {
  /// 标题文本
  final String title;

  /// 左侧按钮（可选）
  final Widget? leading;

  /// 右侧按钮（可选）
  final Widget? trailing;

  /// 标题栏背景色（默认使用浅色）
  final Color? backgroundColor;

  /// 标题文字样式
  final TextStyle? titleStyle;

  /// 顶部/左右内边距
  final EdgeInsets padding;

  const NeumorphicOverlayAppBar({
    Key? key,
    required this.title,
    this.leading,
    this.trailing,
    this.backgroundColor,
    this.titleStyle,
    this.padding = const EdgeInsets.all(20),
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: padding,
          child: Row(
            children: [
              // 左侧按钮
              if (leading != null) ...[
                leading!,
                const SizedBox(width: 16),
              ],
              // 中间标题栏
              Expanded(
                child: Neumorphic(
                  style: NeumorphicStyle(
                    depth: 4,
                    intensity: 0.6,
                    color: backgroundColor ?? const Color(0xFFF0F0F0),
                    boxShape: NeumorphicBoxShape.roundRect(
                      BorderRadius.circular(25),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  child: Text(
                    title,
                    style: titleStyle ??
                        TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: ThemeColors.text(context),
                        ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              // 右侧按钮
              if (trailing != null) ...[
                const SizedBox(width: 16),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 快速创建圆形 Neumorphic 按钮的辅助类
class NeumorphicCircleButton extends StatelessWidget {
  /// 点击回调
  final VoidCallback? onPressed;

  /// 按钮图标
  final IconData icon;

  /// 图标大小
  final double iconSize;

  /// 图标颜色
  final Color? iconColor;

  /// 按钮内边距
  final EdgeInsets padding;

  /// Neumorphic 样式深度
  final double depth;

  /// 按钮背景色
  final Color? backgroundColor;

  const NeumorphicCircleButton({
    Key? key,
    required this.onPressed,
    required this.icon,
    this.iconSize = 20,
    this.iconColor,
    this.padding = const EdgeInsets.all(12),
    this.depth = 4,
    this.backgroundColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return NeumorphicButton(
      onPressed: onPressed,
      style: NeumorphicStyle(
        boxShape: const NeumorphicBoxShape.circle(),
        depth: depth,
        color: backgroundColor ?? const Color(0xFFF0F0F0),
      ),
      padding: padding,
      child: Icon(
        icon,
        size: iconSize,
        color: iconColor ?? ThemeColors.text(context),
      ),
    );
  }
}
