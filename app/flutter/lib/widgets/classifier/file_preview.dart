import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart';
import 'package:provider/provider.dart';
import '../../models/classifier_file.dart';
import '../../providers/auth_provider.dart';
import '../../utils/theme_colors.dart';
import '../video/video_player_widget.dart';

/// 文件预览组件
class FilePreview extends StatefulWidget {
  final ClassifierFile file;
  final bool useThumbnail;
  final VoidCallback onToggleThumbnail;
  final int currentCount;
  final int totalCount;
  final double progress;
  final bool showControls;
  final VoidCallback onToggleControls;

  const FilePreview({
    Key? key,
    required this.file,
    required this.useThumbnail,
    required this.onToggleThumbnail,
    required this.currentCount,
    required this.totalCount,
    required this.progress,
    required this.showControls,
    required this.onToggleControls,
  }) : super(key: key);

  @override
  State<FilePreview> createState() => _FilePreviewState();
}

class _FilePreviewState extends State<FilePreview> {

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onToggleControls,
      child: Container(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 文件预览 - 充满整个空间
            _buildFileContent(),

            // 底部进度条（可隐藏）
            if (widget.showControls)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _buildProgressBar(),
              ),
          ],
        ),
      ),
    );
  }

  /// 构建文件内容（图片/视频）
  Widget _buildFileContent() {
    final authProvider = Provider.of<AuthProvider>(context);
    if (authProvider.apiService == null) {
      return _buildPlaceholder(Icons.error_outline);
    }

    // 图片预览
    if (widget.file.isImage) {
      // GIF 始终加载原图以显示动画
      if (widget.file.isGif) {
        return _buildImage(
          authProvider.apiService!.classifier.getFileUrl(widget.file.path),
        );
      }

      // 其他图片根据设置选择缩略图或原图
      final imageUrl = widget.useThumbnail
          ? authProvider.apiService!.classifier.getThumbnailUrl(widget.file.path)
          : authProvider.apiService!.classifier.getFileUrl(widget.file.path);

      return _buildImage(imageUrl);
    }

    // 视频预览
    if (widget.file.isVideo) {
      // 缩略图模式：显示首帧
      if (widget.useThumbnail) {
        return _buildVideoThumbnail(
          authProvider.apiService!.classifier.getThumbnailUrl(widget.file.path),
        );
      }

      // 原图模式：使用新的视频播放器组件（简化模式）
      return VideoPlayerWidget(
        key: ValueKey('classifier_video_${widget.file.path}'),
        videoUrl: authProvider.apiService!.classifier.getFileUrl(widget.file.path),
        apiKey: authProvider.currentServer?.apiKey ?? '',
        autoPlay: false,
        simpleMode: true, // 简化模式：只显示中间的播放/暂停按钮
        externalControlsVisible: widget.showControls, // 外部控制的显示状态
        onControlsVisibilityChanged: (visible) {
          // 简化模式下，当视频播放器控件状态改变时通知父组件
          if (!visible && widget.showControls || visible && !widget.showControls) {
            widget.onToggleControls();
          }
        },
      );
    }

    return _buildPlaceholder(Icons.insert_drive_file);
  }

  /// 构建图片组件
  Widget _buildImage(String imageUrl) {
    final authProvider = Provider.of<AuthProvider>(context);

    return InteractiveViewer(
      minScale: 0.5,
      maxScale: 4.0,
      child: Center(
        child: Image.network(
          imageUrl,
          fit: BoxFit.contain,
          width: double.infinity,
          height: double.infinity,
          headers: {
            'Cookie': 'api_key=${authProvider.apiService?.apiKey ?? ''}',
          },
          errorBuilder: (context, error, stackTrace) {
            return _buildPlaceholder(Icons.broken_image);
          },
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return _buildPlaceholder(Icons.image);
          },
        ),
      ),
    );
  }

  /// 构建视频缩略图
  Widget _buildVideoThumbnail(String thumbnailUrl) {
    final authProvider = Provider.of<AuthProvider>(context);

    return Center(
      child: Image.network(
        thumbnailUrl,
        fit: BoxFit.contain,
        width: double.infinity,
        height: double.infinity,
        headers: {
          'Cookie': 'api_key=${authProvider.apiService?.apiKey ?? ''}',
        },
        errorBuilder: (context, error, stackTrace) {
          return _buildPlaceholder(Icons.play_circle_outline);
        },
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return _buildPlaceholder(Icons.videocam);
        },
      ),
    );
  }

  /// 占位符
  Widget _buildPlaceholder(IconData icon) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.grey[800],
      child: Center(
        child: Icon(
          icon,
          size: 64,
          color: Colors.grey[500],
        ),
      ),
    );
  }

  /// 底部进度条区域
  Widget _buildProgressBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withOpacity(0.7),
            Colors.transparent,
          ],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 进度信息和缩略图开关
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${widget.currentCount} / ${widget.totalCount}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              Row(
                children: [
                  Icon(
                    Icons.photo_size_select_actual_outlined,
                    size: 18,
                    color: Colors.white.withOpacity(0.8),
                  ),
                  const SizedBox(width: 8),
                  NeumorphicSwitch(
                    value: widget.useThumbnail,
                    onChanged: (_) => widget.onToggleThumbnail(),
                    height: 24,
                    style: const NeumorphicSwitchStyle(
                      thumbDepth: 4,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 进度条
          NeumorphicProgress(
            height: 10,
            percent: widget.progress.clamp(0.0, 1.0),
            style: ProgressStyle(
              depth: -4,
              border: NeumorphicBorder.none(),
              accent: Colors.grey[700]!,
              variant: Colors.white.withOpacity(0.3),
            ),
          ),
        ],
      ),
    );
  }
}
