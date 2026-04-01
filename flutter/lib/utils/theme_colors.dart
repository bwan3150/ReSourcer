import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart';

/// 主题颜色工具类 - 根据亮色/暗色主题自动适配文字和图标颜色
class ThemeColors {
  /// 获取主要文字/图标颜色
  /// 亮色模式：黑色 (#171717) - 保持原样
  /// 暗色模式：白色 (#E0E0E0)
  static Color text(BuildContext context) {
    return NeumorphicTheme.isUsingDark(context)
        ? const Color(0xFFE0E0E0)  // 暗色：白色
        : const Color(0xFF171717);  // 亮色：黑色（原样）
  }

  /// 获取次要文字/图标颜色（稍淡）
  /// 亮色模式：灰色 (#737373) - 保持原样
  /// 暗色模式：浅灰色 (#B0B0B0)
  static Color textSecondary(BuildContext context) {
    return NeumorphicTheme.isUsingDark(context)
        ? const Color(0xFFB0B0B0)  // 暗色：浅灰色
        : const Color(0xFF737373);  // 亮色：灰色（原样）
  }
}
