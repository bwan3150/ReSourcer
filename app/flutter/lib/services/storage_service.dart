import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/server.dart';

/// 本地存储服务 - 多服务器管理
class StorageService {
  static StorageService? _instance;
  late SharedPreferences _prefs;

  static const String _serversKey = 'servers';
  static const String _currentServerIdKey = 'current_server_id';

  StorageService._();

  static Future<StorageService> getInstance() async {
    if (_instance == null) {
      _instance = StorageService._();
      _instance!._prefs = await SharedPreferences.getInstance();
    }
    return _instance!;
  }

  /// 获取所有服务器
  List<Server> getServers() {
    final serversJson = _prefs.getString(_serversKey);
    if (serversJson == null || serversJson.isEmpty) {
      return [];
    }

    try {
      final List<dynamic> decoded = jsonDecode(serversJson);
      return decoded.map((json) => Server.fromJson(json)).toList();
    } catch (e) {
      print('解析服务器列表失败: $e');
      return [];
    }
  }

  /// 保存服务器列表
  Future<bool> saveServers(List<Server> servers) async {
    final encoded = jsonEncode(servers.map((s) => s.toJson()).toList());
    return await _prefs.setString(_serversKey, encoded);
  }

  /// 添加服务器
  Future<bool> addServer(Server server) async {
    final servers = getServers();
    servers.add(server);
    return await saveServers(servers);
  }

  /// 更新服务器
  Future<bool> updateServer(Server server) async {
    final servers = getServers();
    final index = servers.indexWhere((s) => s.id == server.id);
    if (index != -1) {
      servers[index] = server;
      return await saveServers(servers);
    }
    return false;
  }

  /// 删除服务器
  Future<bool> deleteServer(String serverId) async {
    final servers = getServers();
    servers.removeWhere((s) => s.id == serverId);

    // 如果删除的是当前服务器，清除当前服务器ID
    if (getCurrentServerId() == serverId) {
      await _prefs.remove(_currentServerIdKey);
    }

    return await saveServers(servers);
  }

  /// 获取当前服务器ID
  String? getCurrentServerId() {
    return _prefs.getString(_currentServerIdKey);
  }

  /// 设置当前服务器
  Future<bool> setCurrentServer(String serverId) async {
    return await _prefs.setString(_currentServerIdKey, serverId);
  }

  /// 获取当前服务器
  Server? getCurrentServer() {
    final serverId = getCurrentServerId();
    if (serverId == null) return null;

    try {
      return getServers().firstWhere((s) => s.id == serverId);
    } catch (e) {
      return null;
    }
  }

  /// 检查是否已登录（有当前服务器）
  bool isLoggedIn() {
    return getCurrentServer() != null;
  }

  /// 清除所有数据
  Future<bool> clearAll() async {
    await _prefs.remove(_serversKey);
    await _prefs.remove(_currentServerIdKey);
    return true;
  }
}
