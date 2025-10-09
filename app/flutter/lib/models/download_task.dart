/// 下载任务模型
class DownloadTask {
  final String id;
  final String url;
  final String platform;
  final String downloader;
  final String status; // pending, downloading, completed, failed, cancelled
  final double progress; // 0-100
  final String? speed;
  final String? eta;
  final String? fileName;
  final String? filePath;
  final String? saveFolder;
  final String? error;
  final DateTime createdAt;
  final DateTime? completedAt;

  const DownloadTask({
    required this.id,
    required this.url,
    required this.platform,
    required this.downloader,
    required this.status,
    this.progress = 0,
    this.speed,
    this.eta,
    this.fileName,
    this.filePath,
    this.saveFolder,
    this.error,
    required this.createdAt,
    this.completedAt,
  });

  /// 从JSON创建任务
  factory DownloadTask.fromJson(Map<String, dynamic> json) {
    return DownloadTask(
      id: json['id'] as String,
      url: json['url'] as String,
      platform: json['platform'] as String? ?? 'Unknown',
      downloader: json['downloader'] as String? ?? 'ytdlp',
      status: json['status'] as String,
      progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
      speed: json['speed'] as String?,
      eta: json['eta'] as String?,
      fileName: json['file_name'] as String?,
      filePath: json['file_path'] as String?,
      saveFolder: json['save_folder'] as String?,
      error: json['error'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String)
          : null,
    );
  }

  /// 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'url': url,
      'platform': platform,
      'downloader': downloader,
      'status': status,
      'progress': progress,
      'speed': speed,
      'eta': eta,
      'file_name': fileName,
      'file_path': filePath,
      'save_folder': saveFolder,
      'error': error,
      'created_at': createdAt.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
    };
  }

  /// 复制并修改字段
  DownloadTask copyWith({
    String? id,
    String? url,
    String? platform,
    String? downloader,
    String? status,
    double? progress,
    String? speed,
    String? eta,
    String? fileName,
    String? filePath,
    String? saveFolder,
    String? error,
    DateTime? createdAt,
    DateTime? completedAt,
  }) {
    return DownloadTask(
      id: id ?? this.id,
      url: url ?? this.url,
      platform: platform ?? this.platform,
      downloader: downloader ?? this.downloader,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      speed: speed ?? this.speed,
      eta: eta ?? this.eta,
      fileName: fileName ?? this.fileName,
      filePath: filePath ?? this.filePath,
      saveFolder: saveFolder ?? this.saveFolder,
      error: error ?? this.error,
      createdAt: createdAt ?? this.createdAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  /// 是否是进行中的任务
  bool get isActive => status == 'pending' || status == 'downloading';

  /// 是否已完成
  bool get isCompleted => status == 'completed';

  /// 是否失败
  bool get isFailed => status == 'failed';

  /// 是否已取消
  bool get isCancelled => status == 'cancelled';

  /// 是否可以取消
  bool get canCancel => isActive;

  /// 是否可以删除
  bool get canDelete => !isActive;
}

/// 下载文件夹模型
class DownloadFolder {
  final String name;
  final int fileCount;
  final bool isHidden;

  const DownloadFolder({
    required this.name,
    required this.fileCount,
    this.isHidden = false,
  });

  factory DownloadFolder.fromJson(Map<String, dynamic> json) {
    return DownloadFolder(
      name: json['name'] as String,
      fileCount: json['file_count'] as int? ?? 0,
      isHidden: json['hidden'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'file_count': fileCount,
      'hidden': isHidden,
    };
  }
}

/// URL检测结果
class UrlDetectResult {
  final String platform;
  final String platformName;
  final String downloader;

  const UrlDetectResult({
    required this.platform,
    required this.platformName,
    required this.downloader,
  });

  factory UrlDetectResult.fromJson(Map<String, dynamic> json) {
    return UrlDetectResult(
      platform: json['platform'] as String,
      platformName: json['platform_name'] as String,
      downloader: json['downloader'] as String,
    );
  }
}

/// 认证状态
class AuthStatus {
  final String platform;
  final String platformName;
  final String downloader;
  final bool isActive;

  const AuthStatus({
    required this.platform,
    required this.platformName,
    required this.downloader,
    required this.isActive,
  });
}
