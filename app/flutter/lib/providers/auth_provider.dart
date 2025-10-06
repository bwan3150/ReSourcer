import 'package:flutter/foundation.dart';
import '../services/storage_service.dart';
import '../services/api_service.dart';

/// 认证状态管理
class AuthProvider with ChangeNotifier {
  String? _apiKey;
  String? _baseUrl;
  bool _isLoggedIn = false;
  ApiService? _apiService;

  bool get isLoggedIn => _isLoggedIn;
  String? get apiKey => _apiKey;
  String? get baseUrl => _baseUrl;
  ApiService? get apiService => _apiService;

  /// 初始化，检查是否已登录
  Future<void> initialize() async {
    final storage = await StorageService.getInstance();
    _apiKey = storage.getApiKey();
    _baseUrl = storage.getBaseUrl();
    _isLoggedIn = storage.isLoggedIn();

    if (_isLoggedIn) {
      _apiService = await ApiService.create();
    }

    notifyListeners();
  }

  /// 登录
  Future<bool> login(String baseUrl, String apiKey) async {
    try {
      // 验证 API Key
      final apiService = await ApiService.create();
      final isValid = await apiService.verifyApiKey(baseUrl, apiKey);

      if (!isValid) {
        return false;
      }

      // 保存认证信息
      final storage = await StorageService.getInstance();
      await storage.saveBaseUrl(baseUrl);
      await storage.saveApiKey(apiKey);

      _baseUrl = baseUrl;
      _apiKey = apiKey;
      _isLoggedIn = true;
      _apiService = await ApiService.create();

      notifyListeners();
      return true;
    } catch (e) {
      print('登录失败: $e');
      return false;
    }
  }

  /// 登出
  Future<void> logout() async {
    final storage = await StorageService.getInstance();
    await storage.clearAuth();

    _apiKey = null;
    _baseUrl = null;
    _isLoggedIn = false;
    _apiService = null;

    notifyListeners();
  }
}
