import 'dart:async';
import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart';
import 'package:provider/provider.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../models/gallery_file.dart';
import '../../providers/auth_provider.dart';

/// 图片详情预览页面
class ImageDetailScreen extends StatefulWidget {
  final List<GalleryFile> files;
  final int initialIndex;

  const ImageDetailScreen({
    Key? key,
    required this.files,
    required this.initialIndex,
  }) : super(key: key);

  @override
  State<ImageDetailScreen> createState() => _ImageDetailScreenState();
}

class _ImageDetailScreenState extends State<ImageDetailScreen> {
  late PageController _pageController;
  late int _currentIndex;
  Player? _videoPlayer;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _videoPlayer?.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentIndex = index;
      // 切换页面时停止并释放之前的视频
      _videoPlayer?.dispose();
      _videoPlayer = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final file = widget.files[_currentIndex];

    return NeumorphicTheme(
      theme: const NeumorphicThemeData(
        baseColor: Color(0xFFF0F0F0),
        lightSource: LightSource.topLeft,
        depth: 4,
        intensity: 0.6,
      ),
      child: Scaffold(
        backgroundColor: NeumorphicTheme.baseColor(context),
        appBar: NeumorphicAppBar(
          title: Text(
            file.name,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
            NeumorphicButton(
              onPressed: () => _showFileInfoBubble(context, file),
              style: const NeumorphicStyle(
                boxShape: NeumorphicBoxShape.circle(),
                depth: 3,
              ),
              padding: const EdgeInsets.all(12),
              child: const Icon(Icons.info_outline, size: 20),
            ),
          ],
        ),
        body: Stack(
          children: [
            // 主内容区域 - PageView
            PageView.builder(
              controller: _pageController,
              onPageChanged: _onPageChanged,
              physics: const NeverScrollableScrollPhysics(), // 禁用滑动手势
              itemCount: widget.files.length,
              itemBuilder: (context, index) {
                return _buildMediaViewer(widget.files[index]);
              },
            ),

            // 底部控制栏
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: _buildBottomControls(),
            ),
          ],
        ),
      ),
    );
  }

  // 底部控制栏
  Widget _buildBottomControls() {
    final file = widget.files[_currentIndex];

    if (file.isVideo) {
      // 视频由 _VideoPlayer 组件内部处理控制栏
      return const SizedBox.shrink();
    } else {
      return _buildNavigationControls();
    }
  }

  // 图片/动图的导航控制
  Widget _buildNavigationControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // 上一张按钮
        NeumorphicButton(
          onPressed: _currentIndex > 0
              ? () {
                  _pageController.previousPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                }
              : null,
          style: const NeumorphicStyle(
            boxShape: NeumorphicBoxShape.circle(),
            depth: 4,
          ),
          padding: const EdgeInsets.all(16),
          child: Icon(
            Icons.chevron_left,
            size: 32,
            color: _currentIndex > 0 ? Colors.black87 : Colors.grey,
          ),
        ),

        // 下一张按钮
        NeumorphicButton(
          onPressed: _currentIndex < widget.files.length - 1
              ? () {
                  _pageController.nextPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                }
              : null,
          style: const NeumorphicStyle(
            boxShape: NeumorphicBoxShape.circle(),
            depth: 4,
          ),
          padding: const EdgeInsets.all(16),
          child: Icon(
            Icons.chevron_right,
            size: 32,
            color: _currentIndex < widget.files.length - 1 ? Colors.black87 : Colors.grey,
          ),
        ),
      ],
    );
  }


  // 显示文件信息气泡对话框
  void _showFileInfoBubble(BuildContext context, GalleryFile file) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.3),
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFFF0F0F0).withOpacity(0.95),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildInfoItem('文件名', file.name),
              const SizedBox(height: 16),
              _buildInfoItem('类型', file.extension.toUpperCase()),
              const SizedBox(height: 16),
              _buildInfoItem('大小', _formatFileSize(file.size)),
              const SizedBox(height: 16),
              _buildInfoItem('修改时间', file.modifiedTime),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 15,
            color: Color(0xFF171717),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
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

  Widget _buildMediaViewer(GalleryFile file) {
    final authProvider = Provider.of<AuthProvider>(context);
    final fileUrl = authProvider.apiService?.getImageUrl(file.path);

    if (fileUrl == null) {
      return const Center(
        child: Text(
          '无法加载文件',
          style: TextStyle(color: Colors.white),
        ),
      );
    }

    // 图片或GIF
    if (file.isImage || file.isGif) {
      return InteractiveViewer(
        minScale: 0.5,
        maxScale: 4.0,
        child: Center(
          child: Image.network(
            fileUrl,
            headers: {'Cookie': 'api_key=${authProvider.apiKey}'},
            fit: BoxFit.contain,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return const Center(
                child: CircularProgressIndicator(),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.broken_image,
                      size: 64,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '图片加载失败',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
    }

    // 视频
    if (file.isVideo) {
      return _VideoPlayer(
        videoUrl: fileUrl,
        apiKey: authProvider.apiKey ?? '',
        onPlayerCreated: (player) {
          _videoPlayer = player;
        },
        showNavigationButtons: widget.files.length > 1,
        currentIndex: _currentIndex,
        totalFiles: widget.files.length,
        onPrevious: _currentIndex > 0
            ? () {
                _pageController.previousPage(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                );
              }
            : null,
        onNext: _currentIndex < widget.files.length - 1
            ? () {
                _pageController.nextPage(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                );
              }
            : null,
      );
    }

    // 其他文件类型
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.insert_drive_file,
            size: 64,
            color: Colors.white54,
          ),
          const SizedBox(height: 16),
          Text(
            file.name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            file.extension.toUpperCase(),
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

/// 视频播放器组件
class _VideoPlayer extends StatefulWidget {
  final String videoUrl;
  final String apiKey;
  final Function(Player)? onPlayerCreated;
  final bool showNavigationButtons;
  final int currentIndex;
  final int totalFiles;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  const _VideoPlayer({
    required this.videoUrl,
    required this.apiKey,
    this.onPlayerCreated,
    this.showNavigationButtons = false,
    this.currentIndex = 0,
    this.totalFiles = 1,
    this.onPrevious,
    this.onNext,
  });

  @override
  State<_VideoPlayer> createState() => _VideoPlayerState();
}

class _VideoPlayerState extends State<_VideoPlayer> {
  late final Player _player;
  late final VideoController _videoController;
  bool _isInitialized = false;
  bool _hasError = false;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _volume = 1.0;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    try {
      print('开始初始化视频播放器: ${widget.videoUrl}');

      // 创建Player实例，配置选项
      _player = Player(
        configuration: const PlayerConfiguration(
          title: 'Video Player',
          // 启用日志以便调试
          logLevel: MPVLogLevel.info,
        ),
      );
      _videoController = VideoController(_player);

      widget.onPlayerCreated?.call(_player);

      bool hasError = false;

      // 监听错误
      _player.stream.error.listen((error) {
        print('视频播放错误: $error');
        if (mounted && !hasError) {
          hasError = true;
          setState(() => _hasError = true);
        }
      });

      // 监听缓冲状态
      _player.stream.buffering.listen((buffering) {
        print('视频缓冲状态: $buffering');
      });

      // 监听播放状态
      _player.stream.playing.listen((playing) {
        print('视频播放状态: $playing');
        if (mounted) {
          setState(() {
            _isPlaying = playing;
          });
        }
      });

      // 监听播放位置
      _player.stream.position.listen((position) {
        if (mounted) {
          setState(() => _position = position);
        }
      });

      // 监听播放时长
      _player.stream.duration.listen((duration) {
        print('视频时长: $duration');
        if (mounted) {
          setState(() => _duration = duration);
        }
      });

      // 监听音量
      _player.stream.volume.listen((volume) {
        if (mounted) {
          setState(() => _volume = volume);
        }
      });

      print('正在打开视频文件...');

      // 构建带 API key 的 URL（通过 URL 参数传递，比 HTTP headers 更可靠）
      final uri = Uri.parse(widget.videoUrl);
      final videoUrlWithKey = uri.replace(
        queryParameters: {
          ...uri.queryParameters,
          'key': widget.apiKey, // 后端中间件支持 'key' 参数
        },
      ).toString();

      print('视频 URL: $videoUrlWithKey');

      // 使用超时包装，不依赖 HTTP headers
      await _player.open(
        Media(videoUrlWithKey),
        play: false, // 先不自动播放，等初始化完成
      ).timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          print('视频加载超时');
          throw TimeoutException('视频加载超时');
        },
      );

      print('视频文件已打开，等待编解码器准备...');

      // 等待更长时间让视频完全初始化
      int waitCount = 0;
      while (waitCount < 30 && !hasError) {
        await Future.delayed(const Duration(milliseconds: 100));
        waitCount++;

        // 检查是否已经有 duration（说明视频信息已加载）
        if (_duration.inMilliseconds > 0) {
          print('视频信息已加载，duration: $_duration');
          break;
        }
      }

      if (hasError) {
        print('视频初始化过程中发生错误');
        return;
      }

      if (mounted) {
        print('视频播放器初始化成功');
        setState(() {
          _isInitialized = true;
        });

        // 等待一小段时间再播放，确保编解码器完全准备好
        await Future.delayed(const Duration(milliseconds: 200));

        if (mounted && !hasError) {
          print('开始播放视频');
          _player.play();
        }
      }
    } catch (e, stackTrace) {
      print('视频初始化失败: $e');
      print('堆栈: $stackTrace');
      if (mounted) {
        setState(() => _hasError = true);
      }
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  void _togglePlayPause() {
    if (_isPlaying) {
      _player.pause();
    } else {
      _player.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.white54,
            ),
            SizedBox(height: 16),
            Text(
              '视频加载失败',
              style: TextStyle(color: Colors.white54),
            ),
          ],
        ),
      );
    }

    if (!_isInitialized) {
      return const Center(
        child: CircularProgressIndicator(
          color: Colors.white,
        ),
      );
    }

    return Stack(
      children: [
        // 视频播放器
        Center(
          child: Video(
            controller: _videoController,
            controls: NoVideoControls,
          ),
        ),

        // 点击区域用于播放/暂停
        Positioned.fill(
          child: GestureDetector(
            onTap: _togglePlayPause,
            behavior: HitTestBehavior.translucent,
          ),
        ),

        // 底部控制栏
        Positioned(
          bottom: 20,
          left: 20,
          right: 20,
          child: _buildBottomControls(),
        ),
      ],
    );
  }

  Widget _buildBottomControls() {
    final progress = _duration.inMilliseconds > 0
        ? _position.inMilliseconds / _duration.inMilliseconds
        : 0.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 进度条
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: NeumorphicSlider(
            value: progress.clamp(0.0, 1.0),
            onChanged: (value) {
              final seekDuration = _duration * value;
              _player.seek(seekDuration);
            },
            style: SliderStyle(
              depth: -2,
              variant: Colors.grey[800],
            ),
            min: 0,
            max: 1,
          ),
        ),
        const SizedBox(height: 12),
        // 控制按钮
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 上一个视频按钮（如果有多个文件）
            if (widget.showNavigationButtons && widget.onPrevious != null)
              NeumorphicButton(
                onPressed: widget.onPrevious,
                style: const NeumorphicStyle(
                  boxShape: NeumorphicBoxShape.circle(),
                  depth: 4,
                ),
                padding: const EdgeInsets.all(14),
                child: const Icon(Icons.skip_previous, size: 24, color: Colors.black87),
              )
            else if (widget.showNavigationButtons)
              Opacity(
                opacity: 0.3,
                child: NeumorphicButton(
                  onPressed: null,
                  style: const NeumorphicStyle(
                    boxShape: NeumorphicBoxShape.circle(),
                    depth: 4,
                  ),
                  padding: const EdgeInsets.all(14),
                  child: Icon(Icons.skip_previous, size: 24, color: Colors.grey[400]),
                ),
              ),

            if (widget.showNavigationButtons) const SizedBox(width: 12),

            // 播放/暂停按钮
            NeumorphicButton(
              onPressed: _togglePlayPause,
              style: const NeumorphicStyle(
                boxShape: NeumorphicBoxShape.circle(),
                depth: 4,
              ),
              padding: const EdgeInsets.all(16),
              child: Icon(
                _isPlaying ? Icons.pause : Icons.play_arrow,
                size: 32,
                color: Colors.black87,
              ),
            ),

            const SizedBox(width: 12),

            // 静音按钮
            NeumorphicButton(
              onPressed: () {
                if (_volume > 0) {
                  _player.setVolume(0);
                } else {
                  _player.setVolume(100);
                }
              },
              style: const NeumorphicStyle(
                boxShape: NeumorphicBoxShape.circle(),
                depth: 4,
              ),
              padding: const EdgeInsets.all(14),
              child: Icon(
                _volume > 0 ? Icons.volume_up : Icons.volume_off,
                size: 24,
                color: Colors.black87,
              ),
            ),

            if (widget.showNavigationButtons) const SizedBox(width: 12),

            // 下一个视频按钮（如果有多个文件）
            if (widget.showNavigationButtons && widget.onNext != null)
              NeumorphicButton(
                onPressed: widget.onNext,
                style: const NeumorphicStyle(
                  boxShape: NeumorphicBoxShape.circle(),
                  depth: 4,
                ),
                padding: const EdgeInsets.all(14),
                child: const Icon(Icons.skip_next, size: 24, color: Colors.black87),
              )
            else if (widget.showNavigationButtons)
              Opacity(
                opacity: 0.3,
                child: NeumorphicButton(
                  onPressed: null,
                  style: const NeumorphicStyle(
                    boxShape: NeumorphicBoxShape.circle(),
                    depth: 4,
                  ),
                  padding: const EdgeInsets.all(14),
                  child: Icon(Icons.skip_next, size: 24, color: Colors.grey[400]),
                ),
              ),
          ],
        ),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }
}
