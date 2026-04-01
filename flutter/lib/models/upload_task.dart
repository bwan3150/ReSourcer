/// 上传任务状态
enum UploadStatus {
  pending,
  uploading,
  completed,
  failed,
}

/// 上传任务模型
class UploadTask {
  final String id;
  final String fileName;
  final int fileSize;
  final String targetFolder;
  final UploadStatus status;
  final double progress;
  final int uploadedSize;
  final String? error;
  final String createdAt;

  UploadTask({
    required this.id,
    required this.fileName,
    required this.fileSize,
    required this.targetFolder,
    required this.status,
    required this.progress,
    required this.uploadedSize,
    this.error,
    required this.createdAt,
  });

  factory UploadTask.fromJson(Map<String, dynamic> json) {
    return UploadTask(
      id: json['id'] ?? '',
      fileName: json['file_name'] ?? '',
      fileSize: json['file_size'] ?? 0,
      targetFolder: json['target_folder'] ?? '',
      status: _parseStatus(json['status']),
      progress: (json['progress'] ?? 0).toDouble(),
      uploadedSize: json['uploaded_size'] ?? 0,
      error: json['error'],
      createdAt: json['created_at'] ?? '',
    );
  }

  static UploadStatus _parseStatus(String? status) {
    switch (status?.toLowerCase()) {
      case 'pending':
        return UploadStatus.pending;
      case 'uploading':
        return UploadStatus.uploading;
      case 'completed':
        return UploadStatus.completed;
      case 'failed':
        return UploadStatus.failed;
      default:
        return UploadStatus.pending;
    }
  }
}
