// Downloader 前端逻辑

let currentTasks = [];
let selectedFolder = '';
let selectedDownloader = 'ytdlp'; // 默认 yt-dlp
let pollingInterval = null;
let downloadHistory = JSON.parse(localStorage.getItem('downloadHistory') || '[]');

// 页面加载完成后初始化
document.addEventListener('DOMContentLoaded', async () => {
    // 初始化 i18n
    i18nManager.updateUI();

    await loadConfig();
    await loadFolders();
    await loadTasks();

    // URL 输入检测（防抖）
    const urlInput = document.getElementById('urlInput');
    let detectTimeout;
    urlInput.addEventListener('input', () => {
        clearTimeout(detectTimeout);
        detectTimeout = setTimeout(() => {
            const url = urlInput.value.trim();
            if (url) {
                detectURL(url);
            } else {
                hideDetectResult();
            }
        }, 500);
    });

    // 开始轮询任务状态
    startPolling();
});

// 加载配置
async function loadConfig() {
    try {
        const response = await fetch('/api/downloader/config');
        const data = await response.json();
        // 可用于显示认证状态等
    } catch (error) {
        console.error('Failed to load config:', error);
    }
}

// 加载文件夹列表
async function loadFolders() {
    try {
        const response = await fetch('/api/downloader/folders');
        const folders = await response.json();

        const foldersScroll = document.getElementById('foldersScroll');

        // 保留 Root 选项
        const rootChip = foldersScroll.querySelector('[data-folder=""]');
        foldersScroll.innerHTML = '';
        foldersScroll.appendChild(rootChip);

        // 添加其他文件夹
        folders.forEach(folder => {
            if (!folder.hidden) {
                const chip = document.createElement('div');
                chip.className = 'folder-chip';
                chip.dataset.folder = folder.name;
                chip.textContent = folder.name;
                chip.onclick = () => selectFolder(folder.name);
                foldersScroll.appendChild(chip);
            }
        });
    } catch (error) {
        console.error('Failed to load folders:', error);
    }
}

// 选择文件夹
function selectFolder(folderName) {
    selectedFolder = folderName;

    // 更新 UI
    document.querySelectorAll('.folder-chip').forEach(chip => {
        chip.classList.remove('selected');
        if (chip.dataset.folder === folderName) {
            chip.classList.add('selected');
        }
    });
}

// 检测 URL
async function detectURL(url) {
    try {
        const response = await fetch('/api/downloader/detect', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ url })
        });

        const result = await response.json();
        showDetectResult(result);
    } catch (error) {
        console.error('Failed to detect URL:', error);
        hideDetectResult();
    }
}

// 显示检测结果
function showDetectResult(result) {
    const detectResult = document.getElementById('detectResult');
    const detectPlatform = document.getElementById('detectPlatform');
    const downloaderSelect = document.getElementById('downloaderSelect');

    detectPlatform.textContent = result.platform_name;

    // 自动设置推荐的下载器
    const recommendedDownloader = result.downloader === 'ytdlp' ? 'ytdlp' :
                                 result.downloader === 'gallery_dl' ? 'gallery_dl' : 'ytdlp';
    downloaderSelect.value = recommendedDownloader;
    selectedDownloader = recommendedDownloader;

    detectResult.classList.add('show');
}

// 隐藏检测结果
function hideDetectResult() {
    const detectResult = document.getElementById('detectResult');
    detectResult.classList.remove('show');
}

// 开始下载
async function startDownload() {
    const urlInput = document.getElementById('urlInput');
    const downloaderSelect = document.getElementById('downloaderSelect');
    const downloadBtn = document.getElementById('downloadBtn');

    const url = urlInput.value.trim();
    if (!url) {
        alert(i18nManager.t('urlPlaceholder'));
        return;
    }

    // 使用选中的下载器
    const downloader = downloaderSelect.value;

    // 禁用按钮
    downloadBtn.disabled = true;

    try {
        const response = await fetch('/api/downloader/task', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                url,
                downloader,
                save_folder: selectedFolder,
                format: 'best' // 固定使用 best 格式
            })
        });

        const result = await response.json();

        if (response.ok) {
            // 成功创建任务
            urlInput.value = '';
            hideDetectResult();

            // 立即刷新任务列表
            await loadTasks();

            // 自动展开任务列表
            expandTasks();
        } else {
            // 错误处理（如认证失败）
            alert(result.error || 'Failed to create download task');
        }
    } catch (error) {
        console.error('Failed to start download:', error);
        alert('Failed to start download');
    } finally {
        downloadBtn.disabled = false;
    }
}

// 加载任务列表
async function loadTasks() {
    try {
        const response = await fetch('/api/downloader/tasks');
        const data = await response.json();

        currentTasks = data.tasks || [];
        renderTasks();
        updateTasksCount();

        // 将完成的任务添加到历史记录
        currentTasks.forEach(task => {
            if (task.status === 'completed' && task.file_path) {
                addToHistory(task);
            }
        });
    } catch (error) {
        console.error('Failed to load tasks:', error);
    }
}

// 获取状态图标
function getStatusIcon(status) {
    const icons = {
        'pending': 'schedule',
        'downloading': 'download',
        'completed': 'check_circle',
        'failed': 'error',
        'cancelled': 'cancel'
    };
    return icons[status] || 'help';
}

// 渲染任务列表（合并任务和历史）
function renderTasks() {
    const tasksList = document.getElementById('tasksList');

    // 合并当前任务和历史记录
    const allTasks = [...currentTasks];

    // 添加历史记录中不在当前任务中的项
    downloadHistory.forEach(historyItem => {
        const existsInCurrent = allTasks.some(task => task.id === historyItem.id);
        if (!existsInCurrent) {
            allTasks.push({
                ...historyItem,
                status: 'completed',
                progress: 100
            });
        }
    });

    if (allTasks.length === 0) {
        tasksList.innerHTML = '<div class="empty-state" data-i18n="noTasks">No tasks</div>';
        i18nManager.updateUI();
        return;
    }

    tasksList.innerHTML = allTasks.map(task => `
        <div class="task-card" data-task-id="${task.id}">
            <div class="task-header">
                <div class="task-url" title="${task.url}">${task.url}</div>
                <span class="task-status status-${task.status}">
                    <span class="material-symbols-outlined">${getStatusIcon(task.status)}</span>
                </span>
            </div>

            <div class="task-meta">
                <div class="task-meta-item">
                    <span class="material-symbols-outlined">public</span>
                    <span>${task.platform}</span>
                </div>
                <div class="task-meta-item">
                    <span class="material-symbols-outlined">folder</span>
                    <span>${task.save_folder || 'Root'}</span>
                </div>
                ${task.speed ? `
                <div class="task-meta-item">
                    <span class="material-symbols-outlined">speed</span>
                    <span>${task.speed}</span>
                </div>
                ` : ''}
                ${task.eta ? `
                <div class="task-meta-item">
                    <span class="material-symbols-outlined">schedule</span>
                    <span>${task.eta}</span>
                </div>
                ` : ''}
            </div>

            ${task.status === 'downloading' || task.status === 'pending' ? `
            <div class="progress-bar">
                <div class="progress-fill" style="width: ${task.progress}%"></div>
            </div>
            ` : ''}

            ${task.error ? `
            <div style="font-size: 12px; color: #991b1b; margin-bottom: 8px;">${task.error}</div>
            ` : ''}

            <div class="task-actions">
                ${task.status === 'downloading' || task.status === 'pending' ? `
                <button class="btn-small" onclick="cancelTask('${task.id}')">
                    <span class="material-symbols-outlined">cancel</span>
                    <span data-i18n="cancelBtn">Cancel</span>
                </button>
                ` : ''}

                ${task.status === 'completed' && task.file_path ? `
                <button class="btn-small" onclick="previewFile('${task.file_path}', '${task.url}')">
                    <span class="material-symbols-outlined">visibility</span>
                    <span data-i18n="openFolder">Preview</span>
                </button>
                ` : ''}
            </div>
        </div>
    `).join('');

    i18nManager.updateUI();
}

// 更新任务计数
function updateTasksCount() {
    const tasksCount = document.getElementById('tasksCount');
    // 统计所有任务（包括历史）
    const uniqueIds = new Set([...currentTasks.map(t => t.id), ...downloadHistory.map(h => h.id)]);
    tasksCount.textContent = uniqueIds.size;
}

// 切换任务列表展开/折叠
function toggleTasks() {
    const tasksContent = document.getElementById('tasksContent');
    const tasksToggle = document.getElementById('tasksToggle');

    const isExpanded = tasksContent.classList.contains('expanded');

    if (isExpanded) {
        tasksContent.classList.remove('expanded');
        tasksToggle.classList.remove('expanded');
    } else {
        tasksContent.classList.add('expanded');
        tasksToggle.classList.add('expanded');
    }
}

// 展开任务列表
function expandTasks() {
    const tasksContent = document.getElementById('tasksContent');
    const tasksToggle = document.getElementById('tasksToggle');

    tasksContent.classList.add('expanded');
    tasksToggle.classList.add('expanded');
}

// 取消任务
async function cancelTask(taskId) {
    if (!confirm('Cancel this download?')) {
        return;
    }

    try {
        const response = await fetch(`/api/downloader/task/${taskId}`, {
            method: 'DELETE'
        });

        if (response.ok) {
            await loadTasks();
        } else {
            const error = await response.json();
            alert(error.error || 'Failed to cancel task');
        }
    } catch (error) {
        console.error('Failed to cancel task:', error);
        alert('Failed to cancel task');
    }
}

// 预览文件
function previewFile(filePath, url) {
    const previewModal = document.getElementById('previewModal');
    const previewContainer = document.getElementById('previewContainer');

    // URL 编码文件路径
    const encodedPath = encodeURIComponent(filePath);
    const apiUrl = `/api/downloader/file/${encodedPath}`;

    // 判断文件类型
    const ext = filePath.split('.').pop().toLowerCase();
    const isVideo = ['mp4', 'webm', 'mov', 'avi', 'mkv', 'm4v'].includes(ext);
    const isImage = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].includes(ext);

    if (isVideo) {
        previewContainer.innerHTML = `
            <video controls autoplay style="max-width: 100%; max-height: 90vh;">
                <source src="${apiUrl}" type="video/${ext}">
                Your browser does not support the video tag.
            </video>
        `;
    } else if (isImage) {
        previewContainer.innerHTML = `
            <img src="${apiUrl}" alt="Preview" style="max-width: 100%; max-height: 90vh; object-fit: contain;">
        `;
    } else {
        previewContainer.innerHTML = `
            <div style="padding: 40px; text-align: center; color: #525252;">
                <span class="material-symbols-outlined" style="font-size: 48px; margin-bottom: 16px;">insert_drive_file</span>
                <p style="margin-bottom: 8px;">File saved to:</p>
                <p style="font-size: 13px; word-break: break-all;">${filePath}</p>
            </div>
        `;
    }

    previewModal.classList.add('show');
}

// 关闭预览
function closePreview() {
    const previewModal = document.getElementById('previewModal');
    previewModal.classList.remove('show');
}

// 开始轮询任务状态
function startPolling() {
    // 每 2 秒刷新一次任务列表
    pollingInterval = setInterval(async () => {
        // 只有在有进行中的任务时才轮询
        const hasActiveTasks = currentTasks.some(task =>
            task.status === 'downloading' || task.status === 'pending'
        );

        if (hasActiveTasks) {
            await loadTasks();
        }
    }, 2000);
}

// 页面卸载时停止轮询
window.addEventListener('beforeunload', () => {
    if (pollingInterval) {
        clearInterval(pollingInterval);
    }
});

// 添加到历史记录
function addToHistory(task) {
    // 检查是否已存在
    const exists = downloadHistory.some(item => item.id === task.id);
    if (exists) return;

    // 添加到历史记录
    downloadHistory.unshift({
        id: task.id,
        url: task.url,
        platform: task.platform,
        file_name: task.file_name,
        file_path: task.file_path,
        created_at: task.created_at
    });

    // 限制历史记录数量（最多100条）
    if (downloadHistory.length > 100) {
        downloadHistory = downloadHistory.slice(0, 100);
    }

    // 保存到 localStorage
    localStorage.setItem('downloadHistory', JSON.stringify(downloadHistory));
}

// 清空历史记录（只清除已完成的，保留进行中的）
function clearHistory() {
    if (!confirm(i18nManager.t('clearHistory') + '?')) {
        return;
    }

    // 获取当前正在下载的任务ID
    const activeTaskIds = currentTasks
        .filter(task => task.status === 'downloading' || task.status === 'pending')
        .map(task => task.id);

    // 只保留正在下载的任务
    downloadHistory = downloadHistory.filter(item => activeTaskIds.includes(item.id));

    localStorage.setItem('downloadHistory', JSON.stringify(downloadHistory));
    renderTasks();
    updateTasksCount();
}

