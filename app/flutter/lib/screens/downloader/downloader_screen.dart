import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart';

/// 下载器页面（占位）
class DownloaderScreen extends StatelessWidget {
  const DownloaderScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return NeumorphicTheme(
      theme: const NeumorphicThemeData(
        baseColor: Color(0xFFF0F0F0),
        lightSource: LightSource.topLeft,
        depth: 4,
        intensity: 0.6,
      ),
      child: Scaffold(
        backgroundColor: NeumorphicTheme.baseColor(context),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Neumorphic(
                style: NeumorphicStyle(
                  shape: NeumorphicShape.concave,
                  boxShape: const NeumorphicBoxShape.circle(),
                  depth: 8,
                  intensity: 0.8,
                ),
                child: Container(
                  width: 80,
                  height: 80,
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.download_outlined,
                    size: 40,
                    color: Color(0xFF404040),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                '下载器',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF171717),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '功能开发中...',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
