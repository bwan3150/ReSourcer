import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/server.dart';

/// 分类器 API 服务
class ClassifierApiService {
  final Server server;

  ClassifierApiService(this.server);

  /// 获取分类器状态
  Future<Map<String, dynamic>> getState() async {
    try {
      final response = await http.get(
        Uri.parse('${server.baseUrl}/api/classifier/state'),
        headers: {'Cookie': 'api_key=${server.apiKey}'},
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      throw Exception('获取分类器状态失败');
    } catch (e) {
      print('获取分类器状态失败: $e');
      throw e;
    }
  }

  /// 获取分类文件夹列表
  Future<List<Map<String, dynamic>>> getFolders(String sourceFolder) async {
    try {
      final response = await http.get(
        Uri.parse('${server.baseUrl}/api/classifier/folders?source_folder=${Uri.encodeComponent(sourceFolder)}'),
        headers: {'Cookie': 'api_key=${server.apiKey}'},
      );

      if (response.statusCode == 200) {
        final List<dynamic> folders = jsonDecode(response.body);
        return folders.cast<Map<String, dynamic>>();
      }
      throw Exception('获取分类文件夹失败');
    } catch (e) {
      print('获取分类文件夹失败: $e');
      throw e;
    }
  }

  /// 获取待分类文件列表
  Future<List<Map<String, dynamic>>> getFiles() async {
    try {
      final response = await http.get(
        Uri.parse('${server.baseUrl}/api/classifier/files'),
        headers: {'Cookie': 'api_key=${server.apiKey}'},
      );

      if (response.statusCode == 200) {
        final List<dynamic> files = jsonDecode(response.body);
        return files.cast<Map<String, dynamic>>();
      }
      throw Exception('获取文件列表失败');
    } catch (e) {
      print('获取文件列表失败: $e');
      throw e;
    }
  }

  /// 移动文件到分类文件夹
  Future<Map<String, dynamic>> moveFile({
    required String filePath,
    required String category,
    String? newName,
  }) async {
    try {
      final Map<String, dynamic> body = {
        'file_path': filePath,
        'category': category,
      };
      if (newName != null && newName.isNotEmpty) {
        body['new_name'] = newName;
      }

      final response = await http.post(
        Uri.parse('${server.baseUrl}/api/classifier/move'),
        headers: {
          'Cookie': 'api_key=${server.apiKey}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      throw Exception('移动文件失败');
    } catch (e) {
      print('移动文件失败: $e');
      throw e;
    }
  }

  /// 创建分类文件夹
  Future<Map<String, dynamic>> createFolder(String folderName) async {
    try {
      final response = await http.post(
        Uri.parse('${server.baseUrl}/api/classifier/folder/create'),
        headers: {
          'Cookie': 'api_key=${server.apiKey}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'folder_name': folderName}),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      throw Exception('创建文件夹失败');
    } catch (e) {
      print('创建文件夹失败: $e');
      throw e;
    }
  }

  /// 获取文件的缩略图 URL
  String getThumbnailUrl(String filePath, {int size = 300}) {
    return '${server.baseUrl}/api/gallery/thumbnail?path=${Uri.encodeComponent(filePath)}&size=$size';
  }

  /// 获取文件的原图/视频 URL
  String getFileUrl(String filePath) {
    return '${server.baseUrl}/api/classifier/file/${Uri.encodeComponent(filePath)}';
  }

  /// 保存分类顺序
  Future<Map<String, dynamic>> reorderCategories(String sourceFolder, List<String> categoryOrder) async {
    try {
      final response = await http.post(
        Uri.parse('${server.baseUrl}/api/classifier/categories/reorder'),
        headers: {
          'Cookie': 'api_key=${server.apiKey}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'source_folder': sourceFolder,
          'category_order': categoryOrder,
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      throw Exception('保存分类顺序失败');
    } catch (e) {
      print('保存分类顺序失败: $e');
      throw e;
    }
  }
}
