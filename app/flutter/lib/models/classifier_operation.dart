import 'classifier_file.dart';

/// 分类操作历史记录
class ClassifierOperation {
  /// 原文件信息
  final ClassifierFile file;

  /// 原文件在列表中的索引
  final int fileIndex;

  /// 分类到的文件夹名称
  final String category;

  /// 原始文件名（不含扩展名）
  final String originalName;

  /// 移动后的完整路径
  final String newPath;

  /// 操作时间戳
  final DateTime timestamp;

  ClassifierOperation({
    required this.file,
    required this.fileIndex,
    required this.category,
    required this.originalName,
    required this.newPath,
    required this.timestamp,
  });
}
