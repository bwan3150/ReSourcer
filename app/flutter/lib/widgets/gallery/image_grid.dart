import 'dart:io';
import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';
import '../../models/gallery_file.dart';
import '../../providers/auth_provider.dart';
import '../../providers/upload_provider.dart';
import '../../providers/gallery_provider.dart';
import '../../utils/theme_colors.dart';
import '../../screens/gallery/image_detail_screen.dart';
import '../common/neumorphic_option_sheet.dart';
import '../common/neumorphic_toast.dart';

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
                    'Cookie': 'api_key=${authProvider.currentServer?.apiKey ?? ''}',
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
                    'Cookie': 'api_key=${authProvider.currentServer?.apiKey ?? ''}',
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
                        'Cookie': 'api_key=${authProvider.currentServer?.apiKey ?? ''}',
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

    NeumorphicOptionSheet.show(
      context: context,
      title: '选择上传方式',
      options: [
        SheetOption(
          icon: Icons.camera_alt,
          text: '相机拍摄',
          onTap: () => _uploadFromCamera(),
        ),
        SheetOption(
          icon: Icons.photo_library,
          text: '从相册选择',
          onTap: () => _uploadFromGallery(),
        ),
        SheetOption(
          icon: Icons.folder,
          text: '从文件选择',
          onTap: () => _uploadFromFiles(),
        ),
      ],
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
        _showMessage('拍摄失败', isError: true);
      }
    }
  }

  // 从相册上传（使用 wechat_assets_picker 以支持准确删除）
  Future<void> _uploadFromGallery() async {
    if (_uploading) return;

    try {
      // 使用 wechat_assets_picker 选择照片/视频，返回 AssetEntity 列表
      final List<AssetEntity>? assets = await AssetPicker.pickAssets(
        context,
        pickerConfig: AssetPickerConfig(
          maxAssets: 100,
          requestType: RequestType.common, // 支持图片和视频
          textDelegate: const AssetPickerTextDelegate(),
        ),
      );

      if (assets == null || assets.isEmpty || !mounted) return;

      // 显示确认对话框，包含删除选项
      bool? result = await showDialog<bool>(
        context: context,
        builder: (context) => _GalleryUploadDialog(fileCount: assets.length),
      );

      if (result == null || !mounted) return;

      // 将 AssetEntity 转换为文件路径
      final List<String> filePaths = [];
      for (var asset in assets) {
        final file = await asset.file;
        if (file != null) {
          filePaths.add(file.path);
        }
      }

      if (filePaths.isEmpty) {
        _showMessage('获取失败', isError: true);
        return;
      }

      // 传递 assets 用于删除
      await _performUpload(
        filePaths,
        deleteAfterUpload: result,
        assetEntities: result ? assets : null,
      );
    } catch (e) {
      print('相册选择出错: $e');
      if (mounted) {
        _showMessage('选择失败', isError: true);
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
        _showMessage('选择失败', isError: true);
      }
    }
  }

  // 执行上传
  Future<void> _performUpload(
    List<String> filePaths, {
    required bool deleteAfterUpload,
    List<AssetEntity>? assetEntities, // 可选的 AssetEntity 列表，用于准确删除
  }) async {
    setState(() => _uploading = true);

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final uploadProvider = Provider.of<UploadProvider>(context, listen: false);
    final galleryProvider = Provider.of<GalleryProvider>(context, listen: false);

    if (authProvider.apiService == null) {
      _showMessage('未连接', isError: true);
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
          _showMessage('已创建');

          // 如果需要删除原文件
          if (deleteAfterUpload) {
            if (assetEntities != null && assetEntities.isNotEmpty) {
              // 使用 AssetEntity 直接删除（准确且快速）
              await _deleteAssets(assetEntities);
            } else {
              // 没有 AssetEntity，无法删除
              _showMessage('不支持删除', isError: true);
            }
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

  // 使用 AssetEntity 直接删除照片（准确且快速）
  Future<void> _deleteAssets(List<AssetEntity> assets) async {
    try {
      // 提取所有 asset ID
      final List<String> assetIds = assets.map((asset) => asset.id).toList();

      print('准备删除 ${assetIds.length} 个资源');

      // 使用 PhotoManager 批量删除
      final List<String> deletedIds = await PhotoManager.editor.deleteWithIds(assetIds);

      if (mounted) {
        if (deletedIds.isNotEmpty) {
          _showMessage('已删除 ${deletedIds.length} 个');
          print('成功删除 ${deletedIds.length} 个资源');
        } else {
          _showMessage('删除失败', isError: true);
          print('删除失败：没有资源被删除');
        }
      }
    } catch (e) {
      print('删除资源出错: $e');
      if (mounted) {
        _showMessage('删除失败', isError: true);
      }
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;

    if (isError) {
      NeumorphicToast.showError(context, message);
    } else {
      NeumorphicToast.showSuccess(context, message);
    }
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
                ? CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(ThemeColors.text(context)),
                    backgroundColor: const Color(0xFFE0E0E0),
                  )
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
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: NeumorphicBackground(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题
              Center(
                child: Text(
                  '上传确认',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: ThemeColors.text(context),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // 文件数量
              Center(
                child: Text(
                  '已选择 ${widget.fileCount} 个文件',
                  style: TextStyle(
                    fontSize: 14,
                    color: ThemeColors.textSecondary(context),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // 删除选项
              Center(
                child: GestureDetector(
                  onTap: () {
                    setState(() => _deleteAfterUpload = !_deleteAfterUpload);
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                    // 自定义 Checkbox
                    Neumorphic(
                      style: NeumorphicStyle(
                        depth: _deleteAfterUpload ? -2 : 2,
                        intensity: 0.6,
                        boxShape: NeumorphicBoxShape.roundRect(
                          BorderRadius.circular(6),
                        ),
                      ),
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: _deleteAfterUpload
                            ? Icon(
                                Icons.check,
                                size: 18,
                                color: ThemeColors.text(context),
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '上传后删除原图',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: ThemeColors.text(context),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '文件将移至回收站',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                ),
              ),
              const SizedBox(height: 24),
              // 按钮组
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 取消按钮
                  NeumorphicButton(
                    onPressed: () => Navigator.pop(context),
                    style: NeumorphicStyle(
                      depth: 4,
                      intensity: 0.7,
                      boxShape: NeumorphicBoxShape.roundRect(
                        BorderRadius.circular(12),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    child: Text(
                      '取消',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: ThemeColors.textSecondary(context),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // 上传按钮
                  NeumorphicButton(
                    onPressed: () => Navigator.pop(context, _deleteAfterUpload),
                    style: NeumorphicStyle(
                      depth: 4,
                      intensity: 0.7,
                      boxShape: NeumorphicBoxShape.roundRect(
                        BorderRadius.circular(12),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    child: Text(
                      '上传',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: ThemeColors.text(context),
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
}
