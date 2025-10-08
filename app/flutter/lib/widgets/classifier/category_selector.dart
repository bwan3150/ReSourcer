import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart';
import '../../models/classifier_category.dart';
import '../../utils/theme_colors.dart';
import '../common/neumorphic_dialog.dart';

/// 分类选择器组件 - 可滚动列表，支持几十个分类
class CategorySelector extends StatelessWidget {
  final List<ClassifierCategory> categories;
  final Function(String) onSelectCategory;
  final Function(String) onAddCategory;

  const CategorySelector({
    Key? key,
    required this.categories,
    required this.onSelectCategory,
    required this.onAddCategory,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // 计算底部安全区域高度
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      constraints: BoxConstraints(
        // 最大高度为屏幕的 40%，确保不会占用太多空间
        maxHeight: MediaQuery.of(context).size.height * 0.4,
      ),
      decoration: BoxDecoration(
        color: NeumorphicTheme.baseColor(context),
        border: Border(
          top: BorderSide(
            color: ThemeColors.textSecondary(context).withOpacity(0.1),
            width: 1,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 可滚动的分类列表
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
              itemCount: categories.length,
              itemBuilder: (context, index) {
                final category = categories[index];
                final shortcut = _getShortcutKey(index);

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _buildCategoryButton(
                    context,
                    category.name,
                    shortcut,
                  ),
                );
              },
            ),
          ),

          // 底部固定区域：添加按钮
          Container(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 12 + bottomPadding),
            decoration: BoxDecoration(
              color: NeumorphicTheme.baseColor(context),
              border: Border(
                top: BorderSide(
                  color: ThemeColors.textSecondary(context).withOpacity(0.1),
                  width: 1,
                ),
              ),
            ),
            child: _buildAddButton(context),
          ),
        ],
      ),
    );
  }

  /// 构建分类按钮
  Widget _buildCategoryButton(
    BuildContext context,
    String category,
    String? shortcut,
  ) {
    return NeumorphicButton(
      onPressed: () => onSelectCategory(category),
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
          // 快捷键提示
          if (shortcut != null) ...[
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: ThemeColors.textSecondary(context).withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                shortcut,
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                  color: ThemeColors.textSecondary(context),
                ),
              ),
            ),
          ],
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
                    onAddCategory(value.trim());
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
                      onAddCategory(name);
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

  /// 获取快捷键（1-9, a-z）
  String? _getShortcutKey(int index) {
    if (index < 9) {
      return (index + 1).toString();
    } else if (index < 35) {
      return String.fromCharCode(97 + (index - 9)); // a-z
    }
    return null;
  }
}
