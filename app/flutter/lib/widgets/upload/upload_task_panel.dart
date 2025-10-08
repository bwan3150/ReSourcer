import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart';
import 'package:provider/provider.dart';
import '../../models/upload_task.dart';
import '../../providers/auth_provider.dart';
import '../../providers/upload_provider.dart';

/// 上传任务面板
class UploadTaskPanel extends StatelessWidget {
  const UploadTaskPanel({Key? key}) : super(key: key);

  void _showPanel(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _UploadTaskSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<UploadProvider>(
      builder: (context, provider, child) {
        if (provider.tasks.isEmpty) {
          return const SizedBox.shrink();
        }

        final activeTasks = provider.tasks.where((task) {
          return task.status == UploadStatus.uploading ||
                 task.status == UploadStatus.pending;
        }).toList();

        if (activeTasks.isEmpty) {
          return const SizedBox.shrink();
        }

        return Positioned(
          bottom: 80,
          right: 16,
          child: NeumorphicButton(
            onPressed: () => _showPanel(context),
            style: NeumorphicStyle(
              depth: 6,
              intensity: 0.8,
              boxShape: NeumorphicBoxShape.roundRect(
                BorderRadius.circular(24),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text('上传中 ${activeTasks.length}'),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 上传任务底部面板
class _UploadTaskSheet extends StatefulWidget {
  const _UploadTaskSheet();

  @override
  State<_UploadTaskSheet> createState() => _UploadTaskSheetState();
}

class _UploadTaskSheetState extends State<_UploadTaskSheet> {
  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final uploadProvider = Provider.of<UploadProvider>(context, listen: false);

    if (authProvider.apiService != null) {
      await uploadProvider.loadTasks(authProvider.apiService!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
      decoration: BoxDecoration(
        color: NeumorphicTheme.baseColor(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // 顶部拖动条
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // 标题栏
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '上传任务',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                NeumorphicButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: const NeumorphicStyle(
                    boxShape: NeumorphicBoxShape.circle(),
                    depth: 2,
                  ),
                  padding: const EdgeInsets.all(8),
                  child: const Icon(Icons.close, size: 20),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // 任务列表
          Expanded(
            child: Consumer<UploadProvider>(
              builder: (context, provider, child) {
                if (provider.isLoading && provider.tasks.isEmpty) {
                  return const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF171717)),
                    ),
                  );
                }

                if (provider.tasks.isEmpty) {
                  return const Center(
                    child: Text('暂无上传任务'),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: provider.tasks.length,
                  itemBuilder: (context, index) {
                    return _UploadTaskItem(task: provider.tasks[index]);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 上传任务项
class _UploadTaskItem extends StatelessWidget {
  final UploadTask task;

  const _UploadTaskItem({required this.task});

  Future<void> _handleDelete(BuildContext context) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final uploadProvider = Provider.of<UploadProvider>(context, listen: false);

    if (authProvider.apiService != null) {
      await uploadProvider.deleteTask(authProvider.apiService!, task.id);
    }
  }

  Color _getStatusColor() {
    switch (task.status) {
      case UploadStatus.completed:
        return Colors.green;
      case UploadStatus.failed:
        return Colors.red;
      case UploadStatus.uploading:
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  String _getStatusText() {
    switch (task.status) {
      case UploadStatus.completed:
        return '已完成';
      case UploadStatus.failed:
        return '失败';
      case UploadStatus.uploading:
        return '上传中';
      default:
        return '等待中';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Neumorphic(
      margin: const EdgeInsets.only(bottom: 12),
      style: NeumorphicStyle(
        depth: 2,
        intensity: 0.6,
        boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(12)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  task.fileName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _getStatusColor().withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _getStatusText(),
                  style: TextStyle(
                    fontSize: 12,
                    color: _getStatusColor(),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (task.status == UploadStatus.completed ||
                  task.status == UploadStatus.failed)
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => _handleDelete(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
            ],
          ),

          if (task.status == UploadStatus.uploading) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: task.progress / 100,
              backgroundColor: Colors.grey[300],
              valueColor: AlwaysStoppedAnimation<Color>(_getStatusColor()),
            ),
            const SizedBox(height: 4),
            Text(
              '${task.progress.toStringAsFixed(1)}%',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],

          if (task.error != null) ...[
            const SizedBox(height: 4),
            Text(
              task.error!,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.red,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}
