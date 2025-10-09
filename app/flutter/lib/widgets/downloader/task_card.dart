import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart';
import '../../models/download_task.dart';
import '../../utils/theme_colors.dart';

/// 下载任务卡片组件
class TaskCard extends StatelessWidget {
  final DownloadTask task;
  final VoidCallback? onCancel;
  final VoidCallback? onDelete;
  final VoidCallback? onPreview;
  final VoidCallback? onOpenFolder;

  const TaskCard({
    Key? key,
    required this.task,
    this.onCancel,
    this.onDelete,
    this.onPreview,
    this.onOpenFolder,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Neumorphic(
      margin: const EdgeInsets.only(bottom: 12),
      style: NeumorphicStyle(
        depth: 2,
        intensity: 0.6,
        boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(16)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 顶部：URL/文件名 + 状态图标
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    _getDisplayName(),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: ThemeColors.text(context),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                _buildStatusIndicator(context),
              ],
            ),

            const SizedBox(height: 12),

            // 元信息：平台、文件夹、速度、ETA
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _buildMetaItem(context, Icons.public, task.platform),
                _buildMetaItem(
                  context,
                  Icons.folder_outlined,
                  _getFolderDisplay(),
                  maxWidth: 120, // 限制文件夹名称宽度
                ),
                if (task.speed != null)
                  _buildMetaItem(context, Icons.speed, task.speed!),
                if (task.eta != null)
                  _buildMetaItem(context, Icons.schedule, task.eta!),
              ],
            ),

            // 进度条（下载中/准备中时显示）
            if (task.isActive) ...[
              const SizedBox(height: 12),
              _buildProgressBar(context),
            ],

            // 错误信息（失败时显示）
            if (task.error != null) ...[
              const SizedBox(height: 10),
              Text(
                task.error!,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.red[700],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],

            // 操作按钮
            if (_hasActions) ...[
              const SizedBox(height: 12),
              _buildActions(context),
            ],
          ],
        ),
      ),
    );
  }

  /// 获取显示名称（完成时显示文件名，否则显示简化的URL）
  String _getDisplayName() {
    if (task.isCompleted && task.fileName != null) {
      return task.fileName!;
    }

    // 简化URL显示：移除协议和www前缀
    String url = task.url;
    url = url.replaceFirst(RegExp(r'^https?://'), '');
    url = url.replaceFirst(RegExp(r'^www\.'), '');

    // 如果URL很长，截取关键部分
    if (url.length > 60) {
      final uri = Uri.tryParse(task.url);
      if (uri != null) {
        // 显示：域名/...路径片段?参数
        final host = uri.host.replaceFirst(RegExp(r'^www\.'), '');
        final pathSegments = uri.pathSegments;
        if (pathSegments.isNotEmpty) {
          final lastSegment = pathSegments.last;
          return '$host/.../$lastSegment';
        }
        return host;
      }
    }

    return url;
  }

  /// 获取文件夹显示
  String _getFolderDisplay() {
    if (task.filePath != null) {
      final parts = task.filePath!.split('/');
      if (parts.length > 1) {
        parts.removeLast(); // 移除文件名
        return parts.join('/');
      }
    }
    return task.saveFolder ?? '源文件夹';
  }

  /// 构建状态指示器
  Widget _buildStatusIndicator(BuildContext context) {
    if (task.status == 'pending' ||
        (task.status == 'downloading' && task.progress == 0)) {
      // 准备中 - 显示旋转加载动画
      return SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(
            ThemeColors.text(context).withOpacity(0.5),
          ),
        ),
      );
    } else if (task.status == 'downloading' && task.progress > 0) {
      // 下载中 - 显示百分比
      return Text(
        '${task.progress.toInt()}%',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: ThemeColors.text(context),
        ),
      );
    } else {
      // 其他状态 - 显示图标
      return Icon(
        _getStatusIcon(),
        size: 20,
        color: _getStatusColor(context),
      );
    }
  }

  /// 获取状态图标
  IconData _getStatusIcon() {
    switch (task.status) {
      case 'completed':
        return Icons.check_circle;
      case 'failed':
        return Icons.error;
      case 'cancelled':
        return Icons.cancel;
      default:
        return Icons.help;
    }
  }

  /// 获取状态颜色
  Color _getStatusColor(BuildContext context) {
    switch (task.status) {
      case 'completed':
        return Colors.green;
      case 'failed':
        return Colors.red;
      case 'cancelled':
        return Colors.orange;
      default:
        return ThemeColors.textSecondary(context);
    }
  }

  /// 构建元信息项
  Widget _buildMetaItem(
    BuildContext context,
    IconData icon,
    String text, {
    double? maxWidth,
  }) {
    final textWidget = Text(
      text,
      style: TextStyle(
        fontSize: 12,
        color: ThemeColors.textSecondary(context),
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: ThemeColors.textSecondary(context),
        ),
        const SizedBox(width: 4),
        if (maxWidth != null)
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: textWidget,
          )
        else
          textWidget,
      ],
    );
  }

  /// 构建进度条
  Widget _buildProgressBar(BuildContext context) {
    return NeumorphicProgress(
      height: 8,
      percent: (task.progress / 100).clamp(0.0, 1.0),
      style: ProgressStyle(
        depth: -2,
        border: NeumorphicBorder.none(),
        accent: ThemeColors.text(context),
        variant: ThemeColors.textSecondary(context).withOpacity(0.2),
      ),
    );
  }

  /// 是否有操作按钮
  bool get _hasActions =>
      onCancel != null || onDelete != null || onPreview != null || onOpenFolder != null;

  /// 构建操作按钮
  Widget _buildActions(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        // 取消按钮（进行中时显示）
        if (task.canCancel && onCancel != null)
          _buildActionButton(
            context: context,
            icon: Icons.cancel,
            label: '取消',
            onPressed: onCancel!,
          ),

        // 预览按钮（已完成时显示）
        if (task.isCompleted && task.filePath != null && onPreview != null)
          _buildActionButton(
            context: context,
            icon: Icons.visibility,
            label: '预览',
            onPressed: onPreview!,
          ),

        // 打开文件夹按钮（已完成时显示）
        if (task.isCompleted && task.filePath != null && onOpenFolder != null)
          _buildActionButton(
            context: context,
            icon: Icons.folder_open,
            label: '打开',
            onPressed: onOpenFolder!,
          ),

        // 删除按钮（非进行中时显示）
        if (task.canDelete && onDelete != null)
          _buildActionButton(
            context: context,
            icon: Icons.delete,
            label: '删除',
            onPressed: onDelete!,
            textColor: Colors.red[700],
          ),
      ],
    );
  }

  /// 构建单个操作按钮
  Widget _buildActionButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    Color? textColor,
  }) {
    return NeumorphicButton(
      onPressed: onPressed,
      style: NeumorphicStyle(
        depth: 2,
        intensity: 0.6,
        boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(8)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: textColor ?? ThemeColors.text(context),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: textColor ?? ThemeColors.text(context),
            ),
          ),
        ],
      ),
    );
  }
}
