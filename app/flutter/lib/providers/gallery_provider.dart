import 'package:flutter/foundation.dart';
import '../models/gallery_file.dart';
import '../models/gallery_folder.dart';
import '../services/api_service.dart';

/// 画廊状态管理
class GalleryProvider with ChangeNotifier {
  List<GalleryFolder> _folders = [];
  List<GalleryFile> _files = [];
  GalleryFolder? _currentFolder;
  bool _isLoading = false;
  String? _error;

  List<GalleryFolder> get folders => _folders;
  List<GalleryFile> get files => _files;
  GalleryFolder? get currentFolder => _currentFolder;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// 加载文件夹列表
  Future<void> loadFolders(ApiService apiService) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final data = await apiService.getGalleryFolders();
      _folders = data.map((json) => GalleryFolder.fromJson(json)).toList();

      // 默认选择第一个文件夹
      if (_folders.isNotEmpty) {
        await selectFolder(apiService, _folders[0]);
      }

      _error = null;
    } catch (e) {
      _error = '加载文件夹失败: $e';
      _folders = [];
    }

    _isLoading = false;
    notifyListeners();
  }

  /// 选择文件夹并加载文件
  Future<void> selectFolder(ApiService apiService, GalleryFolder folder) async {
    _currentFolder = folder;
    _isLoading = true;
    notifyListeners();

    try {
      final data = await apiService.getGalleryFiles(folder.path);
      _files = data.map((json) => GalleryFile.fromJson(json)).toList();
      _error = null;
    } catch (e) {
      _error = '加载文件失败: $e';
      _files = [];
    }

    _isLoading = false;
    notifyListeners();
  }

  /// 刷新画廊
  Future<void> refresh(ApiService apiService) async {
    await loadFolders(apiService);
  }
}
