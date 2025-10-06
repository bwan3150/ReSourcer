import 'package:flutter/foundation.dart';
import '../models/upload_task.dart';
import '../services/api_service.dart';

/// 上传任务状态管理
class UploadProvider with ChangeNotifier {
  List<UploadTask> _tasks = [];
  bool _isLoading = false;

  List<UploadTask> get tasks => _tasks;
  bool get isLoading => _isLoading;

  /// 加载上传任务列表
  Future<void> loadTasks(ApiService apiService) async {
    _isLoading = true;
    notifyListeners();

    try {
      final data = await apiService.getUploadTasks();
      _tasks = data.map((json) => UploadTask.fromJson(json)).toList();
    } catch (e) {
      print('加载上传任务失败: $e');
      _tasks = [];
    }

    _isLoading = false;
    notifyListeners();
  }

  /// 上传多个文件
  Future<bool> uploadFiles(ApiService apiService, List<String> filePaths, String targetFolder) async {
    try {
      final success = await apiService.uploadFiles(filePaths, targetFolder);
      if (success) {
        // 重新加载任务列表
        await loadTasks(apiService);
        return true;
      }
      return false;
    } catch (e) {
      print('上传文件失败: $e');
      return false;
    }
  }

  /// 删除任务
  Future<bool> deleteTask(ApiService apiService, String taskId) async {
    try {
      final success = await apiService.deleteUploadTask(taskId);
      if (success) {
        await loadTasks(apiService);
      }
      return success;
    } catch (e) {
      print('删除任务失败: $e');
      return false;
    }
  }

  /// 刷新任务列表
  Future<void> refresh(ApiService apiService) async {
    await loadTasks(apiService);
  }
}
