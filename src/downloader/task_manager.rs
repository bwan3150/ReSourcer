// 任务管理器：管理下载任务队列、状态追踪、进度更新
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::Mutex;
use super::models::{DownloadTask, Platform, DownloaderType, TaskStatus};

/// 任务管理器
pub struct TaskManager {
    tasks: Arc<Mutex<HashMap<String, DownloadTask>>>,
}

impl TaskManager {
    /// 创建新的任务管理器
    pub fn new() -> Self {
        TaskManager {
            tasks: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    /// 创建新任务并开始下载
    pub async fn create_task(
        &self,
        url: String,
        platform: Platform,
        downloader: DownloaderType,
        save_folder: String,
        format: Option<String>,
    ) -> Result<String, String> {
        // 1. 生成唯一任务 ID
        let task_id = uuid::Uuid::new_v4().to_string();

        // 2. 创建任务对象
        let task = DownloadTask {
            id: task_id.clone(),
            url: url.clone(),
            platform: platform.clone(),
            downloader: downloader.clone(),
            status: TaskStatus::Pending,
            progress: 0.0,
            speed: None,
            eta: None,
            save_folder: save_folder.clone(),
            file_name: None,
            file_path: None,
            error: None,
            created_at: chrono::Utc::now().to_rfc3339(),
        };

        // 3. 存储任务
        self.tasks.lock().await.insert(task_id.clone(), task);

        // 4. 异步启动下载
        let task_id_clone = task_id.clone();
        let tasks_clone = self.tasks.clone();
        tokio::spawn(async move {
            Self::execute_download(
                task_id_clone,
                url,
                platform,
                downloader,
                save_folder,
                format,
                tasks_clone,
            )
            .await;
        });

        Ok(task_id)
    }

    /// 获取单个任务
    pub async fn get_task(&self, task_id: &str) -> Option<DownloadTask> {
        self.tasks.lock().await.get(task_id).cloned()
    }

    /// 获取所有任务
    pub async fn get_all_tasks(&self) -> Vec<DownloadTask> {
        self.tasks.lock().await.values().cloned().collect()
    }

    /// 更新任务进度
    pub async fn update_progress(
        &self,
        task_id: &str,
        progress: f32,
        speed: Option<String>,
        eta: Option<String>,
    ) {
        if let Some(task) = self.tasks.lock().await.get_mut(task_id) {
            task.progress = progress;
            task.speed = speed;
            task.eta = eta;
        }
    }

    /// 更新任务状态
    pub async fn update_status(&self, task_id: &str, status: TaskStatus) {
        if let Some(task) = self.tasks.lock().await.get_mut(task_id) {
            task.status = status;
        }
    }

    /// 设置任务完成
    pub async fn complete_task(&self, task_id: &str, file_name: String, file_path: String) {
        if let Some(task) = self.tasks.lock().await.get_mut(task_id) {
            task.status = TaskStatus::Completed;
            task.progress = 100.0;
            task.file_name = Some(file_name);
            task.file_path = Some(file_path);
        }
    }

    /// 设置任务失败
    pub async fn fail_task(&self, task_id: &str, error: String) {
        if let Some(task) = self.tasks.lock().await.get_mut(task_id) {
            task.status = TaskStatus::Failed;
            task.error = Some(error);
        }
    }

    /// 取消任务（基础版本：只更新状态，不杀进程）
    pub async fn cancel_task(&self, task_id: &str) -> Result<(), String> {
        if let Some(task) = self.tasks.lock().await.get_mut(task_id) {
            // 只有 Pending 或 Downloading 状态才能取消
            match task.status {
                TaskStatus::Pending | TaskStatus::Downloading => {
                    task.status = TaskStatus::Cancelled;
                    Ok(())
                }
                _ => Err("任务已完成或已取消，无法再次取消".to_string()),
            }
        } else {
            Err("任务不存在".to_string())
        }
    }

    /// 执行下载（私有函数）
    async fn execute_download(
        task_id: String,
        url: String,
        platform: Platform,
        downloader: DownloaderType,
        save_folder: String,
        format: Option<String>,
        tasks: Arc<Mutex<HashMap<String, DownloadTask>>>,
    ) {
        // 1. 更新状态为 Downloading
        if let Some(task) = tasks.lock().await.get_mut(&task_id) {
            task.status = TaskStatus::Downloading;
        }

        // 2. 根据下载器类型调用对应的下载器
        let result = match downloader {
            DownloaderType::YtDlp => {
                // 创建进度回调
                let task_id_clone = task_id.clone();
                let tasks_clone = tasks.clone();

                super::downloaders::ytdlp::download(
                    url.clone(),
                    platform,
                    save_folder.clone(),
                    format,
                    move |progress, speed, eta| {
                        let task_id = task_id_clone.clone();
                        let tasks = tasks_clone.clone();

                        // 在回调中更新进度
                        tokio::spawn(async move {
                            if let Some(task) = tasks.lock().await.get_mut(&task_id) {
                                task.progress = progress;
                                task.speed = speed;
                                task.eta = eta;
                            }
                        });
                    },
                )
                .await
            }
            DownloaderType::GalleryDl => {
                // 未来实现
                Err("GalleryDl 下载器尚未实现".to_string())
            }
            _ => Err("不支持的下载器类型".to_string()),
        };

        // 3. 根据结果更新任务状态
        match result {
            Ok(file_path) => {
                // 下载成功，file_path 现在是完整的文件路径
                if let Some(task) = tasks.lock().await.get_mut(&task_id) {
                    task.status = TaskStatus::Completed;
                    task.progress = 100.0;

                    // 从文件路径中提取文件名
                    let file_name = std::path::Path::new(&file_path)
                        .file_name()
                        .and_then(|n| n.to_str())
                        .unwrap_or("unknown")
                        .to_string();

                    task.file_path = Some(file_path.clone());
                    task.file_name = Some(file_name.clone());

                    // 添加到历史记录
                    let history_item = super::config::HistoryItem {
                        id: task.id.clone(),
                        url: task.url.clone(),
                        platform: task.platform.to_string(),
                        file_name,
                        file_path,
                        created_at: task.created_at.clone(),
                    };

                    if let Err(e) = super::config::add_to_history(history_item) {
                        eprintln!("保存历史记录失败: {}", e);
                    }
                }
            }
            Err(error) => {
                // 下载失败
                if let Some(task) = tasks.lock().await.get_mut(&task_id) {
                    task.status = TaskStatus::Failed;
                    task.error = Some(error);
                }
            }
        }
    }
}

impl Default for TaskManager {
    fn default() -> Self {
        Self::new()
    }
}
