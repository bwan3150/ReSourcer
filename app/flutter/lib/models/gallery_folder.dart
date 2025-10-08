/// 画廊文件夹模型
class GalleryFolder {
  final String name;
  final String path;
  final int fileCount;
  final bool isSource;

  GalleryFolder({
    required this.name,
    required this.path,
    required this.fileCount,
    required this.isSource,
  });

  factory GalleryFolder.fromJson(Map<String, dynamic> json) {
    return GalleryFolder(
      name: json['name'] ?? '',
      path: json['path'] ?? '',
      fileCount: json['file_count'] ?? 0,
      isSource: json['is_source'] ?? false,
    );
  }
}
