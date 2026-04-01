import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart';
import '../../models/download_task.dart';
import '../../utils/theme_colors.dart';

/// 文件夹选择器（横向滚动chip）
class FolderSelector extends StatelessWidget {
  final List<DownloadFolder> folders;
  final String selectedFolder;
  final ValueChanged<String> onFolderSelected;
  final VoidCallback onAddFolder;

  const FolderSelector({
    Key? key,
    required this.folders,
    required this.selectedFolder,
    required this.onFolderSelected,
    required this.onAddFolder,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Row(
            children: [
              Icon(
                Icons.folder,
                size: 16,
                color: ThemeColors.textSecondary(context),
              ),
              const SizedBox(width: 6),
              Text(
                '目标文件夹',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: ThemeColors.textSecondary(context),
                ),
              ),
            ],
          ),
        ),

        // 横向滚动chip列表
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              // 源文件夹
              _buildFolderChip(
                context: context,
                folderName: '',
                displayName: '源文件夹',
                isSelected: selectedFolder == '',
                icon: Icons.source,
              ),

              const SizedBox(width: 8),

              // 其他文件夹
              ...folders.map((folder) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _buildFolderChip(
                    context: context,
                    folderName: folder.name,
                    displayName: folder.name,
                    isSelected: selectedFolder == folder.name,
                    icon: Icons.folder,
                  ),
                );
              }),

              // 添加按钮
              _buildAddButton(context),
            ],
          ),
        ),
      ],
    );
  }

  /// 构建文件夹chip
  Widget _buildFolderChip({
    required BuildContext context,
    required String folderName,
    required String displayName,
    required bool isSelected,
    required IconData icon,
  }) {
    return NeumorphicButton(
      onPressed: () => onFolderSelected(folderName),
      style: NeumorphicStyle(
        depth: isSelected ? -2 : 2,
        intensity: 0.6,
        boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(20)),
        color: isSelected
            ? (NeumorphicTheme.isUsingDark(context)
                ? Colors.white.withOpacity(0.1)
                : Colors.black.withOpacity(0.05))
            : NeumorphicTheme.baseColor(context),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: isSelected
                ? ThemeColors.text(context)
                : ThemeColors.textSecondary(context),
          ),
          const SizedBox(width: 6),
          Text(
            displayName,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              color: isSelected
                  ? ThemeColors.text(context)
                  : ThemeColors.textSecondary(context),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建添加按钮
  Widget _buildAddButton(BuildContext context) {
    return NeumorphicButton(
      onPressed: onAddFolder,
      style: NeumorphicStyle(
        depth: 2,
        intensity: 0.6,
        boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(20)),
        border: NeumorphicBorder(
          color: ThemeColors.textSecondary(context).withOpacity(0.3),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.add,
            size: 16,
            color: ThemeColors.textSecondary(context),
          ),
          const SizedBox(width: 4),
          Text(
            '添加文件夹',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: ThemeColors.textSecondary(context),
            ),
          ),
        ],
      ),
    );
  }
}
