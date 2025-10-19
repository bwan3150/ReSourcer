import 'dart:io';
import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../providers/auth_provider.dart';
import '../../providers/upload_provider.dart';
import '../../providers/gallery_provider.dart';
import '../../utils/theme_colors.dart';
import '../common/neumorphic_option_sheet.dart';
import '../common/neumorphic_toast.dart';
import '../common/neumorphic_dialog.dart';

/// 上传辅助类 - 处理文件上传的通用逻辑
class UploadHelper {
  final BuildContext context;
  final String? targetFolder;
  final Function(bool uploading) onUploadingChanged;

  UploadHelper({
    required this.context,
    required this.targetFolder,
    required this.onUploadingChanged,
  });

  final ImagePicker _picker = ImagePicker();

  /// 显示上传方式选择对话框
  Future<void> showUploadMethodDialog() async {
    if (targetFolder == null) {
      _showMessage('请先选择目标文件夹', isError: true);
      return;
    }

    NeumorphicOptionSheet.show(
      context: context,
      title: '选择上传方式',
      options: [
        SheetOption(
          icon: Icons.camera_alt,
          text: '相机拍摄',
          onTap: () => uploadFromCamera(),
        ),
        SheetOption(
          icon: Icons.photo_library,
          text: '从相册选择',
          onTap: () => uploadFromGallery(),
        ),
        SheetOption(
          icon: Icons.folder,
          text: '从文件选择',
          onTap: () => uploadFromFiles(),
        ),
      ],
    );
  }

  /// 从相机上传
  Future<void> uploadFromCamera() async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );

      if (photo == null) return;

      await _performUpload([photo.path], deleteAfterUpload: false);
    } catch (e) {
      print('相机拍摄出错: $e');
      _showMessage('拍摄失败', isError: true);
    }
  }

  /// 从相册上传（使用 wechat_assets_picker 以支持准确删除）
  Future<void> uploadFromGallery() async {
    try {
      // 循环请求权限,直到用户授权或取消
      while (true) {
        final PermissionState ps = await PhotoManager.requestPermissionExtend();

        // 权限已授权,继续
        if (ps.isAuth) break;

        // 权限被拒绝,显示对话框
        final bool? shouldRetry = await NeumorphicDialog.showConfirm(
          context: context,
          title: '需要相册权限',
          content: '需要访问相册以选择照片和视频',
          cancelText: '取消',
          confirmText: '开启',
        );

        // 用户取消,退出
        if (shouldRetry != true) return;

        // 用户点了"开启",继续循环请求
      }

      // 使用 wechat_assets_picker 选择照片/视频，返回 AssetEntity 列表
      final List<AssetEntity>? assets = await AssetPicker.pickAssets(
        context,
        pickerConfig: AssetPickerConfig(
          maxAssets: 100,
          requestType: RequestType.common, // 支持图片和视频
          textDelegate: const AssetPickerTextDelegate(),
        ),
      );

      if (assets == null || assets.isEmpty) return;

      // 显示确认对话框，包含删除选项
      bool? result = await showDialog<bool>(
        context: context,
        builder: (context) => _GalleryUploadDialog(fileCount: assets.length),
      );

      if (result == null) return;

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
      _showMessage('选择失败', isError: true);
    }
  }

  /// 从文件系统上传
  Future<void> uploadFromFiles() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.any,
      );

      if (result == null || result.files.isEmpty) return;

      final filePaths = result.files
          .where((f) => f.path != null)
          .map((f) => f.path!)
          .toList();

      if (filePaths.isEmpty) return;

      await _performUpload(filePaths, deleteAfterUpload: false);
    } catch (e) {
      print('文件选择出错: $e');
      _showMessage('选择失败', isError: true);
    }
  }

  /// 执行上传
  Future<void> _performUpload(
    List<String> filePaths, {
    required bool deleteAfterUpload,
    List<AssetEntity>? assetEntities, // 可选的 AssetEntity 列表，用于准确删除
  }) async {
    onUploadingChanged(true);

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final uploadProvider = Provider.of<UploadProvider>(context, listen: false);
    final galleryProvider = Provider.of<GalleryProvider>(context, listen: false);

    if (authProvider.apiService == null) {
      _showMessage('未连接', isError: true);
      onUploadingChanged(false);
      return;
    }

    try {
      // 上传文件
      final success = await uploadProvider.uploadFiles(
        authProvider.apiService!,
        filePaths,
        targetFolder!,
      );

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
      onUploadingChanged(false);
    } catch (e) {
      print('上传出错: $e');
      _showMessage('上传出错', isError: true);
      onUploadingChanged(false);
    }
  }

  /// 使用 AssetEntity 直接删除照片（准确且快速）
  Future<void> _deleteAssets(List<AssetEntity> assets) async {
    try {
      // 提取所有 asset ID
      final List<String> assetIds = assets.map((asset) => asset.id).toList();

      print('准备删除 ${assetIds.length} 个资源');

      // 使用 PhotoManager 批量删除
      final List<String> deletedIds = await PhotoManager.editor.deleteWithIds(assetIds);

      if (deletedIds.isNotEmpty) {
        _showMessage('已删除 ${deletedIds.length} 个');
        print('成功删除 ${deletedIds.length} 个资源');
      } else {
        _showMessage('删除失败', isError: true);
        print('删除失败：没有资源被删除');
      }
    } catch (e) {
      print('删除资源出错: $e');
      _showMessage('删除失败', isError: true);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (isError) {
      NeumorphicToast.showError(context, message);
    } else {
      NeumorphicToast.showSuccess(context, message);
    }
  }
}

/// 相册上传确认对话框
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
