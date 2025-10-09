import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart';
import 'package:provider/provider.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../models/classifier_file.dart';
import '../../providers/auth_provider.dart';
import '../../utils/theme_colors.dart';

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
  Player? _player;
  VideoController? _videoController;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  @override
  void didUpdateWidget(FilePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 文件变化或缩略图开关变化时，重新初始化视频
    if (oldWidget.file.path != widget.file.path ||
        oldWidget.useThumbnail != widget.useThumbnail) {
      _disposeVideo();
      _initializeVideo();
    }
  }

  @override
  void dispose() {
    _disposeVideo();
    super.dispose();
  }

  void _initializeVideo() {
    // 只有非缩略图模式且是视频文件才初始化播放器
    if (!widget.useThumbnail && widget.file.isVideo) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      if (authProvider.apiService != null) {
        _player = Player();
        _videoController = VideoController(_player!);

        final videoUrl = authProvider.apiService!.classifier.getFileUrl(widget.file.path);
        _player!.open(Media(videoUrl), play: false);
      }
    }
  }

  void _disposeVideo() {
    _player?.dispose();
    _player = null;
    _videoController = null;
  }

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

      // 原图模式：播放视频
      if (_videoController != null) {
        return _buildVideoPlayer();
      }
      return _buildPlaceholder(Icons.videocam);
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

    return Stack(
      fit: StackFit.expand,
      alignment: Alignment.center,
      children: [
        Center(
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
        ),
        // 播放图标叠加层
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.5),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.play_arrow,
            size: 48,
            color: Colors.white.withOpacity(0.9),
          ),
        ),
      ],
    );
  }

  /// 构建视频播放器
  Widget _buildVideoPlayer() {
    return Video(
      controller: _videoController!,
      controls: MaterialVideoControls,
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
