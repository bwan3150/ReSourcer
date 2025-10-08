import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart';
import 'package:provider/provider.dart';
import '../../models/source_folder.dart';
import '../../providers/auth_provider.dart';
import '../../providers/source_folder_provider.dart';
import '../../services/api_service.dart';
import '../../utils/theme_colors.dart';
import '../../screens/source_folder/source_folder_list_screen.dart';

/// 源文件夹下拉选择器
class SourceFolderDropdown extends StatelessWidget {
  final VoidCallback onFolderChanged;

  const SourceFolderDropdown({
    Key? key,
    required this.onFolderChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<SourceFolderProvider>(
      builder: (context, provider, child) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: NeumorphicBackground(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: ListView.builder(
                shrinkWrap: true,
                physics: const BouncingScrollPhysics(),
                itemCount: provider.sourceFolders.length + 1, // +1 for management option
                itemBuilder: (context, index) {
                  // 最后一项是"源文件夹管理"
                  if (index == provider.sourceFolders.length) {
                    return NeumorphicButton(
                      onPressed: () {
                        // 先关闭下拉菜单
                        onFolderChanged();

                        // 使用 Future 来处理导航
                        Future.microtask(() async {
                          if (!context.mounted) return;

                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => const SourceFolderListScreen(),
                            ),
                          );

                          // 返回后刷新
                          if (context.mounted) {
                            final authProvider = Provider.of<AuthProvider>(context, listen: false);
                            final apiService = ApiService(authProvider.currentServer!);
                            await provider.loadSourceFolders(apiService);
                          }
                        });
                      },
                      style: const NeumorphicStyle(
                        depth: 0,
                        intensity: 0.6,
                        boxShape: NeumorphicBoxShape.rect(),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      child: Row(
                        children: [
                          Icon(
                            Icons.settings,
                            size: 20,
                            color: ThemeColors.textSecondary(context),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '源文件夹管理',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w400,
                                color: ThemeColors.textSecondary(context),
                              ),
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            size: 20,
                            color: ThemeColors.textSecondary(context),
                          ),
                        ],
                      ),
                    );
                  }

                  // 源文件夹选项
                  final folder = provider.sourceFolders[index];
                  final isSelected = folder.isActive;

                  return NeumorphicButton(
                    onPressed: () async {
                      if (!isSelected) {
                        final authProvider = Provider.of<AuthProvider>(context, listen: false);
                        final apiService = ApiService(authProvider.currentServer!);
                        await provider.switchToFolder(apiService, folder.path);
                      }
                      onFolderChanged();
                    },
                    style: NeumorphicStyle(
                      depth: isSelected ? -3 : 0,
                      intensity: 0.6,
                      boxShape: const NeumorphicBoxShape.rect(),
                      color: isSelected
                          ? (NeumorphicTheme.isUsingDark(context)
                              ? Colors.white.withOpacity(0.1)
                              : Colors.grey[300])
                          : null,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    child: Row(
                      children: [
                        Icon(
                          Icons.folder_outlined,
                          size: 20,
                          color: isSelected ? ThemeColors.text(context) : ThemeColors.textSecondary(context),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            folder.displayName,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                              color: isSelected ? ThemeColors.text(context) : ThemeColors.textSecondary(context),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
