import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart';
import 'package:provider/provider.dart';
import '../../models/gallery_file.dart';
import '../../providers/auth_provider.dart';
import '../../utils/constants.dart';

import '../../screens/gallery/image_detail_screen.dart';

/// 图片网格组件
class ImageGrid extends StatelessWidget {
  final List<GalleryFile> files;
  final int fileCount;

  const ImageGrid({
    Key? key,
    required this.files,
    required this.fileCount,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(12),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.0,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                return ImageGridItem(
                  file: files[index],
                  allFiles: files,
                  currentIndex: index,
                );
              },
              childCount: files.length,
            ),
          ),
        ),
        // 底部文件计数
        SliverToBoxAdapter(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Text(
                '$fileCount ${fileCount == 1 ? 'file' : 'files'}',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[600],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 图片网格项
class ImageGridItem extends StatelessWidget {
  final GalleryFile file;
  final List<GalleryFile> allFiles;
  final int currentIndex;

  const ImageGridItem({
    Key? key,
    required this.file,
    required this.allFiles,
    required this.currentIndex,
  }) : super(key: key);

  void _handleTap(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ImageDetailScreen(
          files: allFiles,
          initialIndex: currentIndex,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final thumbnailUrl = authProvider.apiService?.getThumbnailUrl(file.path);

    return GestureDetector(
      onTap: () => _handleTap(context),
      child: Neumorphic(
        style: NeumorphicStyle(
          depth: 4,
          intensity: 0.8,
          boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(12)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 根据文件类型显示内容
              if (file.isImage && thumbnailUrl != null)
                // 普通图片使用缩略图
                Image.network(
                  thumbnailUrl,
                  fit: BoxFit.cover,
                  headers: {
                    'Cookie': 'api_key=${authProvider.apiKey}',
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return _buildPlaceholder(Icons.broken_image);
                  },
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return _buildPlaceholder(Icons.image);
                  },
                )
              else if (file.isGif)
                // GIF直接加载原文件以显示动画
                Image.network(
                  authProvider.apiService!.getImageUrl(file.path),
                  fit: BoxFit.cover,
                  headers: {
                    'Cookie': 'api_key=${authProvider.apiKey}',
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return _buildPlaceholder(Icons.broken_image);
                  },
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return _buildPlaceholder(Icons.gif);
                  },
                )
              else if (file.isVideo)
                // 视频显示占位符（点击后进入详情页播放）
                Container(
                  color: Colors.grey[800],
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Icon(
                        Icons.play_circle_outline,
                        size: 64,
                        color: Colors.white.withOpacity(0.8),
                      ),
                    ],
                  ),
                )
              else
                _buildPlaceholder(Icons.insert_drive_file),

              // 右下角的文件类型标签
              Positioned(
                bottom: 6,
                right: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    file.extension.replaceFirst('.', '').toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder(IconData icon) {
    return Container(
      color: Colors.grey[300],
      child: Icon(
        icon,
        size: 40,
        color: Colors.grey[500],
      ),
    );
  }
}

