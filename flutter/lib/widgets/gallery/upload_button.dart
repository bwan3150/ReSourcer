import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart';
import '../../screens/upload/upload_tasks_screen.dart';

/// 上传任务列表按钮（悬浮按钮）- 仅作为入口，不显示徽章，不轮询
class UploadButton extends StatelessWidget {
  const UploadButton({Key? key}) : super(key: key);

  void _openTaskList(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const UploadTasksScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return NeumorphicFloatingActionButton(
      onPressed: () => _openTaskList(context),
      style: NeumorphicStyle(
        depth: 6,
        intensity: 0.8,
        boxShape: const NeumorphicBoxShape.circle(),
        color: NeumorphicTheme.baseColor(context),
      ),
      child: const Icon(
        Icons.cloud_upload_outlined,
        size: 28,
        color: Color(0xFF171717),
      ),
    );
  }
}
