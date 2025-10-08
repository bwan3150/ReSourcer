import 'package:flutter/foundation.dart';
import '../models/classifier_file.dart';
import '../models/classifier_category.dart';
import '../models/classifier_operation.dart';
import '../services/api_service.dart';

/// 分类器状态管理
class ClassifierProvider with ChangeNotifier {
  // 状态数据
  String? _sourceFolder;
  List<ClassifierFile> _files = [];
  List<ClassifierCategory> _categories = [];
  List<ClassifierOperation> _operationHistory = [];
  int _currentIndex = 0;
  int _processedCount = 0;
  bool _isLoading = false;
  String? _error;
  bool _useThumbnail = true; // 是否使用缩略图（默认开启）

  // Getters
  String? get sourceFolder => _sourceFolder;
  List<ClassifierFile> get files => _files;
  List<ClassifierCategory> get categories => _categories;
  List<ClassifierCategory> get visibleCategories =>
      _categories.where((c) => !c.hidden).toList();
  List<ClassifierOperation> get operationHistory => _operationHistory;
  int get currentIndex => _currentIndex;
  int get processedCount => _processedCount;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get useThumbnail => _useThumbnail;

  /// 当前文件
  ClassifierFile? get currentFile {
    if (_currentIndex >= 0 && _currentIndex < _files.length) {
      return _files[_currentIndex];
    }
    return null;
  }

  /// 是否还有待分类文件
  bool get hasFiles => _files.isNotEmpty;

  /// 是否已完成所有分类
  bool get isCompleted => _files.isEmpty && _processedCount > 0;

  /// 总文件数（已处理 + 待处理）
  int get totalFileCount => _processedCount + _files.length;

  /// 进度百分比
  double get progressPercentage {
    final total = totalFileCount;
    if (total == 0) return 0.0;
    return _processedCount / total;
  }

  /// 是否可以撤销
  bool get canUndo => _operationHistory.isNotEmpty;

  /// 最近的操作记录（最多3条）
  List<ClassifierOperation> get recentOperations {
    if (_operationHistory.length <= 3) {
      return _operationHistory;
    }
    return _operationHistory.sublist(_operationHistory.length - 3);
  }

  /// 切换缩略图/原图模式
  void toggleThumbnail() {
    _useThumbnail = !_useThumbnail;
    notifyListeners();
  }

  /// 初始化 - 加载状态和文件列表
  Future<void> initialize(ApiService apiService) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // 加载状态
      final state = await apiService.classifier.getState();
      _sourceFolder = state['source_folder'] as String?;

      if (_sourceFolder == null || _sourceFolder!.isEmpty) {
        _error = '请先在设置中配置源文件夹';
        _isLoading = false;
        notifyListeners();
        return;
      }

      // 加载分类文件夹
      await loadCategories(apiService);

      if (visibleCategories.isEmpty) {
        _error = '请先在设置中配置分类文件夹';
        _isLoading = false;
        notifyListeners();
        return;
      }

      // 加载文件列表
      await loadFiles(apiService);

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = '初始化失败: $e';
      _isLoading = false;
      notifyListeners();
      print('初始化分类器失败: $e');
    }
  }

  /// 加载分类文件夹列表
  Future<void> loadCategories(ApiService apiService) async {
    if (_sourceFolder == null) return;

    try {
      final data = await apiService.classifier.getFolders(_sourceFolder!);
      _categories = data.map((json) => ClassifierCategory.fromJson(json)).toList();
      notifyListeners();
    } catch (e) {
      print('加载分类文件夹失败: $e');
      throw e;
    }
  }

  /// 加载待分类文件列表
  Future<void> loadFiles(ApiService apiService) async {
    try {
      final data = await apiService.classifier.getFiles();
      _files = data.map((json) => ClassifierFile.fromJson(json)).toList();
      _currentIndex = 0;
      _processedCount = 0;
      _operationHistory.clear();
      notifyListeners();
    } catch (e) {
      print('加载文件列表失败: $e');
      throw e;
    }
  }

  /// 刷新数据
  Future<void> refresh(ApiService apiService) async {
    await initialize(apiService);
  }

  /// 移动当前文件到指定分类
  Future<bool> moveToCategory(
    ApiService apiService,
    String category, {
    String? newName,
  }) async {
    if (currentFile == null) return false;

    try {
      final file = currentFile!;
      final result = await apiService.classifier.moveFile(
        filePath: file.path,
        category: category,
        newName: newName,
      );

      // 记录操作历史
      final operation = ClassifierOperation(
        file: file,
        fileIndex: _currentIndex,
        category: category,
        originalName: file.nameWithoutExtension,
        newPath: result['moved_to'] as String,
        timestamp: DateTime.now(),
      );

      _operationHistory.add(operation);

      // 限制历史记录数量（最多20条）
      if (_operationHistory.length > 20) {
        _operationHistory.removeAt(0);
      }

      // 从列表中移除已处理的文件
      _files.removeAt(_currentIndex);
      _processedCount++;

      // 如果当前索引超出范围，保持在最后一个有效索引
      if (_currentIndex >= _files.length && _files.isNotEmpty) {
        _currentIndex = _files.length - 1;
      }

      notifyListeners();
      return true;
    } catch (e) {
      print('移动文件失败: $e');
      _error = '移动文件失败: $e';
      notifyListeners();
      return false;
    }
  }

  /// 撤销上一步操作
  Future<bool> undo(ApiService apiService) async {
    if (_operationHistory.isEmpty) return false;

    try {
      final lastOp = _operationHistory.last;

      // 移回原位置（category 为空表示移回源文件夹根目录）
      await apiService.classifier.moveFile(
        filePath: lastOp.newPath,
        category: '',
        newName: lastOp.originalName,
      );

      // 恢复文件到列表
      _files.insert(lastOp.fileIndex, lastOp.file);

      // 调整当前索引
      if (_currentIndex > lastOp.fileIndex) {
        _currentIndex = lastOp.fileIndex;
      }

      _processedCount--;
      _operationHistory.removeLast();

      notifyListeners();
      return true;
    } catch (e) {
      print('撤销操作失败: $e');
      _error = '撤销失败: 文件可能已被手动移动';
      notifyListeners();
      return false;
    }
  }

  /// 快速添加新分类文件夹
  Future<bool> addCategory(ApiService apiService, String categoryName) async {
    try {
      // 检查是否已存在
      if (_categories.any((c) => c.name == categoryName)) {
        _error = '文件夹已存在';
        notifyListeners();
        return false;
      }

      // 创建文件夹
      await apiService.classifier.createFolder(categoryName);

      // 添加到分类列表
      _categories.add(ClassifierCategory(name: categoryName, hidden: false));
      notifyListeners();
      return true;
    } catch (e) {
      print('创建分类文件夹失败: $e');
      _error = '创建文件夹失败: $e';
      notifyListeners();
      return false;
    }
  }

  /// 清除错误信息
  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// 重置状态
  void reset() {
    _sourceFolder = null;
    _files = [];
    _categories = [];
    _operationHistory = [];
    _currentIndex = 0;
    _processedCount = 0;
    _error = null;
    _isLoading = false;
    _useThumbnail = true;
    notifyListeners();
  }
}
