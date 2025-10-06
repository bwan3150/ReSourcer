/// 画廊文件模型
class GalleryFile {
  final String name;
  final String path;  // 文件路径
  final String fileType;
  final String extension;
  final int size;
  final String modifiedTime;

  GalleryFile({
    required this.name,
    required this.path,
    required this.fileType,
    required this.extension,
    required this.size,
    required this.modifiedTime,
  });

  factory GalleryFile.fromJson(Map<String, dynamic> json) {
    return GalleryFile(
      name: json['name'] ?? '',
      path: json['path'] ?? '',
      fileType: json['file_type'] ?? '',
      extension: json['extension'] ?? '',
      size: json['size'] ?? 0,
      modifiedTime: json['modified_time'] ?? '',
    );
  }

  bool get isImage {
    return fileType.toLowerCase() == 'image';
  }

  bool get isVideo {
    return fileType.toLowerCase() == 'video';
  }

  bool get isGif {
    return fileType.toLowerCase() == 'gif';
  }
}
