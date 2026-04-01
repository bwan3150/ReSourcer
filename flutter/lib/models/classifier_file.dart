/// 分类器文件模型
class ClassifierFile {
  /// 文件名
  final String name;

  /// 文件路径
  final String path;

  /// 文件类型 (image/video)
  final String fileType;

  ClassifierFile({
    required this.name,
    required this.path,
    required this.fileType,
  });

  factory ClassifierFile.fromJson(Map<String, dynamic> json) {
    return ClassifierFile(
      name: json['name'] ?? '',
      path: json['path'] ?? '',
      fileType: json['file_type'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'path': path,
      'file_type': fileType,
    };
  }

  /// 判断是否为图片
  bool get isImage => fileType == 'image';

  /// 判断是否为视频
  bool get isVideo => fileType == 'video';

  /// 获取文件扩展名
  String get extension {
    final lastDot = name.lastIndexOf('.');
    if (lastDot == -1) return '';
    return name.substring(lastDot);
  }

  /// 获取不含扩展名的文件名
  String get nameWithoutExtension {
    final lastDot = name.lastIndexOf('.');
    if (lastDot == -1) return name;
    return name.substring(0, lastDot);
  }

  /// 判断是否为 GIF
  bool get isGif => extension.toLowerCase() == '.gif';
}
