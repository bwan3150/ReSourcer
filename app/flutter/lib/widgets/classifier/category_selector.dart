import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart';
import '../../models/classifier_category.dart';
import '../../utils/theme_colors.dart';
import '../common/neumorphic_dialog.dart';

/// 分类选择器组件 - 可滚动列表，支持几十个分类，支持拖拽调整高度
class CategorySelector extends StatefulWidget {
  final List<ClassifierCategory> categories;
  final Function(String) onSelectCategory;
  final Function(String) onAddCategory;
  final bool isExpanded;
  final VoidCallback onToggleExpanded;

  const CategorySelector({
    Key? key,
    required this.categories,
    required this.onSelectCategory,
    required this.onAddCategory,
    required this.isExpanded,
    required this.onToggleExpanded,
  }) : super(key: key);

  @override
  State<CategorySelector> createState() => _CategorySelectorState();
}

class _CategorySelectorState extends State<CategorySelector> {
  static const double _minHeightCollapsed = 150.0; // 最小高度（切换为水平模式的阈值，确保一行按钮完整显示）
  static const double _maxHeight = 400.0; // 最大高度
  static const double _defaultHeight = 150.0; // 默认高度（改为收起状态）

  double _currentHeight = _defaultHeight;

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final screenHeight = MediaQuery.of(context).size.height;

    // 限制最大高度为屏幕高度的40%
    final maxAllowedHeight = (screenHeight * 0.4).clamp(_minHeightCollapsed, _maxHeight);

    // 判断是否应该显示为水平模式
    final isHorizontalMode = _currentHeight <= _minHeightCollapsed;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 把手
        _buildHandle(context),

        // 分类列表 - 根据高度自动切换显示样式
        if (isHorizontalMode)
          _buildCollapsedView(context, bottomPadding)
        else
          _buildExpandedView(context, bottomPadding, _currentHeight.clamp(_minHeightCollapsed, maxAllowedHeight)),
      ],
    );
  }

  /// 构建把手
  Widget _buildHandle(BuildContext context) {
    return GestureDetector(
      onVerticalDragUpdate: (details) {
        setState(() {
          // 向下拖为正，向上拖为负
          // 我们希望向下拖时增加高度，向上拖时减少高度
          _currentHeight -= details.delta.dy;

          // 限制在合理范围内（最小为 _minHeightCollapsed，保证一行按钮可见）
          final screenHeight = MediaQuery.of(context).size.height;
          final maxAllowedHeight = (screenHeight * 0.4).clamp(_minHeightCollapsed, _maxHeight);
          _currentHeight = _currentHeight.clamp(_minHeightCollapsed, maxAllowedHeight);
        });
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: NeumorphicTheme.baseColor(context),
          border: Border(
            top: BorderSide(
              color: ThemeColors.textSecondary(context).withOpacity(0.1),
              width: 1,
            ),
          ),
        ),
        child: Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: ThemeColors.textSecondary(context).withOpacity(0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }

  /// 展开视图 - 垂直列表
  Widget _buildExpandedView(BuildContext context, double bottomPadding, double height) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: NeumorphicTheme.baseColor(context),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.fromLTRB(16, 12, 16, 80 + bottomPadding),
        itemCount: widget.categories.length + 1,
        itemBuilder: (context, index) {
          if (index == widget.categories.length) {
            return _buildAddButton(context);
          }

          final category = widget.categories[index];

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _buildCategoryButton(
              context,
              category.name,
              category.fileCount,
            ),
          );
        },
      ),
    );
  }

  /// 收起视图 - 水平滑动
  Widget _buildCollapsedView(BuildContext context, double bottomPadding) {
    return Container(
      decoration: BoxDecoration(
        color: NeumorphicTheme.baseColor(context),
      ),
      padding: EdgeInsets.only(bottom: 80 + bottomPadding), // 增加底部空白避免被导航栏遮挡
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // 分类按钮
            for (int i = 0; i < widget.categories.length; i++) ...[
              _buildCompactCategoryButton(context, widget.categories[i].name, widget.categories[i].fileCount),
              const SizedBox(width: 8),
            ],
            // 添加按钮
            _buildCompactAddButton(context),
          ],
        ),
      ),
    );
  }

  /// 构建分类按钮
  Widget _buildCategoryButton(
    BuildContext context,
    String category,
    int fileCount,
  ) {
    return NeumorphicButton(
      onPressed: () => widget.onSelectCategory(category),
      style: NeumorphicStyle(
        depth: 4,
        intensity: 0.8,
        boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(12)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // 分类名称（不省略）
          Expanded(
            child: Text(
              category,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: ThemeColors.text(context),
              ),
              // 不使用 overflow，让文字完整显示
              maxLines: 2,
            ),
          ),
          // 文件数量
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: ThemeColors.textSecondary(context).withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '$fileCount',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: ThemeColors.textSecondary(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建紧凑型分类按钮（水平滑动用）
  Widget _buildCompactCategoryButton(
    BuildContext context,
    String category,
    int fileCount,
  ) {
    return NeumorphicButton(
      onPressed: () => widget.onSelectCategory(category),
      style: NeumorphicStyle(
        depth: 4,
        intensity: 0.8,
        boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(20)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            category,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: ThemeColors.text(context),
            ),
            maxLines: 1,
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: ThemeColors.textSecondary(context).withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$fileCount',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: ThemeColors.textSecondary(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建紧凑型添加按钮（水平滑动用）
  Widget _buildCompactAddButton(BuildContext context) {
    return NeumorphicButton(
      onPressed: () => _showAddCategoryDialog(context),
      style: NeumorphicStyle(
        depth: 4,
        intensity: 0.8,
        boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(20)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.add_circle_outline,
            size: 18,
            color: ThemeColors.text(context),
          ),
          const SizedBox(width: 6),
          Text(
            '添加',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: ThemeColors.text(context),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建添加按钮
  Widget _buildAddButton(BuildContext context) {
    return NeumorphicButton(
      onPressed: () => _showAddCategoryDialog(context),
      style: NeumorphicStyle(
        depth: 4,
        intensity: 0.8,
        boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(12)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.add_circle_outline,
            size: 20,
            color: ThemeColors.text(context),
          ),
          const SizedBox(width: 8),
          Text(
            '添加新分类',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: ThemeColors.text(context),
            ),
          ),
        ],
      ),
    );
  }

  /// 显示添加分类对话框
  void _showAddCategoryDialog(BuildContext context) {
    final controller = TextEditingController();

    NeumorphicDialog.showCustom<void>(
      context: context,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '添加新分类',
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
                boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(10)),
              ),
              child: TextField(
                controller: controller,
                autofocus: true,
                style: TextStyle(
                  fontSize: 16,
                  color: ThemeColors.text(context),
                ),
                decoration: InputDecoration(
                  hintText: '分类名称',
                  hintStyle: TextStyle(
                    color: ThemeColors.textSecondary(context),
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                onSubmitted: (value) {
                  if (value.trim().isNotEmpty) {
                    Navigator.pop(context);
                    widget.onAddCategory(value.trim());
                  }
                },
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
                    intensity: 0.7,
                    boxShape: NeumorphicBoxShape.roundRect(
                      BorderRadius.circular(10),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
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
                  onPressed: () {
                    final name = controller.text.trim();
                    if (name.isNotEmpty) {
                      Navigator.pop(context);
                      widget.onAddCategory(name);
                    }
                  },
                  style: NeumorphicStyle(
                    depth: 4,
                    intensity: 0.7,
                    boxShape: NeumorphicBoxShape.roundRect(
                      BorderRadius.circular(10),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  child: Text(
                    '添加',
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
}
