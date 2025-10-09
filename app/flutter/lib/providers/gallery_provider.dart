import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
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

  /// 刷新画廊（保持当前文件夹）
  Future<void> refresh(ApiService apiService) async {
    // 清除图片缓存，确保重新加载图片（特别是服务器地址变更后）
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();

    _isLoading = true;
    notifyListeners();

    try {
      // 刷新文件夹列表
      final data = await apiService.getGalleryFolders();
      _folders = data.map((json) => GalleryFolder.fromJson(json)).toList();

      // 如果当前有选中的文件夹，刷新当前文件夹的内容
      if (_currentFolder != null) {
        // 找到更新后的当前文件夹对象
        final updatedFolder = _folders.firstWhere(
          (f) => f.path == _currentFolder!.path,
          orElse: () => _folders.isNotEmpty ? _folders[0] : _currentFolder!,
        );
        await selectFolder(apiService, updatedFolder);
      } else if (_folders.isNotEmpty) {
        // 如果没有选中文件夹，选择第一个
        await selectFolder(apiService, _folders[0]);
      }

      _error = null;
    } catch (e) {
      _error = '刷新失败: $e';
    }

    _isLoading = false;
    notifyListeners();
  }
}
