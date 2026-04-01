import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart';
import '../../utils/theme_colors.dart';

/// Neumorphic 风格的 Toast 组件
class NeumorphicToast {
  /// 显示成功提示
  static void showSuccess(BuildContext context, String message) {
    _show(context, message, ToastType.success);
  }

  /// 显示错误提示
  static void showError(BuildContext context, String message) {
    _show(context, message, ToastType.error);
  }

  /// 显示普通提示
  static void showInfo(BuildContext context, String message) {
    _show(context, message, ToastType.info);
  }

  /// 显示 Toast
  static void _show(BuildContext context, String message, ToastType type) {
    final overlay = Overlay.of(context);
    final overlayEntry = OverlayEntry(
      builder: (context) => _ToastWidget(
        message: message,
        type: type,
      ),
    );

    overlay.insert(overlayEntry);

    // 2秒后自动移除
    Future.delayed(const Duration(seconds: 2), () {
      overlayEntry.remove();
    });
  }
}

/// Toast 类型
enum ToastType {
  success,
  error,
  info,
}

/// Toast Widget
class _ToastWidget extends StatefulWidget {
  final String message;
  final ToastType type;

  const _ToastWidget({
    required this.message,
    required this.type,
  });

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _controller.forward();

    // 1.7秒后开始淡出动画
    Future.delayed(const Duration(milliseconds: 1700), () {
      if (mounted) {
        _controller.reverse();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color _getColor() {
    switch (widget.type) {
      case ToastType.success:
        return Colors.green;
      case ToastType.error:
        return Colors.red;
      case ToastType.info:
        return Colors.blue;
    }
  }

  IconData _getIcon() {
    switch (widget.type) {
      case ToastType.success:
        return Icons.check_circle;
      case ToastType.error:
        return Icons.error;
      case ToastType.info:
        return Icons.info;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _getColor();
    final icon = _getIcon();

    return Positioned(
      bottom: 120, // 在页面偏下方显示
      left: 40,
      right: 40,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: Neumorphic(
                style: NeumorphicStyle(
                  depth: 8,
                  intensity: 0.8,
                  boxShape: NeumorphicBoxShape.roundRect(
                    BorderRadius.circular(20), // 大圆角
                  ),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      NeumorphicIcon(
                        icon,
                        size: 20,
                        style: NeumorphicStyle(
                          depth: 2,
                          intensity: 0.8,
                          color: NeumorphicTheme.baseColor(context),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          widget.message,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: ThemeColors.text(context),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
