import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/gallery_provider.dart';
import '../../providers/upload_provider.dart';
import '../../models/gallery_folder.dart';
import '../../utils/theme_colors.dart';
import '../../widgets/gallery/image_grid.dart';
import '../../widgets/gallery/folder_dropdown.dart';
import '../../widgets/gallery/upload_helper.dart';
import '../upload/upload_tasks_screen.dart';

/// 画廊页面
class GalleryScreen extends StatefulWidget {
  const GalleryScreen({Key? key}) : super(key: key);

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  bool _isDropdownOpen = false;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    // 使用 addPostFrameCallback 延迟到 build 完成后再加载数据
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  Future<void> _loadData() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final galleryProvider = Provider.of<GalleryProvider>(context, listen: false);

    if (authProvider.apiService != null) {
      await galleryProvider.loadFolders(authProvider.apiService!);
    }
  }

  Future<void> _handleRefresh() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final galleryProvider = Provider.of<GalleryProvider>(context, listen: false);

    if (authProvider.apiService != null) {
      await galleryProvider.refresh(authProvider.apiService!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NeumorphicTheme.baseColor(context),
      body: SafeArea(
          child: Stack(
            children: [
              // 主内容 - 图片网格
              Consumer<GalleryProvider>(
                builder: (context, provider, child) {
                  if (provider.isLoading && provider.files.isEmpty) {
                    return Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(ThemeColors.text(context)),
                      ),
                    );
                  }

                  if (provider.error != null) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            size: 64,
                            color: Colors.grey,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            provider.error!,
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                          const SizedBox(height: 16),
                          NeumorphicButton(
                            onPressed: _handleRefresh,
                            child: const Text('重试'),
                          ),
                        ],
                      ),
                    );
                  }

                  // 始终显示 ImageGrid，即使为空也会显示上传按钮
                  return RefreshIndicator(
                    onRefresh: _handleRefresh,
                    backgroundColor: NeumorphicTheme.baseColor(context),
                    color: ThemeColors.text(context),
                    child: ImageGrid(
                      files: provider.files,
                      fileCount: provider.files.length,
                      currentFolderPath: provider.currentFolder?.path,
                    ),
                  );
                },
              ),

              // 顶部镂空按钮（浮动）
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _buildHeader(),
              ),

              // 遮罩层（点击关闭下拉菜单）- 必须在下拉菜单之前，不覆盖下拉菜单区域
              if (_isDropdownOpen)
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () => setState(() => _isDropdownOpen = false),
                    child: Container(color: Colors.black.withOpacity(0.3)),
                  ),
                ),

              // 下拉菜单 - 在遮罩层之上
              if (_isDropdownOpen)
                Positioned(
                  top: 76, // 浮动按钮高度
                  left: 20,
                  right: 20,
                  child: _buildFolderDropdown(),
                ),

              // 右下角悬浮上传按钮（位置基于导航栏）
              Positioned(
                right: 20,
                bottom: 90, // 底部导航栏高度 + 间距
                child: NeumorphicButton(
                  onPressed: _uploading ? null : _showUploadMethodDialog,
                  style: const NeumorphicStyle(
                    boxShape: NeumorphicBoxShape.circle(),
                    depth: 4,
                    intensity: 0.8,
                  ),
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: 32,
                    height: 32,
                    child: _uploading
                        ? CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(ThemeColors.text(context)),
                            strokeWidth: 3,
                          )
                        : Icon(
                            Icons.add,
                            size: 32,
                            color: ThemeColors.text(context),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
  }

  void _showFolderSelector() {
    setState(() {
      _isDropdownOpen = !_isDropdownOpen;
    });
  }

  void _showUploadMethodDialog() {
    final galleryProvider = Provider.of<GalleryProvider>(context, listen: false);
    final targetFolder = galleryProvider.currentFolder?.path;

    final helper = UploadHelper(
      context: context,
      targetFolder: targetFolder,
      onUploadingChanged: (uploading) {
        if (mounted) {
          setState(() => _uploading = uploading);
        }
      },
    );
    helper.showUploadMethodDialog();
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // 文件夹选择器
            Expanded(
              child: Consumer<GalleryProvider>(
                builder: (context, provider, child) {
                  final folderName = provider.currentFolder?.isSource == true
                      ? '源文件夹'
                      : (provider.currentFolder?.name ?? '画廊');

                  return Neumorphic(
                    style: NeumorphicStyle(
                      depth: _isDropdownOpen ? -2 : 4,
                      intensity: 0.6,
                      boxShape: NeumorphicBoxShape.roundRect(
                        BorderRadius.circular(25),
                      ),
                    ),
                    child: NeumorphicButton(
                      onPressed: _showFolderSelector,
                      style: NeumorphicStyle(
                        depth: 0,
                        intensity: 0,
                        boxShape: NeumorphicBoxShape.roundRect(
                          BorderRadius.circular(25),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      child: Row(
                        children: [
                          Icon(
                            provider.currentFolder?.isSource == true
                                ? Icons.source
                                : Icons.folder,
                            size: 20,
                            color: ThemeColors.text(context),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              folderName,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: ThemeColors.text(context),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Icon(
                            _isDropdownOpen ? Icons.expand_less : Icons.expand_more,
                            size: 20,
                            color: ThemeColors.textSecondary(context),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 16),
            // 上传任务按钮
            NeumorphicButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const UploadTasksScreen(),
                  ),
                );
              },
              style: const NeumorphicStyle(
                boxShape: NeumorphicBoxShape.circle(),
                depth: 4,
              ),
              padding: const EdgeInsets.all(12),
              child: Icon(
                Icons.upload_file,
                size: 20,
                color: ThemeColors.text(context),
              ),
            ),
          ],
        ),
    );
  }

  Widget _buildFolderDropdown() {
    return FolderDropdown(
      onFolderChanged: () {
        setState(() => _isDropdownOpen = false);
      },
    );
  }
}

/// 文件夹选择器底部面板（已废弃，改用下拉菜单）
class _FolderSelectorSheet extends StatelessWidget {
  const _FolderSelectorSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
      decoration: BoxDecoration(
        color: NeumorphicTheme.baseColor(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // 顶部拖动条
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // 标题
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '选择文件夹',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                NeumorphicButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: const NeumorphicStyle(
                    boxShape: NeumorphicBoxShape.circle(),
                    depth: 2,
                  ),
                  padding: const EdgeInsets.all(8),
                  child: const Icon(Icons.close, size: 20),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // 文件夹列表
          Expanded(
            child: Consumer<GalleryProvider>(
              builder: (context, provider, child) {
                if (provider.folders.isEmpty) {
                  return const Center(
                    child: Text('暂无文件夹'),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: provider.folders.length,
                  itemBuilder: (context, index) {
                    final folder = provider.folders[index];
                    final isSelected = provider.currentFolder?.path == folder.path;

                    return _FolderItem(
                      folder: folder,
                      isSelected: isSelected,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 文件夹项
class _FolderItem extends StatelessWidget {
  final GalleryFolder folder;
  final bool isSelected;

  const _FolderItem({
    required this.folder,
    required this.isSelected,
  });

  Future<void> _handleSelect(BuildContext context) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final galleryProvider = Provider.of<GalleryProvider>(context, listen: false);

    if (authProvider.apiService != null) {
      await galleryProvider.selectFolder(authProvider.apiService!, folder);
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayName = folder.isSource ? '源文件夹' : folder.name;

    return Neumorphic(
      margin: const EdgeInsets.only(bottom: 12),
      style: NeumorphicStyle(
        depth: isSelected ? -2 : 2,
        intensity: 0.6,
        boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(12)),
      ),
      child: InkWell(
        onTap: () => _handleSelect(context),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                folder.isSource ? Icons.source : Icons.folder,
                size: 24,
                color: isSelected ? ThemeColors.text(context) : ThemeColors.textSecondary(context),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  displayName,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: ThemeColors.text(context),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF171717).withOpacity(0.1)
                      : Colors.grey[300],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${folder.fileCount}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isSelected ? ThemeColors.text(context) : Colors.grey[700],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
