// 上传任务管理器：管理上传任务队列、状态追踪、进度更新
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::Mutex;
use super::models::{UploadTask, UploadStatus};
use std::path::Path;
use tokio::io::AsyncWriteExt;
use futures_util::StreamExt;

/// 任务管理器
pub struct TaskManager {
    tasks: Arc<Mutex<HashMap<String, UploadTask>>>,
}

impl TaskManager {
    /// 创建新的任务管理器
    pub fn new() -> Self {
        TaskManager {
            tasks: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    /// 创建任务并执行上传（流式处理，直接处理）
    pub async fn create_and_upload(
        &self,
        file_name: String,
        target_folder: String,
        field: actix_multipart::Field,
    ) -> Result<String, String> {
        // 1. 生成唯一任务 ID
        let task_id = uuid::Uuid::new_v4().to_string();

        // 2. 创建任务对象（初始文件大小未知）
        let task = UploadTask {
            id: task_id.clone(),
            file_name: file_name.clone(),
            file_size: 0,  // 初始未知
            target_folder: target_folder.clone(),
            status: UploadStatus::Pending,
            progress: 0.0,
            uploaded_size: 0,
            error: None,
            created_at: chrono::Utc::now().to_rfc3339(),
        };

        // 3. 存储任务
        self.tasks.lock().await.insert(task_id.clone(), task);

        // 4. 在后台spawn任务执行上传（避免阻塞响应）
        let task_id_clone = task_id.clone();
        let file_name_clone = file_name.clone();
        let target_folder_clone = target_folder.clone();
        let tasks_clone = self.tasks.clone();

        actix_web::rt::spawn(async move {
            Self::execute_upload_static(
                task_id_clone,
                file_name_clone,
                target_folder_clone,
                field,
                tasks_clone,
            )
            .await;
        });

        Ok(task_id)
    }

    /// 静态方法执行上传（用于spawn）
    async fn execute_upload_static(
        task_id: String,
        file_name: String,
        target_folder: String,
        mut field: actix_multipart::Field,
        tasks: Arc<Mutex<HashMap<String, UploadTask>>>,
    ) {
        // 更新状态为上传中
        Self::update_status(&tasks, &task_id, UploadStatus::Uploading).await;

        // 确保目标文件夹存在
        if let Err(e) = tokio::fs::create_dir_all(&target_folder).await {
            Self::update_error(&tasks, &task_id, format!("无法创建目标文件夹: {}", e)).await;
            return;
        }

        // 构建文件路径
        let file_path = Path::new(&target_folder).join(&file_name);

        // 检查文件是否已存在
        if file_path.exists() {
            Self::update_error(&tasks, &task_id, format!("文件已存在: {}", file_name)).await;
            return;
        }

        // 创建文件
        let mut file = match tokio::fs::File::create(&file_path).await {
            Ok(f) => f,
            Err(e) => {
                Self::update_error(&tasks, &task_id, format!("无法创建文件: {}", e)).await;
                return;
            }
        };

        let mut uploaded_size: u64 = 0;

        // 读取并写入文件数据
        while let Some(chunk) = field.next().await {
            match chunk {
                Ok(data) => {
                    if let Err(e) = file.write_all(&data).await {
                        Self::update_error(&tasks, &task_id, format!("写入文件失败: {}", e)).await;
                        return;
                    }
                    uploaded_size += data.len() as u64;

                    // 更新进度 (由于不知道总大小，这里以已上传大小为准)
                    Self::update_progress_with_size(&tasks, &task_id, uploaded_size, uploaded_size).await;
                }
                Err(e) => {
                    Self::update_error(&tasks, &task_id, format!("读取数据失败: {}", e)).await;
                    return;
                }
            }
        }

        // 确保文件已刷新到磁盘
        if let Err(e) = file.flush().await {
            Self::update_error(&tasks, &task_id, format!("刷新文件失败: {}", e)).await;
            return;
        }

        // 上传完成
        Self::update_status(&tasks, &task_id, UploadStatus::Completed).await;
        Self::update_progress(&tasks, &task_id, uploaded_size, 100.0).await;
    }

    /// 获取单个任务
    pub async fn get_task(&self, task_id: &str) -> Option<UploadTask> {
        self.tasks.lock().await.get(task_id).cloned()
    }

    /// 获取所有任务
    pub async fn get_all_tasks(&self) -> Vec<UploadTask> {
        self.tasks.lock().await.values().cloned().collect()
    }

    /// 删除任务
    pub async fn delete_task(&self, task_id: &str) -> bool {
        self.tasks.lock().await.remove(task_id).is_some()
    }

    /// 更新任务状态
    async fn update_status(
        tasks: &Arc<Mutex<HashMap<String, UploadTask>>>,
        task_id: &str,
        status: UploadStatus,
    ) {
        if let Some(task) = tasks.lock().await.get_mut(task_id) {
            task.status = status;
        }
    }

    /// 更新任务进度
    async fn update_progress(
        tasks: &Arc<Mutex<HashMap<String, UploadTask>>>,
        task_id: &str,
        uploaded_size: u64,
        progress: f32,
    ) {
        if let Some(task) = tasks.lock().await.get_mut(task_id) {
            task.uploaded_size = uploaded_size;
            task.progress = progress;
        }
    }

    /// 更新任务进度（包含文件大小）
    async fn update_progress_with_size(
        tasks: &Arc<Mutex<HashMap<String, UploadTask>>>,
        task_id: &str,
        uploaded_size: u64,
        total_size: u64,
    ) {
        if let Some(task) = tasks.lock().await.get_mut(task_id) {
            task.uploaded_size = uploaded_size;
            task.file_size = total_size;
            // 由于流式上传，我们用已上传字节数来表示进度
            task.progress = if total_size > 0 {
                (uploaded_size as f32 / total_size as f32 * 100.0).min(100.0)
            } else {
                0.0
            };
        }
    }

    /// 更新任务错误
    async fn update_error(
        tasks: &Arc<Mutex<HashMap<String, UploadTask>>>,
        task_id: &str,
        error: String,
    ) {
        if let Some(task) = tasks.lock().await.get_mut(task_id) {
            task.status = UploadStatus::Failed;
            task.error = Some(error);
        }
    }
}
