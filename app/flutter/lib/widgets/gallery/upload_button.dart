import 'dart:async';
import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/upload_provider.dart';
import '../../models/upload_task.dart';
import '../../screens/upload/upload_tasks_screen.dart';

/// 上传任务列表按钮（悬浮按钮）
class UploadButton extends StatefulWidget {
  const UploadButton({Key? key}) : super(key: key);

  @override
  State<UploadButton> createState() => _UploadButtonState();
}

class _UploadButtonState extends State<UploadButton> {
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    // 加载任务并开始轮询
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadTasks();
      _startPolling();
    });
  }

  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }

  Future<void> _loadTasks() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final uploadProvider = Provider.of<UploadProvider>(context, listen: false);

    if (authProvider.apiService != null) {
      await uploadProvider.loadTasks(authProvider.apiService!);
    }
  }

  void _startPolling() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        _loadTasks();
      }
    });
  }

  void _stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  void _openTaskList() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const UploadTasksScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<UploadProvider>(
      builder: (context, provider, child) {
        final activeTasks = provider.tasks
            .where((t) =>
                t.status == UploadStatus.pending ||
                t.status == UploadStatus.uploading)
            .length;

        return Stack(
          children: [
            NeumorphicFloatingActionButton(
              onPressed: _openTaskList,
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
            ),
            // 徽章显示活跃任务数
            if (activeTasks > 0)
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$activeTasks',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
