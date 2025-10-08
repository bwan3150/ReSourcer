/// 源文件夹模型
class SourceFolder {
  final String path;
  final bool isActive;  // 是否为当前活跃源
  final DateTime? lastAccessed;

  SourceFolder({
    required this.path,
    required this.isActive,
    this.lastAccessed,
  });

  factory SourceFolder.fromJson(Map<String, dynamic> json) {
    return SourceFolder(
      path: json['path'],
      isActive: json['isActive'] ?? false,
      lastAccessed: json['lastAccessed'] != null
          ? DateTime.parse(json['lastAccessed'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'path': path,
      'isActive': isActive,
      'lastAccessed': lastAccessed?.toIso8601String(),
    };
  }

  SourceFolder copyWith({
    String? path,
    bool? isActive,
    DateTime? lastAccessed,
  }) {
    return SourceFolder(
      path: path ?? this.path,
      isActive: isActive ?? this.isActive,
      lastAccessed: lastAccessed ?? this.lastAccessed,
    );
  }

  /// 获取文件夹显示名称（路径最后一部分）
  String get displayName {
    final segments = path.split('/');
    return segments.last.isEmpty ? segments[segments.length - 2] : segments.last;
  }
}
