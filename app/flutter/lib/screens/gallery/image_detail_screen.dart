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

    return Scaffold(
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
            headers: {'Cookie': 'api_key=${authProvider.currentServer?.apiKey ?? ''}'},
            fit: BoxFit.contain,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF171717)),
                ),
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
        key: ValueKey(fileUrl), // 使用URL作为key，确保每个视频有独立的widget实例
        videoUrl: fileUrl,
        apiKey: authProvider.currentServer?.apiKey ?? '',
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
    Key? key,
    required this.videoUrl,
    required this.apiKey,
    this.onPlayerCreated,
    this.showNavigationButtons = false,
    this.currentIndex = 0,
    this.totalFiles = 1,
    this.onPrevious,
    this.onNext,
  }) : super(key: key);

  @override
  State<_VideoPlayer> createState() => _VideoPlayerState();
}

class _VideoPlayerState extends State<_VideoPlayer> {
  Player? _player;
  VideoController? _videoController;
  bool _isInitialized = false;
  bool _hasError = false;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _volume = 1.0;
  bool _showControls = true; // 控件显示状态
  Timer? _hideControlsTimer; // 自动隐藏控件的计时器
  bool _isDisposed = false; // 标记是否已dispose，防止在dispose后调用Player方法
  bool _playerDisposed = false; // 标记Player是否已经dispose

  @override
  void initState() {
    super.initState();
    // 立即初始化，所有异步操作中都有_isDisposed检查
    _initializeVideo();
    _startHideControlsTimer(); // 开始自动隐藏倒计时
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

      // 立即检查是否已dispose
      if (_isDisposed || !mounted) {
        print('Player创建后检测到widget已dispose，停止初始化');
        // 不在这里dispose，让widget的dispose方法统一处理
        return;
      }

      // 配置 VideoController，禁用硬件加速强制使用软件解码
      // 这样即使高分辨率视频硬件解码失败，也能通过软件解码播放
      _videoController = VideoController(
        _player!,
        configuration: const VideoControllerConfiguration(
          enableHardwareAcceleration: false, // 使用软件解码，兼容性更好
        ),
      );

      // 再次检查
      if (_isDisposed || !mounted) {
        print('VideoController创建后检测到widget已dispose，停止初始化');
        return;
      }

      widget.onPlayerCreated?.call(_player!);

      bool hasError = false;

      // 监听错误
      _player!.stream.error.listen((error) {
        print('视频播放错误: $error');
        if (!_isDisposed && mounted && !hasError) {
          hasError = true;
          setState(() => _hasError = true);
        }
      });

      // 监听缓冲状态
      _player!.stream.buffering.listen((buffering) {
        print('视频缓冲状态: $buffering');
      });

      // 监听播放状态
      _player!.stream.playing.listen((playing) {
        print('视频播放状态: $playing');
        if (!_isDisposed && mounted) {
          setState(() {
            _isPlaying = playing;
          });

          // 播放状态改变时的控件显示逻辑
          if (playing && _showControls) {
            // 如果开始播放且控件可见，启动自动隐藏计时器
            _startHideControlsTimer();
          } else if (!playing) {
            // 如果暂停，取消自动隐藏计时器并显示控件
            _hideControlsTimer?.cancel();
            setState(() => _showControls = true);
          }
        }
      });

      // 监听播放位置
      _player!.stream.position.listen((position) {
        if (!_isDisposed && mounted) {
          setState(() => _position = position);
        }
      });

      // 监听播放时长
      _player!.stream.duration.listen((duration) {
        print('视频时长: $duration');
        if (!_isDisposed && mounted) {
          setState(() => _duration = duration);
        }
      });

      // 监听音量
      _player!.stream.volume.listen((volume) {
        if (!_isDisposed && mounted) {
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
      await _player!.open(
        Media(videoUrlWithKey),
        play: false, // 先不自动播放，等初始化完成
      ).timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          print('视频加载超时');
          throw TimeoutException('视频加载超时');
        },
      );

      // 检查是否已dispose
      if (_isDisposed || !mounted) {
        print('视频打开后检测到widget已dispose，停止初始化');
        return;
      }

      print('视频文件已打开，等待编解码器准备...');

      // 等待更长时间让视频完全初始化
      int waitCount = 0;
      while (waitCount < 30 && !hasError && !_isDisposed) {
        await Future.delayed(const Duration(milliseconds: 100));
        waitCount++;

        // 再次检查是否已dispose
        if (_isDisposed || !mounted) {
          print('等待过程中检测到widget已dispose，停止初始化');
          return;
        }

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

      // 最终检查
      if (_isDisposed || !mounted) {
        print('准备播放前检测到widget已dispose，停止初始化');
        return;
      }

      if (!_isDisposed && mounted) {
        print('视频播放器初始化成功');
        setState(() {
          _isInitialized = true;
        });

        // 等待一小段时间再播放，确保编解码器完全准备好
        await Future.delayed(const Duration(milliseconds: 200));

        // 再次检查是否已dispose
        if (!_isDisposed && !_playerDisposed && mounted && !hasError && _player != null) {
          print('开始播放视频');
          try {
            _player!.play();
          } catch (e) {
            // 如果play失败（Player被dispose），忽略错误
            print('播放失败（已忽略）: $e');
            if (e.toString().contains('disposed') || e.toString().contains('Disposed')) {
              _playerDisposed = true;
              return; // Player已被dispose，直接返回
            }
            // 其他错误，设置hasError状态
            if (!_isDisposed && mounted) {
              setState(() => _hasError = true);
            }
          }
        } else {
          print('延迟后检测到widget已dispose或有错误，取消播放');
        }
      }
    } catch (e, stackTrace) {
      print('视频初始化失败: $e');
      print('堆栈: $stackTrace');
      // 如果是因为disposed导致的错误，忽略它
      if (e.toString().contains('disposed') || e.toString().contains('Disposed')) {
        print('捕获到dispose相关错误，忽略');
        return;
      }
      if (!_isDisposed && mounted) {
        setState(() => _hasError = true);
      }
    }
  }

  @override
  void dispose() {
    _isDisposed = true; // 设置标志，防止异步操作继续执行
    _hideControlsTimer?.cancel();

    // 先清空VideoController引用
    _videoController = null;

    // 安全地dispose Player，避免重复dispose错误
    if (_player != null && !_playerDisposed) {
      _playerDisposed = true; // 设置标志，防止重复dispose
      try {
        _player!.dispose();
      } catch (e) {
        // 忽略dispose相关错误（Player可能已经被dispose）
        print('Player dispose 错误（已忽略）: $e');
      }
      _player = null;
    }

    super.dispose();
  }

  // 开始自动隐藏控件的计时器（3秒后隐藏）
  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _isPlaying) {
        setState(() => _showControls = false);
      }
    });
  }

  // 切换控件显示/隐藏
  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls) {
      _startHideControlsTimer(); // 显示控件后，开始倒计时自动隐藏
    }
  }

  void _togglePlayPause() {
    if (_isDisposed || _player == null || _playerDisposed) return; // 防止在dispose后或未初始化时调用
    try {
      if (_isPlaying) {
        _player!.pause();
      } else {
        _player!.play();
      }
      // 切换播放状态时，显示控件并重新开始倒计时
      if (mounted) {
        setState(() => _showControls = true);
        _startHideControlsTimer();
      }
    } catch (e) {
      print('切换播放状态失败（已忽略）: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // 如果已dispose，返回空容器
    if (_isDisposed) {
      return Container(
        color: NeumorphicTheme.baseColor(context),
      );
    }

    if (_hasError) {
      return Container(
        color: NeumorphicTheme.baseColor(context),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Colors.grey[600],
                ),
                const SizedBox(height: 16),
                Text(
                  '视频加载失败',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[800],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '可能是视频编码格式不支持',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 24),
                NeumorphicButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: NeumorphicStyle(
                    depth: 4,
                    intensity: 0.6,
                    boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(8)),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  child: Text(
                    '返回',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[800],
                    ),
                  ),
                ),
              ],
            ),
          ),
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

    // 确保VideoController已初始化
    if (_videoController == null) {
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
            controller: _videoController!,
            controls: NoVideoControls,
          ),
        ),

        // 点击区域用于显示/隐藏控件
        Positioned.fill(
          child: GestureDetector(
            onTap: _toggleControls,
            behavior: HitTestBehavior.translucent,
          ),
        ),

        // 底部控制栏（根据 _showControls 状态显示/隐藏）
        if (_showControls)
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
              if (_isDisposed || _player == null || _playerDisposed) return; // 防止在dispose后或未初始化时调用
              try {
                final seekDuration = _duration * value;
                _player!.seek(seekDuration);
                // 拖动进度条时，重置自动隐藏计时器
                _startHideControlsTimer();
              } catch (e) {
                print('Seek失败（已忽略）: $e');
              }
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
                if (_isDisposed || _player == null || _playerDisposed) return; // 防止在dispose后或未初始化时调用
                try {
                  if (_volume > 0) {
                    _player!.setVolume(0);
                  } else {
                    _player!.setVolume(100);
                  }
                  // 点击音量按钮时，重置自动隐藏计时器
                  _startHideControlsTimer();
                } catch (e) {
                  print('设置音量失败（已忽略）: $e');
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
