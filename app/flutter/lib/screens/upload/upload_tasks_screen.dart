import 'dart:async';
import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart';
import 'package:provider/provider.dart';
import '../../models/upload_task.dart';
import '../../providers/auth_provider.dart';
import '../../providers/upload_provider.dart';
import '../../widgets/common/neumorphic_option_sheet.dart';

/// 上传任务列表页面
class UploadTasksScreen extends StatefulWidget {
  const UploadTasksScreen({Key? key}) : super(key: key);

  @override
  State<UploadTasksScreen> createState() => _UploadTasksScreenState();
}

class _UploadTasksScreenState extends State<UploadTasksScreen> {
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

  Future<void> _deleteTask(String taskId) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final uploadProvider = Provider.of<UploadProvider>(context, listen: false);

    if (authProvider.apiService != null) {
      await uploadProvider.deleteTask(authProvider.apiService!, taskId);
    }
  }

  Future<void> _clearFinishedTasks() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final uploadProvider = Provider.of<UploadProvider>(context, listen: false);

    if (authProvider.apiService != null) {
      final result = await uploadProvider.clearFinishedTasks(authProvider.apiService!);
      if (mounted && result > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已清除 $result 个任务'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  /// 显示选择上传方式弹窗
  void _showUploadOptions() {
    NeumorphicOptionSheet.show(
      context: context,
      title: '选择上传方式',
      options: [
        SheetOption(
          icon: Icons.photo_library,
          text: '从相册选择',
          onTap: () => _pickFromGallery(),
        ),
        SheetOption(
          icon: Icons.camera_alt,
          text: '拍照',
          onTap: () => _takePhoto(),
        ),
        SheetOption(
          icon: Icons.folder,
          text: '从文件选择',
          onTap: () => _pickFromFiles(),
        ),
      ],
    );
  }

  /// 从相册选择（待实现）
  void _pickFromGallery() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('从相册选择功能即将推出')),
    );
  }

  /// 拍照（待实现）
  void _takePhoto() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('拍照功能即将推出')),
    );
  }

  /// 从文件选择（待实现）
  void _pickFromFiles() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('从文件选择功能即将推出')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NeumorphicTheme.baseColor(context),
      appBar: NeumorphicAppBar(
          title: const Text(
            '上传任务',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          leading: NeumorphicButton(
            onPressed: () => Navigator.of(context).pop(),
            style: const NeumorphicStyle(
              boxShape: NeumorphicBoxShape.circle(),
              depth: 3,
            ),
            padding: const EdgeInsets.all(12),
            child: const Icon(Icons.arrow_back, size: 20),
          ),
          actions: [
            Consumer<UploadProvider>(
              builder: (context, provider, child) {
                // 检查是否有已完成或失败的任务
                final hasFinishedTasks = provider.tasks.any((t) =>
                    t.status == UploadStatus.completed ||
                    t.status == UploadStatus.failed);

                if (!hasFinishedTasks) {
                  return const SizedBox.shrink();
                }

                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: NeumorphicButton(
                    onPressed: _clearFinishedTasks,
                    style: const NeumorphicStyle(
                      depth: 3,
                      boxShape: NeumorphicBoxShape.circle(),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: const Icon(
                      Icons.delete_sweep,
                      size: 20,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        body: Consumer<UploadProvider>(
          builder: (context, provider, child) {
            if (provider.isLoading && provider.tasks.isEmpty) {
              return const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF171717)),
                ),
              );
            }

            if (provider.tasks.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.cloud_upload_outlined,
                      size: 64,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '暂无上传任务',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: provider.tasks.length,
              itemBuilder: (context, index) {
                final task = provider.tasks[index];
                return _buildTaskItem(task);
              },
            );
          },
        ),
      );
  }

  Widget _buildTaskItem(UploadTask task) {
    final statusText = _getStatusText(task.status);
    final statusColor = _getStatusColor(task.status);
    final sizeText = _formatFileSize(task.uploadedSize) +
        (task.fileSize > 0 ? ' / ${_formatFileSize(task.fileSize)}' : '');

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Neumorphic(
        style: NeumorphicStyle(
          depth: 4,
          intensity: 0.6,
          boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(12)),
        ),
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 文件名和操作按钮
              Row(
                children: [
                  Expanded(
                    child: Text(
                      task.fileName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF171717),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (task.status == UploadStatus.completed ||
                      task.status == UploadStatus.failed)
                    NeumorphicButton(
                      onPressed: () => _deleteTask(task.id),
                      style: const NeumorphicStyle(
                        boxShape: NeumorphicBoxShape.circle(),
                        depth: 2,
                      ),
                      padding: const EdgeInsets.all(8),
                      child: const Icon(Icons.delete_outline, size: 18),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              // 状态和大小
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      statusText,
                      style: TextStyle(
                        fontSize: 12,
                        color: statusColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    sizeText,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // 进度条
              Stack(
                children: [
                  Neumorphic(
                    style: NeumorphicStyle(
                      depth: -2,
                      intensity: 0.8,
                      boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(4)),
                    ),
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: (task.progress / 100).clamp(0.0, 1.0),
                      child: Container(
                        decoration: BoxDecoration(
                          color: statusColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              // 错误信息
              if (task.error != null) ...[
                const SizedBox(height: 8),
                Text(
                  task.error!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.red,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _getStatusText(UploadStatus status) {
    switch (status) {
      case UploadStatus.pending:
        return '等待中';
      case UploadStatus.uploading:
        return '上传中';
      case UploadStatus.completed:
        return '已完成';
      case UploadStatus.failed:
        return '失败';
    }
  }

  Color _getStatusColor(UploadStatus status) {
    switch (status) {
      case UploadStatus.pending:
        return Colors.orange;
      case UploadStatus.uploading:
        return Colors.blue;
      case UploadStatus.completed:
        return Colors.green;
      case UploadStatus.failed:
        return Colors.red;
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(2)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
