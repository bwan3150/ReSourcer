import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/download_task.dart';
import '../services/api_service.dart';

/// 下载器Provider - 管理下载任务和文件夹
class DownloaderProvider extends ChangeNotifier {
  final ApiService apiService;

  List<DownloadTask> _tasks = [];
  List<DownloadFolder> _folders = [];
  String _selectedFolder = ''; // 空字符串代表源文件夹
  bool _isLoading = false;
  String? _error;
  Timer? _pollingTimer;

  DownloaderProvider(this.apiService) {
    _startPolling();
  }

  // Getters
  List<DownloadTask> get tasks => _tasks;
  List<DownloadFolder> get folders => _folders;
  String get selectedFolder => _selectedFolder;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// 活跃任务数量
  int get activeTaskCount => _tasks.where((t) => t.isActive).length;

  /// 已完成任务数量
  int get completedTaskCount => _tasks.where((t) => t.isCompleted).length;

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  /// 加载文件夹列表
  Future<void> loadFolders() async {
    try {
      _error = null;

      // 先获取配置以获得source_folder
      final config = await apiService.downloader.getConfig();
      final sourceFolder = config['source_folder'] as String?;

      // 使用source_folder参数获取文件夹列表
      final response = await apiService.downloader.getFolders(
        sourceFolder: sourceFolder,
      );

      _folders = (response as List)
          .map((json) => DownloadFolder.fromJson(json))
          .where((folder) => !folder.isHidden)
          .toList();
      notifyListeners();
    } catch (e) {
      _error = '加载文件夹失败: $e';
      debugPrint('加载文件夹失败: $e');
      notifyListeners();
    }
  }

  /// 选择文件夹
  void selectFolder(String folderName) {
    _selectedFolder = folderName;
    notifyListeners();
  }

  /// 创建新文件夹
  Future<bool> createFolder(String folderName) async {
    try {
      await apiService.downloader.createFolder(folderName);
      await loadFolders();
      selectFolder(folderName);
      return true;
    } catch (e) {
      _error = '创建文件夹失败: $e';
      notifyListeners();
      return false;
    }
  }

  /// 检测URL
  Future<UrlDetectResult?> detectUrl(String url) async {
    try {
      final response = await apiService.downloader.detectUrl(url);
      return UrlDetectResult.fromJson(response);
    } catch (e) {
      debugPrint('URL检测失败: $e');
      return null;
    }
  }

  /// 创建下载任务
  Future<bool> createTask({
    required String url,
    required String downloader,
    String? saveFolder,
  }) async {
    try {
      _error = null;
      debugPrint('开始创建下载任务: url=$url, downloader=$downloader, saveFolder=$saveFolder');

      await apiService.downloader.createTask(
        url: url,
        downloader: downloader,
        saveFolder: saveFolder ?? '',
        format: 'best',
      );

      debugPrint('下载任务创建成功，开始刷新任务列表');

      // 立即刷新任务列表
      await loadTasks();
      return true;
    } catch (e) {
      _error = '创建任务失败: $e';
      debugPrint('创建任务失败: $e');
      notifyListeners();
      return false;
    }
  }

  /// 加载任务列表
  Future<void> loadTasks() async {
    try {
      final response = await apiService.downloader.getTasks();
      final tasksData = response['tasks'] as List? ?? [];
      _tasks = tasksData.map((json) => DownloadTask.fromJson(json)).toList();

      // 按创建时间倒序排列（最新的在前）
      _tasks.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      notifyListeners();
    } catch (e) {
      debugPrint('加载任务失败: $e');
    }
  }

  /// 取消任务
  Future<bool> cancelTask(String taskId) async {
    try {
      await apiService.downloader.deleteTask(taskId);
      await loadTasks();
      return true;
    } catch (e) {
      _error = '取消任务失败: $e';
      notifyListeners();
      return false;
    }
  }

  /// 删除任务
  Future<bool> deleteTask(String taskId) async {
    try {
      await apiService.downloader.deleteTask(taskId);
      await loadTasks();
      return true;
    } catch (e) {
      _error = '删除任务失败: $e';
      notifyListeners();
      return false;
    }
  }

  /// 清空历史记录（已完成/失败/取消的任务）
  Future<bool> clearHistory() async {
    try {
      await apiService.downloader.clearHistory();
      await loadTasks();
      return true;
    } catch (e) {
      _error = '清空历史失败: $e';
      notifyListeners();
      return false;
    }
  }

  /// 获取文件URL（用于预览）
  String getFileUrl(String filePath) {
    return apiService.downloader.getFileUrl(filePath);
  }

  /// 开始轮询任务状态
  void _startPolling() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      // 只有在有活跃任务时才轮询
      if (activeTaskCount > 0) {
        loadTasks();
      }
    });
  }

  /// 手动刷新
  Future<void> refresh() async {
    _isLoading = true;
    notifyListeners();

    await Future.wait([
      loadFolders(),
      loadTasks(),
    ]);

    _isLoading = false;
    notifyListeners();
  }

  /// 初始化（加载初始数据）
  Future<void> initialize() async {
    await refresh();
  }
}
