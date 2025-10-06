import 'package:shared_preferences/shared_preferences.dart';
import '../utils/constants.dart';

/// 本地存储服务
class StorageService {
  static StorageService? _instance;
  late SharedPreferences _prefs;

  StorageService._();

  static Future<StorageService> getInstance() async {
    if (_instance == null) {
      _instance = StorageService._();
      _instance!._prefs = await SharedPreferences.getInstance();
    }
    return _instance!;
  }

  /// 保存 API Key
  Future<bool> saveApiKey(String apiKey) async {
    return await _prefs.setString(Constants.apiKeyKey, apiKey);
  }

  /// 获取 API Key
  String? getApiKey() {
    return _prefs.getString(Constants.apiKeyKey);
  }

  /// 保存后端服务地址
  Future<bool> saveBaseUrl(String baseUrl) async {
    return await _prefs.setString(Constants.baseUrlKey, baseUrl);
  }

  /// 获取后端服务地址
  String? getBaseUrl() {
    return _prefs.getString(Constants.baseUrlKey);
  }

  /// 检查是否已登录（有 API Key 和 BaseUrl）
  bool isLoggedIn() {
    final apiKey = getApiKey();
    final baseUrl = getBaseUrl();
    return apiKey != null && apiKey.isNotEmpty &&
           baseUrl != null && baseUrl.isNotEmpty;
  }

  /// 清除登录信息
  Future<bool> clearAuth() async {
    await _prefs.remove(Constants.apiKeyKey);
    await _prefs.remove(Constants.baseUrlKey);
    return true;
  }
}
