import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart';
import 'package:provider/provider.dart';
import '../../models/gallery_file.dart';
import '../../models/gallery_folder.dart';
import '../../providers/auth_provider.dart';
import '../../providers/gallery_provider.dart';
import '../../widgets/common/neumorphic_overlay_appbar.dart';
import '../../widgets/common/neumorphic_dialog.dart';
import '../../widgets/common/neumorphic_toast.dart';
import '../../widgets/video/video_player_widget.dart';

/// 图片/视频详情预览页面
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
  late int _currentIndex;
  bool _showControls = true; // 控制顶部和底部控件的显示

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
  }

  void _goToPrevious() {
    if (_currentIndex > 0) {
      setState(() => _currentIndex--);
    }
  }

  void _goToNext() {
    if (_currentIndex < widget.files.length - 1) {
      setState(() => _currentIndex++);
    }
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
  }

  @override
  Widget build(BuildContext context) {
    final file = widget.files[_currentIndex];

    return Scaffold(
      backgroundColor: NeumorphicTheme.baseColor(context),
      body: Stack(
        children: [
          // 主内容区域 - 使用 AnimatedSwitcher 提供过渡动画
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _buildMediaViewer(file),
          ),

          // 底部控制栏（仅图片/GIF显示，根据状态显示/隐藏）
          if (!file.isVideo && _showControls)
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: _buildNavigationControls(),
            ),

          // 顶部 AppBar（根据状态显示/隐藏）
          NeumorphicOverlayAppBar(
            title: file.name,
            showTitle: _showControls,
            leading: NeumorphicCircleButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: Icons.arrow_back,
            ),
            trailing: NeumorphicCircleButton(
              onPressed: () => _showFileInfoBubble(context, file),
              icon: Icons.info_outline,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // 上一张按钮
        NeumorphicButton(
          onPressed: _currentIndex > 0 ? _goToPrevious : null,
          style: const NeumorphicStyle(
            boxShape: NeumorphicBoxShape.circle(),
            depth: 4,
          ),
          padding: const EdgeInsets.all(16),
          child: Icon(
            Icons.chevron_left,
            size: 32,
            color: _currentIndex > 0
                ? (NeumorphicTheme.isUsingDark(context) ? Colors.white : Colors.black87)
                : Colors.grey,
          ),
        ),

        // 下一张按钮
        NeumorphicButton(
          onPressed: _currentIndex < widget.files.length - 1 ? _goToNext : null,
          style: const NeumorphicStyle(
            boxShape: NeumorphicBoxShape.circle(),
            depth: 4,
          ),
          padding: const EdgeInsets.all(16),
          child: Icon(
            Icons.chevron_right,
            size: 32,
            color: _currentIndex < widget.files.length - 1
                ? (NeumorphicTheme.isUsingDark(context) ? Colors.white : Colors.black87)
                : Colors.grey,
          ),
        ),
      ],
    );
  }

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
              const SizedBox(height: 24),
              // 操作按钮
              Row(
                children: [
                  Expanded(
                    child: NeumorphicButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _showRenameDialog(context, file);
                      },
                      style: NeumorphicStyle(
                        depth: 4,
                        intensity: 0.7,
                        boxShape: NeumorphicBoxShape.roundRect(
                          BorderRadius.circular(12),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.edit, size: 18, color: Color(0xFF171717)),
                          SizedBox(width: 6),
                          Text(
                            '重命名',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF171717),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: NeumorphicButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _showMoveDialog(context, file);
                      },
                      style: NeumorphicStyle(
                        depth: 4,
                        intensity: 0.7,
                        boxShape: NeumorphicBoxShape.roundRect(
                          BorderRadius.circular(12),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.drive_file_move, size: 18, color: Color(0xFF171717)),
                          SizedBox(width: 6),
                          Text(
                            '移动',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF171717),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
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
      return Center(
        key: ValueKey('error_${file.path}'),
        child: Text(
          '无法加载文件',
          style: TextStyle(color: Colors.grey[600]),
        ),
      );
    }

    // 图片或GIF
    if (file.isImage || file.isGif) {
      return GestureDetector(
        key: ValueKey('image_${file.path}'),
        onTap: _toggleControls,
        child: InteractiveViewer(
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
                      Icon(Icons.broken_image, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text('图片加载失败', style: TextStyle(color: Colors.grey[600])),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      );
    }

    // 视频 - 使用新的视频播放器组件
    if (file.isVideo) {
      return VideoPlayerWidget(
        key: ValueKey('video_${file.path}'),
        videoUrl: fileUrl,
        apiKey: authProvider.currentServer?.apiKey ?? '',
        autoPlay: true,
        showControls: true,
        onPrevious: _currentIndex > 0 ? _goToPrevious : null,
        onNext: _currentIndex < widget.files.length - 1 ? _goToNext : null,
        externalControlsVisible: _showControls, // 将外部状态传递给视频播放器
        onControlsVisibilityChanged: (visible) {
          // 当视频播放器内部控件状态改变时,同步更新外部状态
          setState(() => _showControls = visible);
        },
      );
    }

    // 其他文件类型
    return Center(
      key: ValueKey('other_${file.path}'),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.insert_drive_file,
            size: 64,
            color: NeumorphicTheme.isUsingDark(context)
                ? Colors.white.withOpacity(0.54)
                : Colors.black.withOpacity(0.54),
          ),
          const SizedBox(height: 16),
          Text(
            file.name,
            style: TextStyle(
              color: NeumorphicTheme.isUsingDark(context) ? Colors.white : Colors.black87,
              fontSize: 16,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            file.extension.toUpperCase(),
            style: TextStyle(
              color: NeumorphicTheme.isUsingDark(context)
                  ? Colors.white.withOpacity(0.54)
                  : Colors.black.withOpacity(0.54),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  // ========== 重命名对话框 ==========
  void _showRenameDialog(BuildContext context, GalleryFile file) async {
    // 在显示对话框前获取 provider 引用
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final galleryProvider = Provider.of<GalleryProvider>(context, listen: false);

    final textController = TextEditingController();

    // 设置当前文件名(不含扩展名)
    final fileName = file.name;
    final lastDotIndex = fileName.lastIndexOf('.');
    final nameWithoutExt = lastDotIndex > 0 ? fileName.substring(0, lastDotIndex) : fileName;
    textController.text = nameWithoutExt;

    final result = await NeumorphicDialog.showInput(
      context: context,
      title: '重命名文件',
      hint: '输入新文件名',
      controller: textController,
      confirmText: '确认',
      cancelText: '取消',
    );

    if (result != null && result.isNotEmpty) {
      _performRename(authProvider, galleryProvider, file, result + file.extension);
    }
  }

  void _performRename(
    AuthProvider authProvider,
    GalleryProvider galleryProvider,
    GalleryFile file,
    String newName,
  ) async {
    if (authProvider.apiService == null) {
      if (mounted) {
        NeumorphicToast.showError(context, '未连接服务器');
      }
      return;
    }

    try {
      await authProvider.apiService!.renameFile(file.path, newName);

      if (mounted) {
        NeumorphicToast.showSuccess(context, '重命名成功');
      }

      // 刷新文件列表
      await galleryProvider.refresh(authProvider.apiService!);

      // 切换到下一个文件(如果有的话),否则返回
      if (mounted) {
        if (_currentIndex < widget.files.length - 1) {
          // 有下一个文件,切换过去
          setState(() {
            _currentIndex++;
          });
        } else if (_currentIndex > 0) {
          // 没有下一个但有上一个,切换到上一个
          setState(() {
            _currentIndex--;
          });
        } else {
          // 只有一个文件,返回画廊
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      if (mounted) {
        NeumorphicToast.showError(context, '重命名失败');
      }
      print('Rename error: $e');
    }
  }

  // ========== 移动对话框 ==========
  void _showMoveDialog(BuildContext context, GalleryFile file) async {
    // 在显示对话框前获取 provider 引用
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final galleryProvider = Provider.of<GalleryProvider>(context, listen: false);

    // 获取所有文件夹(排除当前文件夹)
    final currentFolderPath = galleryProvider.currentFolder?.path;
    final folders = galleryProvider.folders
        .where((folder) => folder.path != currentFolderPath)
        .toList();

    if (folders.isEmpty) {
      NeumorphicToast.showError(context, '没有可移动的目标文件夹');
      return;
    }

    // 显示文件夹选择对话框
    final selectedFolder = await showDialog<GalleryFolder>(
      context: context,
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
            children: [
              Text(
                '移动到',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF171717),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                constraints: BoxConstraints(maxHeight: 300),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: folders.length,
                  itemBuilder: (context, index) {
                    final folder = folders[index];
                    final displayName = folder.isSource ? '源文件夹' : folder.name;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: NeumorphicButton(
                        onPressed: () => Navigator.pop(context, folder),
                        style: NeumorphicStyle(
                          depth: 4,
                          intensity: 0.7,
                          boxShape: NeumorphicBoxShape.roundRect(
                            BorderRadius.circular(12),
                          ),
                        ),
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(
                              folder.isSource ? Icons.source : Icons.folder,
                              size: 24,
                              color: Color(0xFF525252),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                displayName,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF171717),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              NeumorphicButton(
                onPressed: () => Navigator.pop(context),
                style: NeumorphicStyle(
                  depth: 4,
                  intensity: 0.7,
                  boxShape: NeumorphicBoxShape.roundRect(
                    BorderRadius.circular(12),
                  ),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
                child: Text(
                  '取消',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF525252),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (selectedFolder != null) {
      _performMove(authProvider, galleryProvider, file, selectedFolder);
    }
  }

  void _performMove(
    AuthProvider authProvider,
    GalleryProvider galleryProvider,
    GalleryFile file,
    GalleryFolder targetFolder,
  ) async {
    if (authProvider.apiService == null) {
      if (mounted) {
        NeumorphicToast.showError(context, '未连接服务器');
      }
      return;
    }

    try {
      await authProvider.apiService!.moveFile(file.path, targetFolder.path);
      final displayName = targetFolder.isSource ? '源文件夹' : targetFolder.name;

      if (mounted) {
        NeumorphicToast.showSuccess(context, '已移动到 $displayName');
      }

      // 刷新文件列表
      await galleryProvider.refresh(authProvider.apiService!);

      // 切换到下一个文件(如果有的话),否则返回
      if (mounted) {
        if (_currentIndex < widget.files.length - 1) {
          // 有下一个文件,切换过去
          setState(() {
            _currentIndex++;
          });
        } else if (_currentIndex > 0) {
          // 没有下一个但有上一个,切换到上一个
          setState(() {
            _currentIndex--;
          });
        } else {
          // 只有一个文件,返回画廊
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      if (mounted) {
        NeumorphicToast.showError(context, '移动失败');
      }
      print('Move error: $e');
    }
  }
}
