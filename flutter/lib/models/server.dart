/// 服务器模型
class Server {
  final String id;
  final String name;
  final String baseUrl;
  final String apiKey;
  final DateTime addedAt;

  Server({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.apiKey,
    required this.addedAt,
  });

  factory Server.fromJson(Map<String, dynamic> json) {
    return Server(
      id: json['id'],
      name: json['name'],
      baseUrl: json['baseUrl'],
      apiKey: json['apiKey'],
      addedAt: DateTime.parse(json['addedAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'baseUrl': baseUrl,
      'apiKey': apiKey,
      'addedAt': addedAt.toIso8601String(),
    };
  }

  Server copyWith({
    String? id,
    String? name,
    String? baseUrl,
    String? apiKey,
    DateTime? addedAt,
  }) {
    return Server(
      id: id ?? this.id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      addedAt: addedAt ?? this.addedAt,
    );
  }
}

/// 服务器状态
enum ServerStatus {
  online,      // 绿色 - 正常
  authError,   // 黄色 - API Key 无效
  offline,     // 红色 - 服务器离线
  checking,    // 灰色 - 检查中
}
