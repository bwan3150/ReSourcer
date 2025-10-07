import 'package:flutter/foundation.dart';
import '../models/server.dart';
import '../services/storage_service.dart';
import '../services/api_service.dart';

/// 认证状态管理
class AuthProvider with ChangeNotifier {
  Server? _currentServer;
  ApiService? _apiService;
  bool _isLoggedIn = false;

  bool get isLoggedIn => _isLoggedIn;
  Server? get currentServer => _currentServer;
  ApiService? get apiService => _apiService;

  /// 初始化，检查是否已登录
  Future<void> initialize() async {
    final storage = await StorageService.getInstance();
    _currentServer = storage.getCurrentServer();
    _isLoggedIn = _currentServer != null;

    if (_isLoggedIn && _currentServer != null) {
      // 检查服务器健康状态和 API key 有效性
      final healthOk = await ApiService.checkHealth(_currentServer!.baseUrl);
      if (!healthOk) {
        print('服务器未运行，自动登出');
        await logout();
        return;
      }

      final authOk = await ApiService.checkAuth(
        _currentServer!.baseUrl,
        _currentServer!.apiKey,
      );
      if (!authOk) {
        print('API Key 无效，自动登出');
        await logout();
        return;
      }

      // 创建 API 服务
      _apiService = ApiService(_currentServer!);
    }

    notifyListeners();
  }

  /// 切换到指定服务器（登录）
  Future<bool> switchToServer(Server server) async {
    try {
      final storage = await StorageService.getInstance();
      await storage.setCurrentServer(server.id);

      _currentServer = server;
      _apiService = ApiService(server);
      _isLoggedIn = true;

      notifyListeners();
      return true;
    } catch (e) {
      print('切换服务器失败: $e');
      return false;
    }
  }

  /// 登出
  Future<void> logout() async {
    final storage = await StorageService.getInstance();

    // 只清除当前服务器，不删除服务器列表
    if (_currentServer != null) {
      await storage.setCurrentServer(''); // 清空当前服务器ID
    }

    _currentServer = null;
    _apiService = null;
    _isLoggedIn = false;

    notifyListeners();
  }
}
