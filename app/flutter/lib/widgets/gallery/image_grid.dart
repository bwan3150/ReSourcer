import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart';
import 'package:provider/provider.dart';
import '../../models/gallery_file.dart';
import '../../providers/auth_provider.dart';
import '../../utils/constants.dart';

/// 图片网格组件
class ImageGrid extends StatelessWidget {
  final List<GalleryFile> files;

  const ImageGrid({
    Key? key,
    required this.files,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.0,
      ),
      itemCount: files.length,
      itemBuilder: (context, index) {
        return ImageGridItem(file: files[index]);
      },
    );
  }
}

/// 图片网格项
class ImageGridItem extends StatelessWidget {
  final GalleryFile file;

  const ImageGridItem({
    Key? key,
    required this.file,
  }) : super(key: key);

  void _handleTap(BuildContext context) {
    Navigator.of(context).pushNamed(
      Constants.routeImageDetail,
      arguments: file,
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
              // 图片
              if (file.isImage && thumbnailUrl != null)
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
              else if (file.isVideo)
                _buildPlaceholder(Icons.videocam)
              else
                _buildPlaceholder(Icons.insert_drive_file),

              // 文件名
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withOpacity(0.7),
                      ],
                    ),
                  ),
                  child: Text(
                    file.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
