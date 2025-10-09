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
import '../../widgets/downloader/task_card.dart';
import '../../widgets/downloader/folder_selector.dart';
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
  bool _isTasksExpanded = true;
  Timer? _detectDebounce;

  @override
  void initState() {
    super.initState();
    _initializeData();

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

  Future<void> _initializeData() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.apiService != null) {
      final downloaderProvider =
          DownloaderProvider(authProvider.apiService!);

      // 使用Future.microtask避免在build期间调用
      Future.microtask(() {
        if (mounted) {
          // 将provider注册到widget树中
          Provider.of<DownloaderProvider>(context, listen: false).initialize();
        }
      });
    }
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

  /// 创建下载任务（使用传入的正确context）
  Future<void> _startDownloadWithContext(BuildContext context) async {
    debugPrint('点击下载按钮');

    final url = _urlController.text.trim();
    if (url.isEmpty) {
      NeumorphicToast.showError(context, '请输入URL');
      debugPrint('URL为空，返回');
      return;
    }

    debugPrint('URL: $url');

    try {
      final downloaderProvider =
          Provider.of<DownloaderProvider>(context, listen: false);

      debugPrint('准备创建任务: downloader=$_selectedDownloader, folder=${downloaderProvider.selectedFolder}');

      final success = await downloaderProvider.createTask(
        url: url,
        downloader: _selectedDownloader,
        saveFolder: downloaderProvider.selectedFolder,
      );

      debugPrint('任务创建结果: $success');

      if (mounted) {
        if (success) {
          NeumorphicToast.showSuccess(context, '任务已创建');
          _urlController.clear();
          setState(() {
            _detectResult = null;
            _isTasksExpanded = true; // 自动展开任务列表
          });
        } else {
          final error = downloaderProvider.error ?? '创建任务失败';
          debugPrint('创建失败: $error');
          NeumorphicToast.showError(context, error);
        }
      }
    } catch (e, stackTrace) {
      debugPrint('创建任务异常: $e');
      debugPrint('堆栈: $stackTrace');
      if (mounted) {
        NeumorphicToast.showError(context, '创建任务异常: $e');
      }
    }
  }

  /// 显示添加文件夹对话框
  Future<void> _showAddFolderDialog() async {
    final controller = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: NeumorphicTheme.baseColor(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          '新建文件夹',
          style: TextStyle(color: ThemeColors.text(context)),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: ThemeColors.text(context)),
          decoration: InputDecoration(
            hintText: '输入文件夹名称',
            hintStyle: TextStyle(color: ThemeColors.textSecondary(context)),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: ThemeColors.textSecondary(context)),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              '取消',
              style: TextStyle(color: ThemeColors.textSecondary(context)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              '创建',
              style: TextStyle(color: ThemeColors.text(context)),
            ),
          ),
        ],
      ),
    );

    if (result == true && controller.text.trim().isNotEmpty) {
      final downloaderProvider =
          Provider.of<DownloaderProvider>(context, listen: false);

      final success = await downloaderProvider.createFolder(controller.text.trim());
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
  }

  /// 取消任务
  Future<void> _cancelTask(DownloadTask task) async {
    final confirm = await NeumorphicDialog.showConfirm(
      context: context,
      title: '取消下载',
      content: '确定要取消这个下载任务吗？',
      confirmText: '取消下载',
    );

    if (confirm == true) {
      final downloaderProvider =
          Provider.of<DownloaderProvider>(context, listen: false);

      final success = await downloaderProvider.cancelTask(task.id);
      if (mounted) {
        if (success) {
          NeumorphicToast.showSuccess(context, '任务已取消');
        } else {
          NeumorphicToast.showError(context, '取消任务失败');
        }
      }
    }
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

  /// 清空历史记录
  Future<void> _clearHistory() async {
    final confirm = await NeumorphicDialog.showConfirm(
      context: context,
      title: '清空历史',
      content: '确定要清空所有已完成、失败和已取消的任务吗？',
      confirmText: '清空',
    );

    if (confirm == true) {
      final downloaderProvider =
          Provider.of<DownloaderProvider>(context, listen: false);

      final success = await downloaderProvider.clearHistory();
      if (mounted) {
        if (success) {
          NeumorphicToast.showSuccess(context, '历史已清空');
        } else {
          NeumorphicToast.showError(context, '清空历史失败');
        }
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
          NeumorphicToast.showSuccess(context, '已粘贴URL');
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

  /// 预览文件（使用画廊的图片视频查看器）
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

    // 获取文件扩展名
    final extension = task.filePath!.split('.').last.toLowerCase();

    // 根据扩展名推断文件类型
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

    // 创建一个GalleryFile对象用于预览
    final galleryFile = GalleryFile(
      name: task.fileName ?? task.filePath!.split('/').last,
      path: task.filePath!,
      fileType: fileType,
      extension: extension,
      size: 0, // 大小未知
      modifiedTime: task.completedAt?.toIso8601String() ?? '',
    );

    // 使用ImageDetailScreen查看
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ImageDetailScreen(
          files: [galleryFile],
          initialIndex: 0,
        ),
      ),
    );
  }

  /// 打开文件夹（简单实现：显示提示）
  void _openFolder(DownloadTask task) {
    NeumorphicToast.showInfo(context, '打开文件夹功能暂不支持移动端');
    // 移动端无法直接打开系统文件夹
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
      // 使用builder确保子widget可以访问Provider
      builder: (context, child) {
        return Scaffold(
          backgroundColor: NeumorphicTheme.baseColor(context),
          body: SafeArea(
            child: RefreshIndicator(
              onRefresh: () async {
                final provider =
                    Provider.of<DownloaderProvider>(context, listen: false);
                await provider.refresh();
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 标题
                    _buildHeader(),
                    const SizedBox(height: 24),

                    // URL输入卡片
                    _buildUrlInputCard(),
                    const SizedBox(height: 20),

                    // 文件夹选择
                    Consumer<DownloaderProvider>(
                      builder: (context, provider, child) {
                        return FolderSelector(
                          folders: provider.folders,
                          selectedFolder: provider.selectedFolder,
                          onFolderSelected: provider.selectFolder,
                          onAddFolder: _showAddFolderDialog,
                        );
                      },
                    ),
                    const SizedBox(height: 20),

                    // 下载按钮
                    _buildDownloadButton(),
                    const SizedBox(height: 24),

                    // 任务列表
                    _buildTasksSection(),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 构建标题
  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          '下载器',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: ThemeColors.text(context),
          ),
        ),
        // 认证按钮（暂时隐藏，后续实现）
        // NeumorphicButton(
        //   onPressed: _showAuthDialog,
        //   style: NeumorphicStyle(
        //     boxShape: NeumorphicBoxShape.circle(),
        //     depth: 4,
        //   ),
        //   padding: const EdgeInsets.all(12),
        //   child: Icon(
        //     Icons.key,
        //     size: 20,
        //     color: ThemeColors.text(context),
        //   ),
        // ),
      ],
    );
  }

  /// 构建URL输入卡片
  Widget _buildUrlInputCard() {
    return Neumorphic(
      style: NeumorphicStyle(
        depth: 4,
        intensity: 0.6,
        boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(16)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // URL输入框带粘贴按钮
            Row(
              children: [
                // URL输入框
                Expanded(
                  child: Neumorphic(
                    style: NeumorphicStyle(
                      depth: -2,
                      intensity: 0.6,
                      boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(12)),
                    ),
                    child: TextField(
                      controller: _urlController,
                      focusNode: _urlFocusNode,
                      style: TextStyle(
                        fontSize: 15,
                        color: ThemeColors.text(context),
                      ),
                      decoration: InputDecoration(
                        hintText: '输入视频或图片URL...',
                        hintStyle: TextStyle(
                          color: ThemeColors.textSecondary(context),
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.all(14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // 粘贴按钮
                NeumorphicButton(
                  onPressed: _pasteFromClipboard,
                  style: NeumorphicStyle(
                    depth: 4,
                    boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(12)),
                  ),
                  padding: const EdgeInsets.all(14),
                  child: Icon(
                    Icons.content_paste,
                    size: 20,
                    color: ThemeColors.text(context),
                  ),
                ),
              ],
            ),

            // 检测结果（平台+下载器选择）
            if (_detectResult != null) ...[
              const SizedBox(height: 12),
              Neumorphic(
                style: NeumorphicStyle(
                  depth: 1,
                  intensity: 0.4,
                  boxShape: NeumorphicBoxShape.roundRect(
                    BorderRadius.circular(10),
                  ),
                  color: NeumorphicTheme.baseColor(context),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Icon(
                      Icons.public,
                      size: 16,
                      color: ThemeColors.textSecondary(context),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _detectResult!.platformName,
                      style: TextStyle(
                        fontSize: 13,
                        color: ThemeColors.text(context),
                      ),
                    ),
                    const Spacer(),
                    // 下载器选择器（简化为文本显示）
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: NeumorphicTheme.isUsingDark(context)
                            ? Colors.white.withOpacity(0.1)
                            : Colors.black.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _selectedDownloader == 'ytdlp' ? 'yt-dlp' : 'pixiv-toolkit',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: ThemeColors.text(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 构建下载按钮
  Widget _buildDownloadButton() {
    return Consumer<DownloaderProvider>(
      builder: (context, provider, child) {
        return NeumorphicButton(
          onPressed: () => _startDownloadWithContext(context),
          style: NeumorphicStyle(
            depth: 4,
            intensity: 0.8,
            boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(12)),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.download,
                size: 20,
                color: ThemeColors.text(context),
              ),
              const SizedBox(width: 8),
              Text(
                '开始下载',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: ThemeColors.text(context),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 构建任务列表区域
  Widget _buildTasksSection() {
    return Consumer<DownloaderProvider>(
      builder: (context, provider, child) {
        return Neumorphic(
          style: NeumorphicStyle(
            depth: 4,
            intensity: 0.6,
            boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(16)),
          ),
          child: Column(
            children: [
              // 任务标题栏（可折叠）
              NeumorphicButton(
                onPressed: () {
                  setState(() => _isTasksExpanded = !_isTasksExpanded);
                },
                style: NeumorphicStyle(
                  depth: 0,
                  boxShape: NeumorphicBoxShape.roundRect(
                    BorderRadius.circular(16),
                  ),
                ),
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Text(
                      '任务列表',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: ThemeColors.text(context),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: NeumorphicTheme.isUsingDark(context)
                            ? Colors.white.withOpacity(0.1)
                            : Colors.black.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${provider.tasks.length}',
                        style: TextStyle(
                          fontSize: 12,
                          color: ThemeColors.textSecondary(context),
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (provider.completedTaskCount > 0)
                      NeumorphicButton(
                        onPressed: _clearHistory,
                        style: const NeumorphicStyle(
                          depth: 2,
                          boxShape: NeumorphicBoxShape.circle(),
                        ),
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          Icons.delete,
                          size: 16,
                          color: ThemeColors.textSecondary(context),
                        ),
                      ),
                    const SizedBox(width: 8),
                    Icon(
                      _isTasksExpanded ? Icons.expand_less : Icons.expand_more,
                      color: ThemeColors.textSecondary(context),
                    ),
                  ],
                ),
              ),

              // 任务列表内容
              if (_isTasksExpanded)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  child: provider.tasks.isEmpty
                      ? _buildEmptyState()
                      : _buildTasksList(provider.tasks),
                ),
            ],
          ),
        );
      },
    );
  }

  /// 构建空状态
  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        children: [
          Icon(
            Icons.download_outlined,
            size: 48,
            color: ThemeColors.textSecondary(context).withOpacity(0.5),
          ),
          const SizedBox(height: 12),
          Text(
            '暂无下载任务',
            style: TextStyle(
              fontSize: 14,
              color: ThemeColors.textSecondary(context),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建任务列表
  Widget _buildTasksList(List<DownloadTask> tasks) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: tasks.map((task) {
          return TaskCard(
            task: task,
            onCancel: task.canCancel ? () => _cancelTask(task) : null,
            onDelete: task.canDelete ? () => _deleteTask(task) : null,
            onPreview: task.isCompleted ? () => _previewFile(task) : null,
            onOpenFolder: task.isCompleted ? () => _openFolder(task) : null,
          );
        }).toList(),
      ),
    );
  }
}
