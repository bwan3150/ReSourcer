import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:dio/dio.dart';
import 'storage_service.dart';

/// API 服务
class ApiService {
  late String _baseUrl;
  late String _apiKey;
  final Dio _dio = Dio();

  ApiService._();

  static Future<ApiService> create() async {
    final service = ApiService._();
    final storage = await StorageService.getInstance();

    service._baseUrl = storage.getBaseUrl() ?? '';
    service._apiKey = storage.getApiKey() ?? '';

    // 配置 Dio
    service._dio.options.headers['Cookie'] = 'api_key=${service._apiKey}';
    service._dio.options.connectTimeout = const Duration(seconds: 10);
    service._dio.options.receiveTimeout = const Duration(seconds: 10);

    return service;
  }

  /// 验证 API Key
  Future<bool> verifyApiKey(String baseUrl, String apiKey) async {
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

  /// 获取文件夹列表
  Future<List<dynamic>> getGalleryFolders() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/gallery/folders'),
        headers: {'Cookie': 'api_key=$_apiKey'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        return data['folders'] ?? [];
      }
      return [];
    } catch (e) {
      print('获取文件夹列表失败: $e');
      return [];
    }
  }

  /// 获取指定文件夹的文件列表
  Future<List<dynamic>> getGalleryFiles(String folderPath) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/gallery/files?folder=${Uri.encodeComponent(folderPath)}'),
        headers: {'Cookie': 'api_key=$_apiKey'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        return data['files'] ?? [];
      }
      return [];
    } catch (e) {
      print('获取画廊文件失败: $e');
      return [];
    }
  }

  /// 上传文件
  Future<String?> uploadFile(String filePath, String targetFolder) async {
    try {
      String fileName = filePath.split('/').last;

      FormData formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath, filename: fileName),
        'target_folder': targetFolder,
      });

      final response = await _dio.post(
        '$_baseUrl/api/uploader/upload',
        data: formData,
        options: Options(
          headers: {'Cookie': 'api_key=$_apiKey'},
        ),
      );

      if (response.statusCode == 200) {
        return response.data['task_id'];
      }
      return null;
    } catch (e) {
      print('上传文件失败: $e');
      return null;
    }
  }

  /// 获取上传任务列表
  Future<List<dynamic>> getUploadTasks() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/uploader/tasks'),
        headers: {'Cookie': 'api_key=$_apiKey'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['tasks'] ?? [];
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
        Uri.parse('$_baseUrl/api/uploader/tasks/$taskId'),
        headers: {'Cookie': 'api_key=$_apiKey'},
      );

      return response.statusCode == 200;
    } catch (e) {
      print('删除上传任务失败: $e');
      return false;
    }
  }

  /// 获取图片缩略图 URL
  String getThumbnailUrl(String filePath) {
    return '$_baseUrl/api/gallery/thumbnail?path=${Uri.encodeComponent(filePath)}&size=300';
  }

  /// 获取原图 URL
  String getImageUrl(String filePath) {
    return '$_baseUrl/api/classifier/file/${Uri.encodeComponent(filePath)}';
  }
}
