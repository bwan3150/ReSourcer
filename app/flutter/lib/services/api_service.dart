import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:dio/dio.dart';
import '../models/server.dart';
import 'classifier_api_service.dart';
import 'downloader_api_service.dart';

/// API 服务 - 主入口，聚合所有子服务
class ApiService {
  final Server server;
  final Dio _dio = Dio();

  // 子服务
  late final ClassifierApiService classifier;
  late final DownloaderApiService downloader;

  ApiService(this.server) {
    // 配置 Dio
    _dio.options.headers['Cookie'] = 'api_key=${server.apiKey}';
    _dio.options.connectTimeout = const Duration(seconds: 10);
    _dio.options.receiveTimeout = const Duration(seconds: 10);

    // 初始化子服务
    classifier = ClassifierApiService(server);
    downloader = DownloaderApiService(server);
  }

  String get baseUrl => server.baseUrl;
  String get apiKey => server.apiKey;

  /// 获取 App 配置（包含 GitHub URL）
  static Future<Map<String, dynamic>?> getAppConfig(String baseUrl) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/app'),
      ).timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      print('获取 App 配置失败: $e');
      return null;
    }
  }

  /// 健康检查 - 检查服务器是否在运行
  static Future<bool> checkHealth(String baseUrl) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/health'),
      ).timeout(const Duration(seconds: 3));

      return response.statusCode == 200;
    } catch (e) {
      print('健康检查失败: $e');
      return false;
    }
  }

  /// 检查 API Key 是否有效
  static Future<bool> checkAuth(String baseUrl, String apiKey) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/auth/check'),
        headers: {'Cookie': 'api_key=$apiKey'},
      ).timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['valid'] == true;
      }
      return false;
    } catch (e) {
      print('认证检查失败: $e');
      return false;
    }
  }

  /// 验证 API Key（用于添加服务器时）
  static Future<bool> verifyApiKey(String baseUrl, String apiKey) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/verify'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'api_key': apiKey}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['valid'] == true;
      }
      return false;
    } catch (e) {
      print('验证 API Key 失败: $e');
      return false;
    }
  }

  /// 获取画廊文件夹列表
  Future<List<Map<String, dynamic>>> getGalleryFolders() async {
    try {
      final response = await http.get(
        Uri.parse('${server.baseUrl}/api/gallery/folders'),
        headers: {'Cookie': 'api_key=${server.apiKey}'},
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        final List<dynamic> folders = data['folders'];
        return folders.cast<Map<String, dynamic>>();
      }
      throw Exception('获取文件夹列表失败');
    } catch (e) {
      print('获取文件夹列表失败: $e');
      throw e;
    }
  }

  /// 获取画廊文件列表
  Future<List<Map<String, dynamic>>> getGalleryFiles(String folderPath) async {
    try {
      final response = await http.get(
        Uri.parse('${server.baseUrl}/api/gallery/files?folder=${Uri.encodeComponent(folderPath)}'),
        headers: {'Cookie': 'api_key=${server.apiKey}'},
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        final List<dynamic> files = data['files'];
        return files.cast<Map<String, dynamic>>();
      }
      throw Exception('获取文件列表失败');
    } catch (e) {
      print('获取文件列表失败: $e');
      throw e;
    }
  }

  /// 上传多个文件
  Future<bool> uploadFiles(List<String> filePaths, String targetFolder) async {
    try {
      final formData = FormData();
      formData.fields.add(MapEntry('target_folder', targetFolder));

      for (var filePath in filePaths) {
        formData.files.add(MapEntry(
          'files',
          await MultipartFile.fromFile(filePath),
        ));
      }

      final response = await _dio.post(
        '${server.baseUrl}/api/uploader/upload',
        data: formData,
      );

      return response.statusCode == 200;
    } catch (e) {
      print('上传文件失败: $e');
      return false;
    }
  }

  /// 获取上传任务列表
  Future<List<Map<String, dynamic>>> getUploadTasks() async {
    try {
      final response = await http.get(
        Uri.parse('${server.baseUrl}/api/uploader/tasks'),
        headers: {'Cookie': 'api_key=${server.apiKey}'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return (data['tasks'] as List<dynamic>).cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      print('获取上传任务失败: $e');
      return [];
    }
  }

  /// 删除上传任务
  Future<bool> deleteUploadTask(String taskId) async {
    try {
      final response = await http.delete(
        Uri.parse('${server.baseUrl}/api/uploader/task/$taskId'),
        headers: {'Cookie': 'api_key=${server.apiKey}'},
      );

      return response.statusCode == 200;
    } catch (e) {
      print('删除上传任务失败: $e');
      return false;
    }
  }

  /// 清除所有已完成/失败的上传任务
  Future<int> clearFinishedUploadTasks() async {
    try {
      final response = await http.post(
        Uri.parse('${server.baseUrl}/api/uploader/tasks/clear'),
        headers: {'Cookie': 'api_key=${server.apiKey}'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['cleared_count'] ?? 0;
      }
      return 0;
    } catch (e) {
      print('清除上传任务失败: $e');
      return 0;
    }
  }

  /// 获取图片缩略图 URL
  String getThumbnailUrl(String filePath) {
    return '${server.baseUrl}/api/gallery/thumbnail?path=${Uri.encodeComponent(filePath)}&size=300';
  }

  /// 获取原图 URL
  String getImageUrl(String filePath) {
    return '${server.baseUrl}/api/classifier/file/${Uri.encodeComponent(filePath)}';
  }

  /// 重命名文件
  Future<Map<String, dynamic>> renameFile(String filePath, String newName) async {
    try {
      final response = await http.post(
        Uri.parse('${server.baseUrl}/api/gallery/rename'),
        headers: {
          'Cookie': 'api_key=${server.apiKey}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'file_path': filePath,
          'new_name': newName,
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      throw Exception('重命名失败');
    } catch (e) {
      print('重命名文件失败: $e');
      throw e;
    }
  }

  /// 移动文件到其他文件夹
  Future<Map<String, dynamic>> moveFile(String filePath, String targetFolder) async {
    try {
      final response = await http.post(
        Uri.parse('${server.baseUrl}/api/gallery/move'),
        headers: {
          'Cookie': 'api_key=${server.apiKey}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'file_path': filePath,
          'target_folder': targetFolder,
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      throw Exception('移动失败');
    } catch (e) {
      print('移动文件失败: $e');
      throw e;
    }
  }

  // ========== 源文件夹管理 API ==========

  /// 获取设置状态（包含源文件夹信息）
  Future<Map<String, dynamic>> getSettingsState() async {
    try {
      final response = await http.get(
        Uri.parse('${server.baseUrl}/api/settings/state'),
        headers: {'Cookie': 'api_key=${server.apiKey}'},
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      throw Exception('获取设置状态失败');
    } catch (e) {
      print('获取设置状态失败: $e');
      throw e;
    }
  }

  /// 切换源文件夹
  Future<Map<String, dynamic>> switchSourceFolder(String folderPath) async {
    try {
      final response = await http.post(
        Uri.parse('${server.baseUrl}/api/settings/sources/switch'),
        headers: {
          'Cookie': 'api_key=${server.apiKey}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'folder_path': folderPath}),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      throw Exception('切换源文件夹失败');
    } catch (e) {
      print('切换源文件夹失败: $e');
      throw e;
    }
  }

  /// 添加源文件夹
  Future<Map<String, dynamic>> addSourceFolder(String folderPath) async {
    try {
      final response = await http.post(
        Uri.parse('${server.baseUrl}/api/settings/sources/add'),
        headers: {
          'Cookie': 'api_key=${server.apiKey}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'folder_path': folderPath}),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      throw Exception('添加源文件夹失败');
    } catch (e) {
      print('添加源文件夹失败: $e');
      throw e;
    }
  }

  /// 移除源文件夹
  Future<Map<String, dynamic>> removeSourceFolder(String folderPath) async {
    try {
      final response = await http.post(
        Uri.parse('${server.baseUrl}/api/settings/sources/remove'),
        headers: {
          'Cookie': 'api_key=${server.apiKey}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'folder_path': folderPath}),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      throw Exception('移除源文件夹失败');
    } catch (e) {
      print('移除源文件夹失败: $e');
      throw e;
    }
  }
}
