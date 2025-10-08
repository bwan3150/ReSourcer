import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/classifier_provider.dart';
import '../../utils/theme_colors.dart';
import '../../widgets/common/neumorphic_dialog.dart';
import '../../widgets/common/neumorphic_overlay_appbar.dart';
import '../../widgets/classifier/file_preview.dart';
import '../../widgets/classifier/category_selector.dart';
import '../../widgets/classifier/progress_header.dart';

/// 分类器主界面
class ClassifierScreen extends StatefulWidget {
  const ClassifierScreen({Key? key}) : super(key: key);

  @override
  State<ClassifierScreen> createState() => _ClassifierScreenState();
}

class _ClassifierScreenState extends State<ClassifierScreen> {
  final TextEditingController _renameController = TextEditingController();
  bool _showRenameField = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  @override
  void dispose() {
    _renameController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final classifierProvider = Provider.of<ClassifierProvider>(context, listen: false);

    if (authProvider.apiService != null) {
      await classifierProvider.initialize(authProvider.apiService!);
    }
  }

  Future<void> _handleRefresh() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final classifierProvider = Provider.of<ClassifierProvider>(context, listen: false);

    if (authProvider.apiService != null) {
      await classifierProvider.refresh(authProvider.apiService!);
    }
  }

  /// 处理分类操作
  Future<void> _handleClassify(String category) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final classifierProvider = Provider.of<ClassifierProvider>(context, listen: false);

    if (authProvider.apiService == null) return;

    final newName = _renameController.text.trim();
    final success = await classifierProvider.moveToCategory(
      authProvider.apiService!,
      category,
      newName: newName.isEmpty ? null : newName,
    );

    if (success) {
      // 清空重命名输入框
      _renameController.clear();
      setState(() => _showRenameField = false);
    }
  }

  /// 撤销操作
  Future<void> _handleUndo() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final classifierProvider = Provider.of<ClassifierProvider>(context, listen: false);

    if (authProvider.apiService == null) return;

    final success = await classifierProvider.undo(authProvider.apiService!);
    if (!success && classifierProvider.error != null) {
      _showError(classifierProvider.error!);
      classifierProvider.clearError();
    }
  }

  /// 显示错误提示
  void _showError(String message) {
    NeumorphicDialog.showInfo(
      context: context,
      title: '错误',
      content: message,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NeumorphicTheme.baseColor(context),
      body: SafeArea(
        child: Consumer<ClassifierProvider>(
          builder: (context, provider, child) {
            // 加载中
            if (provider.isLoading) {
              return Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(ThemeColors.text(context)),
                ),
              );
            }

            // 错误状态
            if (provider.error != null) {
              return _buildErrorView(provider.error!);
            }

            // 完成状态
            if (provider.isCompleted) {
              return _buildCompletedView(provider);
            }

            // 没有文件
            if (!provider.hasFiles) {
              return _buildEmptyView();
            }

            // 正常分类界面
            return _buildClassifierView(provider);
          },
        ),
      ),
    );
  }

  /// 错误视图
  Widget _buildErrorView(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: ThemeColors.textSecondary(context),
            ),
            const SizedBox(height: 24),
            Text(
              error,
              style: TextStyle(
                fontSize: 16,
                color: ThemeColors.textSecondary(context),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            NeumorphicButton(
              onPressed: _handleRefresh,
              style: NeumorphicStyle(
                depth: 4,
                intensity: 0.8,
                boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(12)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              child: Text(
                '重试',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: ThemeColors.text(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 空状态视图
  Widget _buildEmptyView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Neumorphic(
            style: NeumorphicStyle(
              shape: NeumorphicShape.concave,
              boxShape: const NeumorphicBoxShape.circle(),
              depth: 8,
              intensity: 0.8,
            ),
            child: Container(
              width: 80,
              height: 80,
              alignment: Alignment.center,
              child: Icon(
                Icons.check_circle_outline,
                size: 40,
                color: ThemeColors.text(context),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '没有待分类文件',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: ThemeColors.text(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '源文件夹中没有找到支持的文件',
            style: TextStyle(
              fontSize: 14,
              color: ThemeColors.textSecondary(context),
            ),
          ),
        ],
      ),
    );
  }

  /// 完成视图
  Widget _buildCompletedView(ClassifierProvider provider) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Neumorphic(
            style: NeumorphicStyle(
              shape: NeumorphicShape.concave,
              boxShape: const NeumorphicBoxShape.circle(),
              depth: 8,
              intensity: 0.8,
            ),
            child: Container(
              width: 100,
              height: 100,
              alignment: Alignment.center,
              child: Icon(
                Icons.celebration_outlined,
                size: 50,
                color: ThemeColors.text(context),
              ),
            ),
          ),
          const SizedBox(height: 32),
          Text(
            '全部完成！',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: ThemeColors.text(context),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '已处理 ${provider.processedCount} 个文件',
            style: TextStyle(
              fontSize: 18,
              color: ThemeColors.textSecondary(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            provider.sourceFolder ?? '',
            style: TextStyle(
              fontSize: 14,
              color: ThemeColors.textSecondary(context),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 40),
          NeumorphicButton(
            onPressed: _handleRefresh,
            style: NeumorphicStyle(
              depth: 4,
              intensity: 0.8,
              boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(12)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            child: Text(
              '重新加载',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: ThemeColors.text(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 分类器主视图
  Widget _buildClassifierView(ClassifierProvider provider) {
    return Stack(
      children: [
        // 主内容区域
        Column(
          children: [
            // 顶部进度条
            ProgressHeader(
              currentCount: provider.processedCount,
              totalCount: provider.totalFileCount,
              progress: provider.progressPercentage,
            ),

            // 文件预览区域
            Expanded(
              child: FilePreview(
                file: provider.currentFile!,
                useThumbnail: provider.useThumbnail,
                onToggleThumbnail: () => provider.toggleThumbnail(),
                renameController: _renameController,
                showRenameField: _showRenameField,
                onToggleRename: () {
                  setState(() => _showRenameField = !_showRenameField);
                },
              ),
            ),

            // 底部分类选择器
            CategorySelector(
              categories: provider.visibleCategories,
              onSelectCategory: _handleClassify,
              onAddCategory: (name) async {
                final authProvider = Provider.of<AuthProvider>(context, listen: false);
                if (authProvider.apiService != null) {
                  await provider.addCategory(authProvider.apiService!, name);
                }
              },
            ),
          ],
        ),

        // 顶部悬浮 AppBar
        _buildOverlayAppBar(provider),
      ],
    );
  }

  /// 顶部悬浮 AppBar
  Widget _buildOverlayAppBar(ClassifierProvider provider) {
    final currentFile = provider.currentFile;
    if (currentFile == null) return const SizedBox.shrink();

    return NeumorphicOverlayAppBar(
      title: currentFile.nameWithoutExtension,
      onTitleTap: () => _showFullFileName(currentFile.name),
      leading: provider.canUndo
          ? NeumorphicCircleButton(
              icon: Icons.undo,
              onPressed: _handleUndo,
              iconSize: 20,
            )
          : null,
      trailing: NeumorphicCircleButton(
        icon: _showRenameField ? Icons.close : Icons.edit,
        onPressed: () {
          setState(() => _showRenameField = !_showRenameField);
        },
        iconSize: 20,
      ),
    );
  }

  /// 显示完整文件名
  void _showFullFileName(String fullName) {
    NeumorphicDialog.showInfo(
      context: context,
      title: '文件名',
      content: fullName,
    );
  }
}
