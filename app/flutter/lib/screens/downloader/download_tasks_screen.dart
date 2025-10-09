import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/downloader_provider.dart';
import '../../models/download_task.dart';
import '../../models/gallery_file.dart';
import '../../utils/theme_colors.dart';
import '../../widgets/common/neumorphic_toast.dart';
import '../../widgets/common/neumorphic_option_sheet.dart';
import '../../widgets/common/neumorphic_overlay_appbar.dart';
import '../gallery/image_detail_screen.dart';

/// 下载任务列表页面
class DownloadTasksScreen extends StatefulWidget {
  const DownloadTasksScreen({Key? key}) : super(key: key);

  @override
  State<DownloadTasksScreen> createState() => _DownloadTasksScreenState();
}

class _DownloadTasksScreenState extends State<DownloadTasksScreen> {

  /// 预览文件
  void _previewFile(BuildContext context, DownloadTask task) {
    if (task.filePath == null) {
      NeumorphicToast.showError(context, '文件路径不存在');
      return;
    }

    final extension = task.filePath!.split('.').last.toLowerCase();

    String fileType;
    if (extension == 'gif') {
      fileType = 'gif';
    } else if (['jpg', 'jpeg', 'png', 'webp', 'bmp'].contains(extension)) {
      fileType = 'image';
    } else if (['mp4', 'webm', 'mov', 'avi', 'mkv', 'm4v'].contains(extension)) {
      fileType = 'video';
    } else {
      fileType = 'unknown';
    }

    final galleryFile = GalleryFile(
      name: task.fileName ?? task.filePath!.split('/').last,
      path: task.filePath!,
      fileType: fileType,
      extension: extension,
      size: 0,
      modifiedTime: task.completedAt?.toIso8601String() ?? '',
    );

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ImageDetailScreen(
          files: [galleryFile],
          initialIndex: 0,
        ),
      ),
    );
  }

  /// 删除任务
  Future<void> _deleteTask(BuildContext context, DownloadTask task) async {
    final downloaderProvider =
        Provider.of<DownloaderProvider>(context, listen: false);

    final success = await downloaderProvider.deleteTask(task.id);
    if (success) {
      NeumorphicToast.showSuccess(context, '任务已删除');
    } else {
      NeumorphicToast.showError(context, '删除任务失败');
    }
  }

  /// 清空历史记录
  Future<void> _clearHistory(BuildContext context) async {
    final downloaderProvider =
        Provider.of<DownloaderProvider>(context, listen: false);

    final success = await downloaderProvider.clearHistory();
    if (success) {
      NeumorphicToast.showSuccess(context, '历史已清空');
    } else {
      NeumorphicToast.showError(context, '清空历史失败');
    }
  }

  /// 显示任务操作菜单
  void _showTaskOptions(BuildContext context, DownloadTask task) {
    final options = <SheetOption>[];

    // 预览（已完成的任务）
    if (task.isCompleted && task.filePath != null) {
      options.add(
        SheetOption(
          icon: Icons.visibility,
          text: '预览',
          onTap: () => _previewFile(context, task),
          iconColor: ThemeColors.text(context),
          textColor: ThemeColors.text(context),
        ),
      );
    }

    // 删除
    options.add(
      SheetOption(
        icon: Icons.delete,
        text: '删除',
        onTap: () => _deleteTask(context, task),
        iconColor: ThemeColors.text(context),
        textColor: ThemeColors.text(context),
      ),
    );

    NeumorphicOptionSheet.show(
      context: context,
      options: options,
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);

    if (authProvider.apiService == null) {
      return Scaffold(
        backgroundColor: NeumorphicTheme.baseColor(context),
        body: Center(
          child: Text(
            '请先连接服务器',
            style: TextStyle(
              fontSize: 16,
              color: ThemeColors.textSecondary(context),
            ),
          ),
        ),
      );
    }

    return ChangeNotifierProvider(
      create: (_) => DownloaderProvider(authProvider.apiService!)..initialize(),
      child: Scaffold(
        backgroundColor: NeumorphicTheme.baseColor(context),
        body: SafeArea(
          child: Stack(
            children: [
              // 任务列表内容
              Positioned.fill(
                child: Consumer<DownloaderProvider>(
                  builder: (context, provider, _) {
                    if (provider.tasks.isEmpty) {
                      return _buildEmptyState(context);
                    }

                    return RefreshIndicator(
                      onRefresh: () => provider.loadTasks(),
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 80, 16, 16),
                        itemCount: provider.tasks.length,
                        itemBuilder: (context, index) {
                          final task = provider.tasks[index];
                          return _buildTaskItem(context, task);
                        },
                      ),
                    );
                  },
                ),
              ),

              // 顶部标题栏
              NeumorphicOverlayAppBar(
                title: '下载列表',
                leading: NeumorphicButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: const NeumorphicStyle(
                    depth: 4,
                    boxShape: NeumorphicBoxShape.circle(),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Icon(
                    Icons.arrow_back,
                    size: 20,
                    color: ThemeColors.text(context),
                  ),
                ),
                trailing: Consumer<DownloaderProvider>(
                  builder: (context, provider, _) {
                    // 只有有已完成的任务时才显示清除按钮
                    if (provider.completedTaskCount > 0) {
                      return NeumorphicButton(
                        onPressed: () => _clearHistory(context),
                        style: const NeumorphicStyle(
                          depth: 4,
                          boxShape: NeumorphicBoxShape.circle(),
                        ),
                        padding: const EdgeInsets.all(12),
                        child: Icon(
                          Icons.delete_sweep,
                          size: 20,
                          color: ThemeColors.text(context),
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建空状态
  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.download_outlined,
            size: 64,
            color: ThemeColors.text(context).withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            '暂无下载任务',
            style: TextStyle(
              fontSize: 16,
              color: ThemeColors.text(context).withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建单个任务项
  Widget _buildTaskItem(BuildContext context, DownloadTask task) {
    return GestureDetector(
      onTap: () => _showTaskOptions(context, task),
      child: Neumorphic(
        margin: const EdgeInsets.only(bottom: 12),
        style: NeumorphicStyle(
          depth: 2,
          intensity: 0.5,
          boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(16)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 第一行：名称 + 状态图标
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      _getTaskName(task),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: ThemeColors.text(context),
                      ),
                      maxLines: 3,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildStatusIcon(context, task),
                ],
              ),

              const SizedBox(height: 10),

              // 第二行：网站 + 文件夹
              Row(
                children: [
                  Icon(
                    Icons.public,
                    size: 12,
                    color: ThemeColors.text(context).withOpacity(0.5),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    task.platform,
                    style: TextStyle(
                      fontSize: 11,
                      color: ThemeColors.text(context).withOpacity(0.6),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(
                    Icons.folder,
                    size: 12,
                    color: ThemeColors.text(context).withOpacity(0.5),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _getTaskFolder(task),
                      style: TextStyle(
                        fontSize: 11,
                        color: ThemeColors.text(context).withOpacity(0.6),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),

              // 进度条（下载中时显示）
              if (task.isActive) ...[
                const SizedBox(height: 10),
                NeumorphicProgress(
                  height: 6,
                  percent: (task.progress / 100).clamp(0.0, 1.0),
                  style: ProgressStyle(
                    depth: -2,
                    border: NeumorphicBorder.none(),
                    accent: ThemeColors.text(context),
                    variant: ThemeColors.text(context).withOpacity(0.15),
                  ),
                ),
              ],

              // 错误信息（失败时显示）
              if (task.error != null) ...[
                const SizedBox(height: 8),
                Text(
                  task.error!,
                  style: TextStyle(
                    fontSize: 11,
                    color: ThemeColors.text(context).withOpacity(0.6),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 获取任务名称
  String _getTaskName(DownloadTask task) {
    if (task.isCompleted && task.fileName != null) {
      return task.fileName!;
    }
    return task.url;
  }

  /// 获取任务文件夹（仅显示最后一级目录名）
  String _getTaskFolder(DownloadTask task) {
    if (task.filePath != null) {
      final parts = task.filePath!.split('/');
      if (parts.length > 1) {
        parts.removeLast(); // 移除文件名
        return parts.last; // 返回最后一个文件夹名
      }
    }
    return task.saveFolder ?? '源文件夹';
  }

  /// 构建状态图标
  Widget _buildStatusIcon(BuildContext context, DownloadTask task) {
    if (task.status == 'pending' ||
        (task.status == 'downloading' && task.progress == 0)) {
      // 准备中
      return SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(
            ThemeColors.text(context).withOpacity(0.6),
          ),
        ),
      );
    } else if (task.status == 'downloading' && task.progress > 0) {
      // 下载中 - 显示百分比
      return Text(
        '${task.progress.toInt()}%',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: ThemeColors.text(context),
        ),
      );
    } else {
      // 其他状态 - 使用 Neumorphic 图标
      return Neumorphic(
        style: NeumorphicStyle(
          depth: task.status == 'completed' ? -1 : 1,
          intensity: 0.5,
          boxShape: const NeumorphicBoxShape.circle(),
        ),
        padding: const EdgeInsets.all(4),
        child: Icon(
          _getStatusIconData(task.status),
          size: 14,
          color: ThemeColors.text(context),
        ),
      );
    }
  }

  /// 获取状态图标
  IconData _getStatusIconData(String status) {
    switch (status) {
      case 'completed':
        return Icons.check;
      case 'failed':
        return Icons.close;
      case 'cancelled':
        return Icons.remove;
      default:
        return Icons.help_outline;
    }
  }
}
