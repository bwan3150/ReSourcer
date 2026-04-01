import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart';
import '../../utils/theme_colors.dart';

/// 进度条头部组件（简化版，无文件夹路径）
class ProgressHeader extends StatelessWidget {
  final int currentCount;
  final int totalCount;
  final double progress;

  const ProgressHeader({
    Key? key,
    required this.currentCount,
    required this.totalCount,
    required this.progress,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: NeumorphicTheme.baseColor(context),
        border: Border(
          bottom: BorderSide(
            color: ThemeColors.textSecondary(context).withOpacity(0.1),
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 进度信息
          Text(
            '$currentCount / $totalCount',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: ThemeColors.text(context),
            ),
          ),
          const SizedBox(height: 8),
          // 进度条
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Neumorphic(
              style: NeumorphicStyle(
                depth: -2,
                intensity: 0.6,
                boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(4)),
              ),
              child: Container(
                height: 6,
                child: Stack(
                  children: [
                    Container(
                      color: NeumorphicTheme.baseColor(context),
                    ),
                    FractionallySizedBox(
                      widthFactor: progress,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              ThemeColors.text(context).withOpacity(0.8),
                              ThemeColors.text(context),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
