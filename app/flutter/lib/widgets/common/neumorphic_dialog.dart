import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart';

/// 通用 Neumorphic 对话框
class NeumorphicDialog {
  /// 显示确认对话框（两个按钮）
  static Future<bool?> showConfirm({
    required BuildContext context,
    required String title,
    required String content,
    String cancelText = '取消',
    String confirmText = 'OK',
    Color? confirmTextColor,
  }) {
    return showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.3),
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 40),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: NeumorphicBackground(
            padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF171717),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                content,
                style: const TextStyle(
                  fontSize: 15,
                  color: Color(0xFF737373),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              // 按钮组
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 取消按钮
                  NeumorphicButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: NeumorphicStyle(
                      depth: 4,
                      intensity: 0.7,
                      boxShape: NeumorphicBoxShape.roundRect(
                        BorderRadius.circular(12),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    child: Text(
                      cancelText,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF737373),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // 确认按钮
                  NeumorphicButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: NeumorphicStyle(
                      depth: 4,
                      intensity: 0.7,
                      boxShape: NeumorphicBoxShape.roundRect(
                        BorderRadius.circular(12),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    child: Text(
                      confirmText,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: confirmTextColor ?? const Color(0xFF171717),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }

  /// 显示信息对话框（单个确定按钮）
  static Future<void> showInfo({
    required BuildContext context,
    required String title,
    required String content,
    String buttonText = 'OK',
  }) {
    return showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.3),
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 40),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: NeumorphicBackground(
            padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF171717),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                content,
                style: const TextStyle(
                  fontSize: 15,
                  color: Color(0xFF737373),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              // OK 按钮
              NeumorphicButton(
                onPressed: () => Navigator.pop(context),
                style: NeumorphicStyle(
                  depth: 4,
                  intensity: 0.7,
                  boxShape: NeumorphicBoxShape.roundRect(
                    BorderRadius.circular(12),
                  ),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 12,
                ),
                child: Text(
                  buttonText,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF171717),
                  ),
                ),
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }

  /// 显示自定义内容对话框
  static Future<T?> showCustom<T>({
    required BuildContext context,
    required Widget child,
  }) {
    return showDialog<T>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.3),
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 40),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: NeumorphicBackground(
            child: child,
          ),
        ),
      ),
    );
  }
}
