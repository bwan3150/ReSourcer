import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart';
import 'package:provider/provider.dart';
import '../../models/source_folder.dart';
import '../../providers/source_folder_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../utils/theme_colors.dart';
import '../../widgets/common/neumorphic_dialog.dart';
import '../../widgets/common/neumorphic_option_sheet.dart';

/// 源文件夹列表管理界面
class SourceFolderListScreen extends StatefulWidget {
  const SourceFolderListScreen({Key? key}) : super(key: key);

  @override
  State<SourceFolderListScreen> createState() => _SourceFolderListScreenState();
}

class _SourceFolderListScreenState extends State<SourceFolderListScreen> {
  @override
  void initState() {
    super.initState();
    // 初始化源文件夹列表
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final apiService = ApiService(authProvider.currentServer!);
      final provider = Provider.of<SourceFolderProvider>(context, listen: false);
      provider.loadSourceFolders(apiService);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NeumorphicTheme.baseColor(context),
      appBar: NeumorphicAppBar(
        title: Text(
          '源文件夹管理',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: ThemeColors.text(context),
          ),
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
      ),
      body: Consumer<SourceFolderProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return Center(
              child: CircularProgressIndicator(
                color: ThemeColors.text(context),
              ),
            );
          }

          if (provider.sourceFolders.isEmpty) {
            return _buildEmptyState();
          }

          return RefreshIndicator(
            onRefresh: () async {
              final authProvider = Provider.of<AuthProvider>(context, listen: false);
              final apiService = ApiService(authProvider.currentServer!);
              await provider.loadSourceFolders(apiService);
            },
            backgroundColor: NeumorphicTheme.baseColor(context),
            color: ThemeColors.text(context),
            child: ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: provider.sourceFolders.length + 1, // +1 for footer
              itemBuilder: (context, index) {
                // 最后一项显示统计信息
                if (index == provider.sourceFolders.length) {
                  return _buildFolderCountFooter(provider);
                }

                final folder = provider.sourceFolders[index];
                return _buildFolderCard(folder);
              },
            ),
          );
        },
      ),
    );
  }

  /// 源文件夹统计 Footer
  Widget _buildFolderCountFooter(SourceFolderProvider provider) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.folder_outlined,
              size: 14,
              color: Colors.grey[500],
            ),
            const SizedBox(width: 6),
            Text(
              '${provider.activeCount}/${provider.totalCount}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 源文件夹卡片 - 简约设计：状态标识+路径
  Widget _buildFolderCard(SourceFolder folder) {
    // 源文件夹卡片内容
    final cardContent = GestureDetector(
      onLongPress: folder.isActive ? null : () => _showFolderOptions(folder),
      child: Row(
        children: [
          // 文件夹路径
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  folder.displayName,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: ThemeColors.text(context),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  folder.path,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: folder.isActive
          ? // 当前源文件夹 - 使用静态 Neumorphic 显示下陷状态
          Neumorphic(
              style: NeumorphicStyle(
                depth: -4,
                intensity: 0.6,
                boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(16)),
              ),
              padding: const EdgeInsets.all(20),
              child: cardContent,
            )
          : // 其他源文件夹 - 使用 NeumorphicButton 提供点击反馈
          NeumorphicButton(
              onPressed: () => _switchFolder(folder),
              style: NeumorphicStyle(
                depth: 4,
                intensity: 0.6,
                boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(16)),
              ),
              padding: const EdgeInsets.all(20),
              child: cardContent,
            ),
    );
  }

  /// 空状态
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _AnimatedEmptyIcon(),
          const SizedBox(height: 16),
          Text(
            '未配置源文件夹',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  /// 显示文件夹操作选项
  Future<void> _showFolderOptions(SourceFolder folder) async {
    NeumorphicOptionSheet.show(
      context: context,
      title: folder.displayName,
      options: [
        SheetOption(
          icon: Icons.swap_horiz,
          text: '切换到此文件夹',
          onTap: () => _switchFolder(folder),
        ),
        SheetOption(
          icon: Icons.delete_outline,
          text: '删除',
          textColor: ThemeColors.textSecondary(context),
          iconColor: ThemeColors.textSecondary(context),
          onTap: () => _removeFolder(folder),
        ),
      ],
    );
  }

  /// 切换源文件夹
  Future<void> _switchFolder(SourceFolder folder) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final apiService = ApiService(authProvider.currentServer!);
    final provider = Provider.of<SourceFolderProvider>(context, listen: false);

    await provider.switchToFolder(apiService, folder.path);

    if (mounted) {
      // 等待一小段时间让用户看到反馈效果
      await Future.delayed(const Duration(milliseconds: 300));
    }
  }

  /// 删除源文件夹
  Future<void> _removeFolder(SourceFolder folder) async {
    final confirm = await NeumorphicDialog.showConfirm(
      context: context,
      title: '删除',
      content: '删除 "${folder.displayName}"？',
      confirmText: '删除',
      confirmTextColor: Colors.red,
    );

    if (confirm == true && mounted) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final apiService = ApiService(authProvider.currentServer!);
      final provider = Provider.of<SourceFolderProvider>(context, listen: false);

      await provider.removeSourceFolder(apiService, folder.path);
    }
  }
}

/// 带动画的空状态图标
class _AnimatedEmptyIcon extends StatefulWidget {
  @override
  State<_AnimatedEmptyIcon> createState() => _AnimatedEmptyIconState();
}

class _AnimatedEmptyIconState extends State<_AnimatedEmptyIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );

    _opacityAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );

    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Opacity(
            opacity: _opacityAnimation.value,
            child: child,
          ),
        );
      },
      child: NeumorphicIcon(
        Icons.folder_off_outlined,
        size: 80,
        style: NeumorphicStyle(
          depth: 4,
          intensity: 0.6,
          color: NeumorphicTheme.baseColor(context),
        ),
      ),
    );
  }
}
