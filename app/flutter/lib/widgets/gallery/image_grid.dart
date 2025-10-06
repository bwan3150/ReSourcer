import 'dart:io';
import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../../models/gallery_file.dart';
import '../../providers/auth_provider.dart';
import '../../providers/upload_provider.dart';
import '../../providers/gallery_provider.dart';
import '../../utils/constants.dart';

import '../../screens/gallery/image_detail_screen.dart';

/// 图片网格组件
class ImageGrid extends StatelessWidget {
  final List<GalleryFile> files;
  final int fileCount;
  final String? currentFolderPath;

  const ImageGrid({
    Key? key,
    required this.files,
    required this.fileCount,
    this.currentFolderPath,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(12),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.0,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                // 最后一个item是上传卡片
                if (index == files.length) {
                  return UploadCard(targetFolder: currentFolderPath);
                }
                return ImageGridItem(
                  file: files[index],
                  allFiles: files,
                  currentIndex: index,
                );
              },
              childCount: files.length + 1, // +1 for upload card
            ),
          ),
        ),
        // 底部文件计数
        SliverToBoxAdapter(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Text(
                '$fileCount ${fileCount == 1 ? 'file' : 'files'}',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[600],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 图片网格项
class ImageGridItem extends StatelessWidget {
  final GalleryFile file;
  final List<GalleryFile> allFiles;
  final int currentIndex;

  const ImageGridItem({
    Key? key,
    required this.file,
    required this.allFiles,
    required this.currentIndex,
  }) : super(key: key);

  void _handleTap(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ImageDetailScreen(
          files: allFiles,
          initialIndex: currentIndex,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final thumbnailUrl = authProvider.apiService?.getThumbnailUrl(file.path);

    return GestureDetector(
      onTap: () => _handleTap(context),
      child: Neumorphic(
        style: NeumorphicStyle(
          depth: 4,
          intensity: 0.8,
          boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(12)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 根据文件类型显示内容
              if (file.isImage && thumbnailUrl != null)
                // 普通图片使用缩略图
                Image.network(
                  thumbnailUrl,
                  fit: BoxFit.cover,
                  headers: {
                    'Cookie': 'api_key=${authProvider.apiKey}',
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return _buildPlaceholder(Icons.broken_image);
                  },
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return _buildPlaceholder(Icons.image);
                  },
                )
              else if (file.isGif)
                // GIF直接加载原文件以显示动画
                Image.network(
                  authProvider.apiService!.getImageUrl(file.path),
                  fit: BoxFit.cover,
                  headers: {
                    'Cookie': 'api_key=${authProvider.apiKey}',
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return _buildPlaceholder(Icons.broken_image);
                  },
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return _buildPlaceholder(Icons.gif);
                  },
                )
              else if (file.isVideo && thumbnailUrl != null)
                // 视频显示首帧缩略图
                Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      thumbnailUrl,
                      fit: BoxFit.cover,
                      headers: {
                        'Cookie': 'api_key=${authProvider.apiKey}',
                      },
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          color: Colors.grey[800],
                          child: Icon(
                            Icons.play_circle_outline,
                            size: 64,
                            color: Colors.white.withOpacity(0.8),
                          ),
                        );
                      },
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return _buildPlaceholder(Icons.videocam);
                      },
                    ),
                    // 播放图标叠加层
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.play_arrow,
                          size: 32,
                          color: Colors.white.withOpacity(0.9),
                        ),
                      ),
                    ),
                  ],
                )
              else
                _buildPlaceholder(Icons.insert_drive_file),

              // 右下角的文件类型标签
              Positioned(
                bottom: 6,
                right: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    file.extension.replaceFirst('.', '').toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder(IconData icon) {
    return Container(
      color: Colors.grey[300],
      child: Icon(
        icon,
        size: 40,
        color: Colors.grey[500],
      ),
    );
  }
}


/// 上传卡片组件
class UploadCard extends StatefulWidget {
  final String? targetFolder;

  const UploadCard({Key? key, this.targetFolder}) : super(key: key);

  @override
  State<UploadCard> createState() => _UploadCardState();
}

class _UploadCardState extends State<UploadCard> {
  final ImagePicker _picker = ImagePicker();
  bool _uploading = false;

  // 显示上传方式选择对话框
  Future<void> _showUploadMethodDialog() async {
    if (widget.targetFolder == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择上传方式'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('相机拍摄'),
              onTap: () {
                Navigator.pop(context);
                _uploadFromCamera();
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('从相册选择'),
              onTap: () {
                Navigator.pop(context);
                _uploadFromGallery();
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder),
              title: const Text('从文件选择'),
              onTap: () {
                Navigator.pop(context);
                _uploadFromFiles();
              },
            ),
          ],
        ),
      ),
    );
  }

  // 从相机上传
  Future<void> _uploadFromCamera() async {
    if (_uploading) return;

    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );

      if (photo == null || !mounted) return;

      await _performUpload([photo.path], deleteAfterUpload: false);
    } catch (e) {
      print('相机拍摄出错: $e');
      if (mounted) {
        _showMessage('相机拍摄失败', isError: true);
      }
    }
  }

  // 从相册上传
  Future<void> _uploadFromGallery() async {
    if (_uploading) return;

    try {
      final List<XFile> files = await _picker.pickMultipleMedia(
        imageQuality: 85,
      );

      if (files.isEmpty || !mounted) return;

      // 显示确认对话框，包含删除选项
      bool? result = await showDialog<bool>(
        context: context,
        builder: (context) => _GalleryUploadDialog(fileCount: files.length),
      );

      if (result == null || !mounted) return;

      final filePaths = files.map((f) => f.path).toList();
      await _performUpload(filePaths, deleteAfterUpload: result);
    } catch (e) {
      print('相册选择出错: $e');
      if (mounted) {
        _showMessage('相册选择失败', isError: true);
      }
    }
  }

  // 从文件系统上传
  Future<void> _uploadFromFiles() async {
    if (_uploading) return;

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.media,
      );

      if (result == null || result.files.isEmpty || !mounted) return;

      final filePaths = result.files
          .where((f) => f.path != null)
          .map((f) => f.path!)
          .toList();

      if (filePaths.isEmpty) return;

      await _performUpload(filePaths, deleteAfterUpload: false);
    } catch (e) {
      print('文件选择出错: $e');
      if (mounted) {
        _showMessage('文件选择失败', isError: true);
      }
    }
  }

  // 执行上传
  Future<void> _performUpload(List<String> filePaths, {required bool deleteAfterUpload}) async {
    setState(() => _uploading = true);

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final uploadProvider = Provider.of<UploadProvider>(context, listen: false);
    final galleryProvider = Provider.of<GalleryProvider>(context, listen: false);

    if (authProvider.apiService == null) {
      _showMessage('服务未连接', isError: true);
      setState(() => _uploading = false);
      return;
    }

    try {
      // 上传文件
      final success = await uploadProvider.uploadFiles(
        authProvider.apiService!,
        filePaths,
        widget.targetFolder!,
      );

      if (mounted) {
        if (success) {
          _showMessage('上传任务已创建');

          // 如果需要删除原文件
          if (deleteAfterUpload) {
            await _deleteFiles(filePaths);
          }

          // 刷新文件列表
          await galleryProvider.refresh(authProvider.apiService!);
        } else {
          _showMessage('上传失败', isError: true);
        }
        setState(() => _uploading = false);
      }
    } catch (e) {
      print('上传出错: $e');
      if (mounted) {
        _showMessage('上传出错', isError: true);
        setState(() => _uploading = false);
      }
    }
  }

  // 删除本地文件（会移动到系统回收站/最近删除）
  Future<void> _deleteFiles(List<String> filePaths) async {
    try {
      for (String path in filePaths) {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      }
      if (mounted) {
        _showMessage('已删除 ${filePaths.length} 个本地文件');
      }
    } catch (e) {
      print('删除文件出错: $e');
      if (mounted) {
        _showMessage('删除文件失败', isError: true);
      }
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _uploading ? null : _showUploadMethodDialog,
      child: Neumorphic(
        style: NeumorphicStyle(
          depth: _uploading ? -2 : 4,
          intensity: 0.8,
          boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(12)),
          color: Colors.grey[200],
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: _uploading
                ? const CircularProgressIndicator()
                : const Icon(
                    Icons.add,
                    size: 48,
                    color: Colors.grey,
                  ),
          ),
        ),
      ),
    );
  }
}

// 相册上传确认对话框
class _GalleryUploadDialog extends StatefulWidget {
  final int fileCount;

  const _GalleryUploadDialog({required this.fileCount});

  @override
  State<_GalleryUploadDialog> createState() => _GalleryUploadDialogState();
}

class _GalleryUploadDialogState extends State<_GalleryUploadDialog> {
  bool _deleteAfterUpload = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('上传确认'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('已选择 ${widget.fileCount} 个文件'),
          const SizedBox(height: 16),
          CheckboxListTile(
            value: _deleteAfterUpload,
            onChanged: (value) {
              setState(() => _deleteAfterUpload = value ?? false);
            },
            title: const Text('上传后删除原图'),
            subtitle: const Text('文件将移至回收站'),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _deleteAfterUpload),
          child: const Text('上传'),
        ),
      ],
    );
  }
}
