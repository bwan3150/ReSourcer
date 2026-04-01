import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/server.dart';

/// 下载器 API 服务
class DownloaderApiService {
  final Server server;

  DownloaderApiService(this.server);

  Map<String, String> get _headers => {'Cookie': 'api_key=${server.apiKey}'};

  /// 获取配置信息
  Future<Map<String, dynamic>> getConfig() async {
    final response = await http.get(
      Uri.parse('${server.baseUrl}/api/config/download'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('获取配置失败');
  }

  /// 获取文件夹列表
  /// 如果不传source_folder参数，后端会从配置文件读取
  Future<List<dynamic>> getFolders({String? sourceFolder}) async {
    var url = '${server.baseUrl}/api/folder/list';
    if (sourceFolder != null && sourceFolder.isNotEmpty) {
      url += '?source_folder=${Uri.encodeComponent(sourceFolder)}';
    }

    final response = await http.get(
      Uri.parse(url),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List;
    }
    throw Exception('获取文件夹列表失败');
  }

  /// 创建新文件夹
  Future<void> createFolder(String folderName) async {
    final response = await http.post(
      Uri.parse('${server.baseUrl}/api/folder/create'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({'folder_name': folderName}),
    );

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body);
      throw Exception(error['error'] ?? '创建文件夹失败');
    }
  }

  /// 检测URL
  Future<Map<String, dynamic>> detectUrl(String url) async {
    final response = await http.post(
      Uri.parse('${server.baseUrl}/api/transfer/download/detect'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({'url': url}),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('URL检测失败');
  }

  /// 创建下载任务
  Future<Map<String, dynamic>> createTask({
    required String url,
    required String downloader,
    required String saveFolder,
    String format = 'best',
  }) async {
    final response = await http.post(
      Uri.parse('${server.baseUrl}/api/transfer/download/task'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({
        'url': url,
        'downloader': downloader,
        'save_folder': saveFolder,
        'format': format,
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['error'] ?? '创建任务失败');
    }
  }

  /// 获取任务列表
  Future<Map<String, dynamic>> getTasks() async {
    final response = await http.get(
      Uri.parse('${server.baseUrl}/api/transfer/download/tasks'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('获取任务列表失败');
  }

  /// 删除任务（取消/删除）
  Future<void> deleteTask(String taskId) async {
    final response = await http.delete(
      Uri.parse('${server.baseUrl}/api/transfer/download/task/$taskId'),
      headers: _headers,
    );

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body);
      throw Exception(error['error'] ?? '删除任务失败');
    }
  }

  /// 清空历史记录
  Future<void> clearHistory() async {
    final response = await http.delete(
      Uri.parse('${server.baseUrl}/api/transfer/download/history'),
      headers: _headers,
    );

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body);
      throw Exception(error['error'] ?? '清空历史失败');
    }
  }

  /// 获取文件URL（用于预览）
  String getFileUrl(String filePath) {
    final encodedPath = Uri.encodeComponent(filePath);
    return '${server.baseUrl}/api/preview/content/$encodedPath';
  }

  /// 上传认证信息
  Future<void> uploadCredentials(String platform, String content) async {
    final response = await http.post(
      Uri.parse('${server.baseUrl}/api/config/credentials/$platform'),
      headers: {..._headers, 'Content-Type': 'text/plain'},
      body: content,
    );

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body);
      throw Exception(error['error'] ?? '上传认证信息失败');
    }
  }

  /// 删除认证信息
  Future<void> deleteCredentials(String platform) async {
    final response = await http.delete(
      Uri.parse('${server.baseUrl}/api/config/credentials/$platform'),
      headers: _headers,
    );

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body);
      throw Exception(error['error'] ?? '删除认证信息失败');
    }
  }
}
