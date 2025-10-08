import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart';
import '../../utils/theme_colors.dart';

/// 选项数据类
class SheetOption {
  final IconData icon;
  final String text;
  final Color? textColor;
  final Color? iconColor;
  final VoidCallback onTap;

  const SheetOption({
    required this.icon,
    required this.text,
    required this.onTap,
    this.textColor,
    this.iconColor,
  });
}

/// 通用 Neumorphic 选择弹窗（底部弹出）
class NeumorphicOptionSheet {
  /// 显示选项列表弹窗
  static Future<void> show({
    required BuildContext context,
    String? title,
    required List<SheetOption> options,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: NeumorphicBackground(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 标题（可选）
              if (title != null) ...[
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: ThemeColors.text(context),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
              ],
              // 选项列表
              ...options.asMap().entries.map((entry) {
                final index = entry.key;
                final option = entry.value;
                return Column(
                  children: [
                    if (index > 0) const SizedBox(height: 12),
                    _buildOption(context, option),
                  ],
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建单个选项按钮
  static Widget _buildOption(BuildContext context, SheetOption option) {
    return NeumorphicButton(
      onPressed: () {
        Navigator.pop(context);
        option.onTap();
      },
      style: NeumorphicStyle(
        depth: 4,
        intensity: 0.7,
        boxShape: NeumorphicBoxShape.roundRect(
          BorderRadius.circular(12),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: [
          Icon(
            option.icon,
            color: option.iconColor ?? ThemeColors.text(context),
            size: 24,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              option.text,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: option.textColor ?? ThemeColors.text(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
