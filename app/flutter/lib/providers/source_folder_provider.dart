import 'package:flutter/foundation.dart';
import '../models/source_folder.dart';
import '../services/api_service.dart';

/// 源文件夹管理 Provider
class SourceFolderProvider with ChangeNotifier {
  List<SourceFolder> _sourceFolders = [];
  bool _isLoading = false;

  List<SourceFolder> get sourceFolders => _sourceFolders;
  bool get isLoading => _isLoading;

  /// 当前活跃的源文件夹
  SourceFolder? get currentSourceFolder {
    try {
      return _sourceFolders.firstWhere((folder) => folder.isActive);
    } catch (e) {
      return null;
    }
  }

  /// 备用源文件夹列表
  List<SourceFolder> get backupSourceFolders {
    return _sourceFolders.where((folder) => !folder.isActive).toList();
  }

  /// 从服务器加载源文件夹列表
  Future<void> loadSourceFolders(ApiService apiService) async {
    _isLoading = true;
    notifyListeners();

    try {
      // 调用 API 获取源文件夹配置
      final response = await apiService.getSettingsState();

      if (response['source_folder'] != null && response['source_folder'].toString().isNotEmpty) {
        final currentFolder = SourceFolder(
          path: response['source_folder'],
          isActive: true,
          lastAccessed: DateTime.now(),
        );

        _sourceFolders = [currentFolder];

        // 添加备用源文件夹
        if (response['backup_source_folders'] != null) {
          final backups = (response['backup_source_folders'] as List)
              .map((path) => SourceFolder(
                    path: path,
                    isActive: false,
                  ))
              .toList();
          _sourceFolders.addAll(backups);
        }
      } else {
        _sourceFolders = [];
      }
    } catch (e) {
      print('加载源文件夹列表失败: $e');
      _sourceFolders = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 切换到指定源文件夹
  Future<bool> switchToFolder(ApiService apiService, String folderPath) async {
    try {
      final response = await apiService.switchSourceFolder(folderPath);

      if (response['status'] == 'success') {
        // 重新加载列表
        await loadSourceFolders(apiService);
        return true;
      }
      return false;
    } catch (e) {
      print('切换源文件夹失败: $e');
      return false;
    }
  }

  /// 添加新源文件夹
  Future<bool> addSourceFolder(ApiService apiService, String folderPath) async {
    try {
      final response = await apiService.addSourceFolder(folderPath);

      if (response['status'] == 'success') {
        // 重新加载列表
        await loadSourceFolders(apiService);
        return true;
      }
      return false;
    } catch (e) {
      print('添加源文件夹失败: $e');
      return false;
    }
  }

  /// 移除源文件夹
  Future<bool> removeSourceFolder(ApiService apiService, String folderPath) async {
    try {
      final response = await apiService.removeSourceFolder(folderPath);

      if (response['status'] == 'success') {
        // 重新加载列表
        await loadSourceFolders(apiService);
        return true;
      }
      return false;
    } catch (e) {
      print('移除源文件夹失败: $e');
      return false;
    }
  }

  /// 获取源文件夹数量统计
  int get totalCount => _sourceFolders.length;

  int get activeCount => _sourceFolders.where((f) => f.isActive).length;

  int get backupCount => _sourceFolders.where((f) => !f.isActive).length;
}
