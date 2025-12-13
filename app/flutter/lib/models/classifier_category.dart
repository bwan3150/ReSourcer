/// 分类文件夹模型
class ClassifierCategory {
  /// 文件夹名称
  final String name;

  /// 是否隐藏
  final bool hidden;

  /// 文件数量
  final int fileCount;

  ClassifierCategory({
    required this.name,
    required this.hidden,
    this.fileCount = 0,
  });

  factory ClassifierCategory.fromJson(Map<String, dynamic> json) {
    return ClassifierCategory(
      name: json['name'] as String,
      hidden: json['hidden'] as bool? ?? false,
      fileCount: json['file_count'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'hidden': hidden,
      'file_count': fileCount,
    };
  }

  /// 复制并更新字段
  ClassifierCategory copyWith({
    String? name,
    bool? hidden,
    int? fileCount,
  }) {
    return ClassifierCategory(
      name: name ?? this.name,
      hidden: hidden ?? this.hidden,
      fileCount: fileCount ?? this.fileCount,
    );
  }
}
