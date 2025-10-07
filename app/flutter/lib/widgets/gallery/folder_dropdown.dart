import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart';
import 'package:provider/provider.dart';
import '../../models/gallery_folder.dart';
import '../../providers/auth_provider.dart';
import '../../providers/gallery_provider.dart';

/// 文件夹下拉选择器
class FolderDropdown extends StatelessWidget {
  final VoidCallback onFolderChanged;

  const FolderDropdown({
    Key? key,
    required this.onFolderChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<GalleryProvider>(
      builder: (context, provider, child) {
        if (provider.folders.isEmpty) {
          return const SizedBox.shrink();
        }

        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: NeumorphicBackground(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: ListView.builder(
                shrinkWrap: true,
                physics: const BouncingScrollPhysics(),
                itemCount: provider.folders.length,
                itemBuilder: (context, index) {
                  final folder = provider.folders[index];
                  final isSelected = provider.currentFolder?.path == folder.path;
                  final displayName = folder.isSource ? '源文件夹' : folder.name;

                  return NeumorphicButton(
                    onPressed: () async {
                      final authProvider = Provider.of<AuthProvider>(context, listen: false);
                      if (authProvider.apiService != null) {
                        await provider.selectFolder(authProvider.apiService!, folder);
                        onFolderChanged();
                      }
                    },
                    style: NeumorphicStyle(
                      depth: isSelected ? -3 : 0,
                      intensity: 0.6,
                      boxShape: const NeumorphicBoxShape.rect(),
                      color: isSelected ? Colors.grey[300] : null,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    child: Row(
                      children: [
                        Icon(
                          folder.isSource ? Icons.source : Icons.folder,
                          size: 20,
                          color: isSelected ? const Color(0xFF171717) : Colors.grey[600],
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            displayName,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                              color: isSelected ? const Color(0xFF171717) : Colors.grey[600],
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
                              color: isSelected ? const Color(0xFF171717) : Colors.grey[700],
                            ),
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
