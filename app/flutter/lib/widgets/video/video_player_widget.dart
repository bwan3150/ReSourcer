import 'dart:async';
import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// 统一的视频播放器组件
/// 使用 media_kit 提供视频播放功能
class VideoPlayerWidget extends StatefulWidget {
  final String videoUrl;
  final String apiKey;
  final bool autoPlay;
  final bool showControls;
  final VoidCallback? onPrevious; // 上一个回调（用于多文件浏览）
  final VoidCallback? onNext; // 下一个回调（用于多文件浏览）
  final bool simpleMode; // 简化模式：只显示中间的播放/暂停按钮
  final VoidCallback? onToggleControls; // 切换控件显示/隐藏的回调

  const VideoPlayerWidget({
    Key? key,
    required this.videoUrl,
    required this.apiKey,
    this.autoPlay = true,
    this.showControls = true,
    this.onPrevious,
    this.onNext,
    this.simpleMode = false,
    this.onToggleControls,
  }) : super(key: key);

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  late Player _player;
  late VideoController _videoController;

  bool _isInitialized = false;
  bool _hasError = false;
  bool _isPlaying = false;
  bool _showControls = true;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _volume = 1.0;

  Timer? _hideControlsTimer;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
    if (widget.showControls || widget.simpleMode) {
      _startHideControlsTimer();
    }
  }

  Future<void> _initializePlayer() async {
    try {
      // 创建播放器
      _player = Player();
      _videoController = VideoController(_player);

      // 监听播放状态
      _player.stream.playing.listen((playing) {
        if (mounted) {
          setState(() => _isPlaying = playing);
          if (playing && _showControls) {
            _startHideControlsTimer();
          } else if (!playing) {
            // 暂停时显示控件（简化模式和标准模式都适用）
            _hideControlsTimer?.cancel();
            setState(() => _showControls = true);
          }
        }
      });

      // 监听播放位置
      _player.stream.position.listen((position) {
        if (mounted) setState(() => _position = position);
      });

      // 监听视频时长
      _player.stream.duration.listen((duration) {
        if (mounted) setState(() => _duration = duration);
      });

      // 监听音量
      _player.stream.volume.listen((volume) {
        if (mounted) setState(() => _volume = volume);
      });

      // 监听错误
      _player.stream.error.listen((error) {
        print('视频播放错误: $error');
        if (mounted) setState(() => _hasError = true);
      });

      // 构建带 API key 的 URL
      final uri = Uri.parse(widget.videoUrl);
      final videoUrlWithKey = uri.replace(
        queryParameters: {
          ...uri.queryParameters,
          'key': widget.apiKey,
        },
      ).toString();

      // 打开视频
      await _player.open(Media(videoUrlWithKey), play: widget.autoPlay);

      if (mounted) {
        setState(() => _isInitialized = true);
      }
    } catch (e) {
      print('视频初始化失败: $e');
      if (mounted) {
        setState(() => _hasError = true);
      }
    }
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _player.dispose();
    super.dispose();
  }

  void _startHideControlsTimer() {
    if (!widget.showControls && !widget.simpleMode) return;

    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _isPlaying) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    if (!widget.showControls) return;

    setState(() => _showControls = !_showControls);
    if (_showControls) {
      _startHideControlsTimer();
    }
    // 通知父组件切换控件状态
    widget.onToggleControls?.call();
  }

  void _togglePlayPause() {
    if (_isPlaying) {
      _player.pause();
    } else {
      _player.play();
    }
    setState(() => _showControls = true);
    _startHideControlsTimer();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return _buildErrorView();
    }

    if (!_isInitialized) {
      return _buildLoadingView();
    }

    // 简化模式：只显示中间的播放/暂停按钮
    if (widget.simpleMode) {
      return Stack(
        children: [
          // 视频播放器 - 支持双指缩放
          InteractiveViewer(
            minScale: 0.5,
            maxScale: 4.0,
            child: Center(
              child: Video(
                controller: _videoController,
                controls: NoVideoControls,
              ),
            ),
          ),

          // 点击区域用于显示/隐藏控件
          Positioned.fill(
            child: GestureDetector(
              onTap: () {
                setState(() => _showControls = !_showControls);
                if (_showControls) {
                  _startHideControlsTimer();
                }
                // 通知父组件切换控件状态
                widget.onToggleControls?.call();
              },
              behavior: HitTestBehavior.translucent,
            ),
          ),

          // 中间的播放/暂停按钮（根据状态显示/隐藏，位置固定不受缩放影响）
          if (_showControls)
            Center(
              child: NeumorphicButton(
                onPressed: _togglePlayPause,
                style: const NeumorphicStyle(
                  boxShape: NeumorphicBoxShape.circle(),
                  depth: 4,
                  intensity: 0.8,
                ),
                padding: const EdgeInsets.all(20),
                child: Icon(
                  _isPlaying ? Icons.pause : Icons.play_arrow,
                  size: 40,
                  color: NeumorphicTheme.isUsingDark(context) ? Colors.white : Colors.black87,
                ),
              ),
            ),
        ],
      );
    }

    // 标准模式：底部控制栏
    return Stack(
      children: [
        // 视频播放器 - 支持双指缩放
        InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: Center(
            child: Video(
              controller: _videoController,
              controls: NoVideoControls,
            ),
          ),
        ),

        // 点击区域用于显示/隐藏控件
        if (widget.showControls)
          Positioned.fill(
            child: GestureDetector(
              onTap: _toggleControls,
              behavior: HitTestBehavior.translucent,
            ),
          ),

        // 底部控制栏（位置固定不受缩放影响）
        if (widget.showControls && _showControls)
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: _buildDefaultControls(),
          ),
      ],
    );
  }

  Widget _buildErrorView() {
    return Container(
      color: NeumorphicTheme.baseColor(context),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.grey[600]),
            const SizedBox(height: 16),
            Text(
              '视频加载失败',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey[800],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingView() {
    return Container(
      color: NeumorphicTheme.baseColor(context),
      child: const Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
    );
  }

  Widget _buildDefaultControls() {
    final progress = _duration.inMilliseconds > 0
        ? _position.inMilliseconds / _duration.inMilliseconds
        : 0.0;

    final hasNavigation = widget.onPrevious != null || widget.onNext != null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 静音图标（进度条上方右侧）
        Padding(
          padding: const EdgeInsets.only(right: 12, bottom: 8),
          child: Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: () {
                _player.setVolume(_volume > 0 ? 0 : 100);
                _startHideControlsTimer();
              },
              child: Icon(
                _volume > 0 ? Icons.volume_up : Icons.volume_off,
                size: 24,
                color: NeumorphicTheme.isUsingDark(context)
                    ? Colors.white.withOpacity(0.9)
                    : Colors.black87,
              ),
            ),
          ),
        ),
        // 进度条
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: NeumorphicSlider(
            value: progress.clamp(0.0, 1.0),
            onChanged: (value) {
              final seekDuration = _duration * value;
              _player.seek(seekDuration);
              _startHideControlsTimer();
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
        // 控制按钮（左：上一个，中：播放/暂停，右：下一个）
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // 左侧：上一个按钮
            if (hasNavigation)
              NeumorphicButton(
                onPressed: widget.onPrevious,
                style: const NeumorphicStyle(
                  boxShape: NeumorphicBoxShape.circle(),
                  depth: 4,
                ),
                padding: const EdgeInsets.all(16),
                child: Icon(
                  Icons.chevron_left,
                  size: 32,
                  color: widget.onPrevious != null
                      ? (NeumorphicTheme.isUsingDark(context) ? Colors.white : Colors.black87)
                      : Colors.grey,
                ),
              )
            else
              const SizedBox(width: 56), // 占位保持居中

            // 中间：播放/暂停按钮
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
                color: NeumorphicTheme.isUsingDark(context) ? Colors.white : Colors.black87,
              ),
            ),

            // 右侧：下一个按钮
            if (hasNavigation)
              NeumorphicButton(
                onPressed: widget.onNext,
                style: const NeumorphicStyle(
                  boxShape: NeumorphicBoxShape.circle(),
                  depth: 4,
                ),
                padding: const EdgeInsets.all(16),
                child: Icon(
                  Icons.chevron_right,
                  size: 32,
                  color: widget.onNext != null
                      ? (NeumorphicTheme.isUsingDark(context) ? Colors.white : Colors.black87)
                      : Colors.grey,
                ),
              )
            else
              const SizedBox(width: 56), // 占位保持居中
          ],
        ),
      ],
    );
  }
}
