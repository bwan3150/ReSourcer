/// 分类文件夹模型
class ClassifierCategory {
  /// 文件夹名称
  final String name;

  /// 是否隐藏
  final bool hidden;

  ClassifierCategory({
    required this.name,
    required this.hidden,
  });

  factory ClassifierCategory.fromJson(Map<String, dynamic> json) {
    return ClassifierCategory(
      name: json['name'] as String,
      hidden: json['hidden'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'hidden': hidden,
    };
  }
}
