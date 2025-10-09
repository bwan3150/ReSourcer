import 'dart:async';
import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/downloader_provider.dart';
import '../../models/download_task.dart';
import '../../models/gallery_file.dart';
import '../../utils/theme_colors.dart';
import '../../widgets/common/neumorphic_dialog.dart';
import '../../widgets/common/neumorphic_toast.dart';
import '../../widgets/common/neumorphic_option_sheet.dart';
import '../gallery/image_detail_screen.dart';

/// 下载器页面
class DownloaderScreen extends StatefulWidget {
  const DownloaderScreen({Key? key}) : super(key: key);

  @override
  State<DownloaderScreen> createState() => _DownloaderScreenState();
}

class _DownloaderScreenState extends State<DownloaderScreen> {
  final TextEditingController _urlController = TextEditingController();
  final FocusNode _urlFocusNode = FocusNode();

  UrlDetectResult? _detectResult;
  String _selectedDownloader = 'ytdlp';
  Timer? _detectDebounce;

  @override
  void initState() {
    super.initState();
    // 监听URL输入变化
    _urlController.addListener(_onUrlChanged);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _urlFocusNode.dispose();
    _detectDebounce?.cancel();
    super.dispose();
  }

  /// URL输入变化时的处理
  void _onUrlChanged() {
    _detectDebounce?.cancel();
    _detectDebounce = Timer(const Duration(milliseconds: 500), () {
      final url = _urlController.text.trim();
      if (url.isNotEmpty) {
        _detectUrl(url);
      } else {
        setState(() {
          _detectResult = null;
        });
      }
    });
  }

  /// 检测URL
  Future<void> _detectUrl(String url) async {
    final downloaderProvider =
        Provider.of<DownloaderProvider>(context, listen: false);

    final result = await downloaderProvider.detectUrl(url);
    if (mounted) {
      setState(() {
        _detectResult = result;
        if (result != null) {
          _selectedDownloader = result.downloader;
        }
      });
    }
  }

  /// 创建下载任务并导航到任务列表页面
  Future<void> _startDownloadWithContext(BuildContext context) async {
    debugPrint('=== 开始创建下载任务 ===');
    final url = _urlController.text.trim();
    debugPrint('URL: $url');

    if (url.isEmpty) {
      NeumorphicToast.showError(context, '请输入URL');
      return;
    }

    try {
      debugPrint('尝试获取 DownloaderProvider...');
      final downloaderProvider =
          Provider.of<DownloaderProvider>(context, listen: false);
      debugPrint('DownloaderProvider 获取成功');

      debugPrint('调用 createTask: downloader=$_selectedDownloader, folder=${downloaderProvider.selectedFolder}');
      final success = await downloaderProvider.createTask(
        url: url,
        downloader: _selectedDownloader,
        saveFolder: downloaderProvider.selectedFolder,
      );

      debugPrint('createTask 返回结果: $success');

      if (mounted) {
        if (success) {
          NeumorphicToast.showSuccess(context, '任务已创建');
          _urlController.clear();
          setState(() {
            _detectResult = null;
          });
          // 导航到任务列表页面
          debugPrint('导航到任务列表页面');
          _navigateToTaskList();
        } else {
          final error = downloaderProvider.error ?? '创建任务失败';
          debugPrint('创建任务失败: $error');
          NeumorphicToast.showError(context, error);
        }
      }
    } catch (e, stackTrace) {
      debugPrint('=== 创建任务异常 ===');
      debugPrint('异常: $e');
      debugPrint('堆栈: $stackTrace');
      if (mounted) {
        NeumorphicToast.showError(context, '创建任务异常: $e');
      }
    }
  }

  /// 导航到任务列表页面
  void _navigateToTaskList() {
    Navigator.of(context).pushNamed('/downloader/tasks');
  }

  /// 显示添加文件夹对话框
  Future<void> _showAddFolderDialog() async {
    final controller = TextEditingController();

    await NeumorphicDialog.showCustom(
      context: context,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '新建文件夹',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: ThemeColors.text(context),
              ),
            ),
            const SizedBox(height: 20),
            Neumorphic(
              style: NeumorphicStyle(
                depth: -2,
                intensity: 0.6,
                boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(12)),
              ),
              child: TextField(
                controller: controller,
                autofocus: true,
                style: TextStyle(color: ThemeColors.text(context)),
                decoration: InputDecoration(
                  hintText: '文件夹名称',
                  hintStyle: TextStyle(color: ThemeColors.textSecondary(context)),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(16),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                NeumorphicButton(
                  onPressed: () => Navigator.pop(context),
                  style: NeumorphicStyle(
                    depth: 4,
                    boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(10)),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  child: Text(
                    '取消',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: ThemeColors.textSecondary(context),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                NeumorphicButton(
                  onPressed: () async {
                    final name = controller.text.trim();
                    if (name.isNotEmpty) {
                      Navigator.pop(context);
                      final downloaderProvider =
                          Provider.of<DownloaderProvider>(context, listen: false);
                      final success = await downloaderProvider.createFolder(name);
                      if (mounted) {
                        if (success) {
                          NeumorphicToast.showSuccess(context, '文件夹已创建');
                        } else {
                          NeumorphicToast.showError(
                            context,
                            downloaderProvider.error ?? '创建文件夹失败',
                          );
                        }
                      }
                    }
                  },
                  style: NeumorphicStyle(
                    depth: 4,
                    boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(10)),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  child: Text(
                    '创建',
                    style: TextStyle(
                      fontSize: 16,
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
    );
  }

  /// 删除任务
  Future<void> _deleteTask(DownloadTask task) async {
    final downloaderProvider =
        Provider.of<DownloaderProvider>(context, listen: false);

    final success = await downloaderProvider.deleteTask(task.id);
    if (mounted) {
      if (success) {
        NeumorphicToast.showSuccess(context, '任务已删除');
      } else {
        NeumorphicToast.showError(context, '删除任务失败');
      }
    }
  }

  /// 从剪贴板粘贴URL
  Future<void> _pasteFromClipboard() async {
    try {
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      if (clipboardData != null && clipboardData.text != null) {
        final text = clipboardData.text!.trim();
        if (text.isNotEmpty) {
          _urlController.text = text;
          NeumorphicToast.showSuccess(context, '已粘贴');
        } else {
          NeumorphicToast.showInfo(context, '剪贴板为空');
        }
      } else {
        NeumorphicToast.showInfo(context, '剪贴板为空');
      }
    } catch (e) {
      NeumorphicToast.showError(context, '读取剪贴板失败');
    }
  }

  /// 预览文件
  void _previewFile(DownloadTask task) {
    if (task.filePath == null) {
      NeumorphicToast.showError(context, '文件路径不存在');
      return;
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.apiService == null) {
      NeumorphicToast.showError(context, '未连接服务器');
      return;
    }

    final extension = task.filePath!.split('.').last.toLowerCase();

    String fileType;
    if (extension == 'gif') {
      fileType = 'gif';
    } else if (['jpg', 'jpeg', 'png', 'webp', 'bmp'].contains(extension)) {
      fileType = 'image';
    } else if (['mp4', 'webm', 'mov', 'avi', 'mkv', 'm4v'].contains(extension)) {
      fileType = 'video';
    } else {
      fileType = 'unknown';
    }

    final galleryFile = GalleryFile(
      name: task.fileName ?? task.filePath!.split('/').last,
      path: task.filePath!,
      fileType: fileType,
      extension: extension,
      size: 0,
      modifiedTime: task.completedAt?.toIso8601String() ?? '',
    );

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ImageDetailScreen(
          files: [galleryFile],
          initialIndex: 0,
        ),
      ),
    );
  }

  /// 显示任务操作菜单（长按）
  void _showTaskOptions(DownloadTask task) {
    final options = <SheetOption>[];

    // 预览（已完成的任务）
    if (task.isCompleted && task.filePath != null) {
      options.add(
        SheetOption(
          icon: Icons.visibility,
          text: '预览',
          onTap: () => _previewFile(task),
          iconColor: ThemeColors.text(context),
          textColor: ThemeColors.text(context),
        ),
      );
    }

    // 删除
    options.add(
      SheetOption(
        icon: Icons.delete,
        text: '删除',
        onTap: () => _deleteTask(task),
        iconColor: ThemeColors.text(context),
        textColor: ThemeColors.text(context),
      ),
    );

    NeumorphicOptionSheet.show(
      context: context,
      options: options,
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);

    if (authProvider.apiService == null) {
      return Scaffold(
        backgroundColor: NeumorphicTheme.baseColor(context),
        body: Center(
          child: Text(
            '请先连接服务器',
            style: TextStyle(
              fontSize: 16,
              color: ThemeColors.textSecondary(context),
            ),
          ),
        ),
      );
    }

    return ChangeNotifierProvider(
      create: (_) => DownloaderProvider(authProvider.apiService!)..initialize(),
      builder: (context, child) {
        return Scaffold(
          backgroundColor: NeumorphicTheme.baseColor(context),
          body: SafeArea(
            child: Consumer<DownloaderProvider>(
              builder: (context, provider, _) {
                return SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Column(
                    children: [
                      const SizedBox(height: 60),

                      // 标题 "下载器"（黑色文字）
                      Text(
                        '下载器',
                        style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          color: ThemeColors.text(context),
                        ),
                      ),

                      const SizedBox(height: 40),

                      // 主输入区域（无卡片包装）
                      _buildMainInputArea(provider),

                      const SizedBox(height: 24),

                      // "下载列表" 文字入口
                      _buildTaskListLink(),

                      const SizedBox(height: 60),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  /// 构建主输入区域（无卡片包装）
  Widget _buildMainInputArea(DownloaderProvider provider) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 小黑字标题
          Text(
            '输入链接',
            style: TextStyle(
              fontSize: 12,
              color: ThemeColors.text(context).withOpacity(0.6),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),

          // 输入框 + 圆形粘贴按钮
          Row(
            children: [
              Expanded(
                child: Neumorphic(
                  style: NeumorphicStyle(
                    depth: -3,
                    intensity: 0.6,
                    boxShape: NeumorphicBoxShape.roundRect(
                      BorderRadius.circular(30), // 增大圆角让边缘看起来圆
                    ),
                  ),
                  child: TextField(
                    controller: _urlController,
                    focusNode: _urlFocusNode,
                    style: TextStyle(
                      fontSize: 15,
                      color: ThemeColors.text(context),
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // 圆形粘贴按钮
              NeumorphicButton(
                onPressed: _pasteFromClipboard,
                style: const NeumorphicStyle(
                  depth: 5,
                  intensity: 0.7,
                  boxShape: NeumorphicBoxShape.circle(),
                ),
                padding: const EdgeInsets.all(16),
                child: Icon(
                  Icons.content_paste,
                  size: 22,
                  color: ThemeColors.text(context),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // 文件夹选择（极简，参考分类器收起样式）
          _buildFolderSelector(provider),

          const SizedBox(height: 24),

          // 下载按钮（仅图标，大圆角）
          Consumer<DownloaderProvider>(
            builder: (btnContext, provider, _) {
              return NeumorphicButton(
                onPressed: () => _startDownloadWithContext(btnContext),
                style: NeumorphicStyle(
                  depth: 6,
                  intensity: 0.8,
                  boxShape: NeumorphicBoxShape.roundRect(
                    BorderRadius.circular(30), // 大圆角
                  ),
                ),
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Icon(
                    Icons.download,
                    size: 24,
                    color: ThemeColors.text(context),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  /// 构建文件夹选择器（参考分类器收起样式）
  Widget _buildFolderSelector(DownloaderProvider provider) {
    return SizedBox(
      height: 54, // 增加高度以容纳阴影
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none, // 不裁剪阴影
        padding: const EdgeInsets.symmetric(vertical: 4), // 上下留出阴影空间
        child: Row(
          children: [
            // 源文件夹
            _buildFolderChip(
              name: '',
              displayName: '源文件夹',
              isSelected: provider.selectedFolder == '',
              onTap: () => provider.selectFolder(''),
            ),
            const SizedBox(width: 8),

            // 其他文件夹
            ...provider.folders.map((folder) {
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _buildFolderChip(
                  name: folder.name,
                  displayName: folder.name,
                  isSelected: provider.selectedFolder == folder.name,
                  onTap: () => provider.selectFolder(folder.name),
                ),
              );
            }),

            // 添加按钮
            _buildAddFolderChip(),
          ],
        ),
      ),
    );
  }

  /// 构建文件夹chip
  Widget _buildFolderChip({
    required String name,
    required String displayName,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return NeumorphicButton(
      onPressed: onTap,
      style: NeumorphicStyle(
        depth: isSelected ? -2 : 4,
        intensity: 0.7,
        boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(20)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Text(
        displayName,
        style: TextStyle(
          fontSize: 13,
          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
          color: ThemeColors.text(context).withOpacity(0.6), // 灰色
        ),
      ),
    );
  }

  /// 构建添加文件夹chip
  Widget _buildAddFolderChip() {
    return NeumorphicButton(
      onPressed: _showAddFolderDialog,
      style: NeumorphicStyle(
        depth: 4,
        intensity: 0.7,
        boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(20)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.add,
            size: 16,
            color: ThemeColors.text(context).withOpacity(0.6), // 灰色
          ),
          const SizedBox(width: 4),
          Text(
            '添加',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: ThemeColors.text(context).withOpacity(0.6), // 灰色
            ),
          ),
        ],
      ),
    );
  }

  /// 构建"下载列表"文字入口
  Widget _buildTaskListLink() {
    return GestureDetector(
      onTap: _navigateToTaskList,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          '下载列表',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: ThemeColors.text(context).withOpacity(0.7),
          ),
        ),
      ),
    );
  }
}
