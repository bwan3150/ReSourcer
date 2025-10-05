// Downloader 前端逻辑

let currentTasks = [];
let selectedFolder = '';
let pollingInterval = null;

// 页面加载完成后初始化
document.addEventListener('DOMContentLoaded', async () => {
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
    const detectDownloader = document.getElementById('detectDownloader');

    detectPlatform.textContent = result.platform_name;
    detectDownloader.textContent = result.downloader;

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
    const formatInput = document.getElementById('formatInput');
    const downloadBtn = document.getElementById('downloadBtn');

    const url = urlInput.value.trim();
    if (!url) {
        alert('Please enter a URL');
        return;
    }

    const format = formatInput.value.trim() || null;

    // 禁用按钮
    downloadBtn.disabled = true;

    try {
        const response = await fetch('/api/downloader/task', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                url,
                downloader: null, // 使用自动检测
                save_folder: selectedFolder,
                format
            })
        });

        const result = await response.json();

        if (response.ok) {
            // 成功创建任务
            urlInput.value = '';
            formatInput.value = '';
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
    } catch (error) {
        console.error('Failed to load tasks:', error);
    }
}

// 渲染任务列表
function renderTasks() {
    const tasksList = document.getElementById('tasksList');

    if (currentTasks.length === 0) {
        tasksList.innerHTML = '<div class="empty-state" data-i18n="noTasks">No tasks</div>';
        i18nManager.updateUI();
        return;
    }

    tasksList.innerHTML = currentTasks.map(task => `
        <div class="task-card" data-task-id="${task.id}">
            <div class="task-header">
                <div class="task-url" title="${task.url}">${task.url}</div>
                <span class="task-status status-${task.status}">${task.status}</span>
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
                <button class="btn-small" onclick="openFolder('${task.file_path}')">
                    <span class="material-symbols-outlined">folder_open</span>
                    <span data-i18n="openFolder">Open</span>
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
    tasksCount.textContent = currentTasks.length;
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

// 打开文件夹（仅提示，无法直接打开本地文件夹）
function openFolder(filePath) {
    alert(`File saved to: ${filePath}`);
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
