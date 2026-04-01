import 'package:flutter/foundation.dart';
import '../models/server.dart';
import '../services/storage_service.dart';
import '../services/api_service.dart';

/// 服务器管理 Provider
class ServerProvider with ChangeNotifier {
  List<Server> _servers = [];
  Map<String, ServerStatus> _serverStatuses = {};
  Server? _currentServer;

  List<Server> get servers => _servers;
  Map<String, ServerStatus> get serverStatuses => _serverStatuses;
  Server? get currentServer => _currentServer;

  /// 初始化，加载所有服务器
  Future<void> initialize() async {
    final storage = await StorageService.getInstance();
    _servers = storage.getServers();
    _currentServer = storage.getCurrentServer();

    // 检查所有服务器状态
    await checkAllServers();

    notifyListeners();
  }

  /// 检查所有服务器状态
  Future<void> checkAllServers() async {
    for (var server in _servers) {
      _serverStatuses[server.id] = ServerStatus.checking;
    }
    notifyListeners();

    // 并发检查所有服务器
    await Future.wait(_servers.map((server) async {
      final status = await _checkServerStatus(server);
      _serverStatuses[server.id] = status;
    }));

    notifyListeners();
  }

  /// 检查单个服务器状态（公开方法）
  Future<void> checkServerStatus(Server server) async {
    _serverStatuses[server.id] = ServerStatus.checking;
    notifyListeners();

    final status = await _checkServerStatus(server);
    _serverStatuses[server.id] = status;
    notifyListeners();
  }

  /// 检查单个服务器状态（内部方法）
  Future<ServerStatus> _checkServerStatus(Server server) async {
    // 1. 检查健康状态
    final healthOk = await ApiService.checkHealth(server.baseUrl);
    if (!healthOk) {
      return ServerStatus.offline;
    }

    // 2. 检查认证
    final authOk = await ApiService.checkAuth(server.baseUrl, server.apiKey);
    if (!authOk) {
      return ServerStatus.authError;
    }

    return ServerStatus.online;
  }

  /// 添加服务器
  Future<bool> addServer(Server server) async {
    try {
      final storage = await StorageService.getInstance();
      await storage.addServer(server);

      _servers.add(server);
      _serverStatuses[server.id] = ServerStatus.checking;
      notifyListeners();

      // 异步检查服务器状态
      final status = await _checkServerStatus(server);
      _serverStatuses[server.id] = status;
      notifyListeners();

      return true;
    } catch (e) {
      print('添加服务器失败: $e');
      return false;
    }
  }

  /// 更新服务器
  Future<bool> updateServer(Server server) async {
    try {
      final storage = await StorageService.getInstance();
      await storage.updateServer(server);

      final index = _servers.indexWhere((s) => s.id == server.id);
      if (index != -1) {
        _servers[index] = server;
      }

      // 如果是当前服务器，也更新
      if (_currentServer?.id == server.id) {
        _currentServer = server;
      }

      notifyListeners();

      // 重新检查该服务器状态
      final status = await _checkServerStatus(server);
      _serverStatuses[server.id] = status;
      notifyListeners();

      return true;
    } catch (e) {
      print('更新服务器失败: $e');
      return false;
    }
  }

  /// 重命名服务器
  Future<bool> renameServer(String serverId, String newName) async {
    try {
      final server = _servers.firstWhere((s) => s.id == serverId);
      final updatedServer = Server(
        id: server.id,
        name: newName,
        baseUrl: server.baseUrl,
        apiKey: server.apiKey,
        addedAt: server.addedAt,
      );

      return await updateServer(updatedServer);
    } catch (e) {
      print('重命名服务器失败: $e');
      return false;
    }
  }

  /// 删除服务器
  Future<bool> deleteServer(String serverId) async {
    try {
      final storage = await StorageService.getInstance();
      await storage.deleteServer(serverId);

      _servers.removeWhere((s) => s.id == serverId);
      _serverStatuses.remove(serverId);

      // 如果删除的是当前服务器，清除当前服务器
      if (_currentServer?.id == serverId) {
        _currentServer = null;
      }

      notifyListeners();
      return true;
    } catch (e) {
      print('删除服务器失败: $e');
      return false;
    }
  }

  /// 切换到指定服务器
  Future<bool> switchToServer(String serverId) async {
    try {
      final storage = await StorageService.getInstance();
      await storage.setCurrentServer(serverId);

      _currentServer = _servers.firstWhere((s) => s.id == serverId);
      notifyListeners();

      return true;
    } catch (e) {
      print('切换服务器失败: $e');
      return false;
    }
  }

  /// 获取服务器状态
  ServerStatus getServerStatus(String serverId) {
    return _serverStatuses[serverId] ?? ServerStatus.checking;
  }

  /// 获取在线服务器数量
  int get onlineServerCount {
    return _serverStatuses.values.where((s) => s == ServerStatus.online).length;
  }
}
