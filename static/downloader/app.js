// Downloader 前端逻辑

let currentTasks = [];
let selectedFolder = '';
let selectedDownloader = 'ytdlp'; // 默认 yt-dlp
let pollingInterval = null;

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

        // 检查是否配置了源文件夹
        if (!data.source_folder || data.source_folder.trim() === '') {
            // 跳转到设置页面
            if (confirm(i18nManager.translate('pleaseConfigureSourceFolder') || '请先在设置页面配置源文件夹')) {
                window.location.href = '/settings/';
            }
        }
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

        // 保留源文件夹和添加按钮
        const rootChip = foldersScroll.querySelector('[data-folder=""]');
        const addButton = foldersScroll.querySelector('.add-folder');
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

        // 添加按钮放在最后
        foldersScroll.appendChild(addButton);
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

    // 自动设置推荐的下载器（后端返回小写带下划线格式）
    const recommendedDownloader = result.downloader === 'ytdlp' ? 'ytdlp' :
                                 result.downloader === 'pixiv_toolkit' ? 'pixiv_toolkit' : 'ytdlp';
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

    if (currentTasks.length === 0) {
        tasksList.innerHTML = '<div class="empty-state" data-i18n="noTasks">No tasks</div>';
        i18nManager.updateUI();
        return;
    }

    tasksList.innerHTML = currentTasks.map(task => `
        <div class="task-card" data-task-id="${task.id}">
            <div class="task-header">
                <div class="task-url" title="${task.url}">
                    ${task.status === 'completed' && task.file_name ? task.file_name : task.url}
                </div>
                <span class="task-status status-${task.status}">
                    ${(task.status === 'pending' || (task.status === 'downloading' && task.progress === 0)) ? '<div class="loader-pending"></div>' :
                      (task.status === 'downloading' && task.progress > 0) ? '<div class="loader-downloading"></div>' :
                      `<span class="material-symbols-outlined">${getStatusIcon(task.status)}</span>`}
                </span>
            </div>

            <div class="task-meta">
                <div class="task-meta-item">
                    <span class="material-symbols-outlined">public</span>
                    <span>${task.platform}</span>
                </div>
                <div class="task-meta-item">
                    <span class="material-symbols-outlined">folder</span>
                    <span>${task.file_path ? task.file_path.split('/').slice(0, -1).join('/') : (task.save_folder || 'Root')}</span>
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
                <button class="btn-small" onclick="window.open('${task.url}', '_blank')">
                    <span class="material-symbols-outlined">open_in_new</span>
                    <span data-i18n="openUrl">URL</span>
                </button>
                <button class="btn-small" onclick="previewFile('${task.file_path}', '${task.url}')">
                    <span class="material-symbols-outlined">visibility</span>
                    <span data-i18n="previewBtn">Preview</span>
                </button>
                <button class="btn-small" onclick="openFolder('${task.file_path}')">
                    <span class="material-symbols-outlined">folder_open</span>
                    <span data-i18n="openFolder">Open</span>
                </button>
                ` : ''}

                ${task.status === 'completed' || task.status === 'failed' || task.status === 'cancelled' ? `
                <button class="btn-small btn-delete" onclick="deleteTask('${task.id}')">
                    <span class="material-symbols-outlined">delete</span>
                    <span data-i18n="deleteBtn">Delete</span>
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

// 预览文件
async function previewFile(filePath, url) {
    const previewModal = document.getElementById('previewModal');
    const previewContainer = document.getElementById('previewContainer');

    // URL 编码文件路径
    const encodedPath = encodeURIComponent(filePath);
    const apiUrl = `/api/downloader/file/${encodedPath}`;

    // 判断文件类型
    const ext = filePath.split('.').pop().toLowerCase();
    const isVideo = ['mp4', 'webm', 'mov', 'avi', 'mkv', 'm4v'].includes(ext);
    const isImage = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].includes(ext);

    console.log('Preview file:', filePath);
    console.log('Extension:', ext);
    console.log('Is video:', isVideo);
    console.log('Is image:', isImage);
    console.log('API URL:', apiUrl);

    if (isVideo) {
        previewContainer.innerHTML = `
            <video controls autoplay style="max-width: 100%; max-height: 90vh;">
                <source src="${apiUrl}" type="video/${ext}">
                Your browser does not support the video tag.
            </video>
        `;
        previewModal.classList.add('show');
    } else if (isImage) {
        previewContainer.innerHTML = `
            <img src="${apiUrl}" alt="Preview" style="max-width: 100%; max-height: 90vh; object-fit: contain;">
        `;
        previewModal.classList.add('show');
    } else {
        // 不支持的文件类型，报错
        alert(`Preview not supported for file type: .${ext}\nFile path: ${filePath}`);
    }
}

// 关闭预览
function closePreview() {
    const previewModal = document.getElementById('previewModal');
    const previewContainer = document.getElementById('previewContainer');

    // 停止视频/音频播放
    const video = previewContainer.querySelector('video');
    const audio = previewContainer.querySelector('audio');

    if (video) {
        video.pause();
        video.currentTime = 0;
        video.src = ''; // 清空源
    }

    if (audio) {
        audio.pause();
        audio.currentTime = 0;
        audio.src = ''; // 清空源
    }

    // 清空容器
    previewContainer.innerHTML = '';

    previewModal.classList.remove('show');
}

// 打开文件所在文件夹
async function openFolder(filePath) {
    try {
        // 调用后端 API 打开文件夹
        const response = await fetch('/api/downloader/open-folder', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ path: filePath })
        });

        const result = await response.json();

        if (!response.ok) {
            alert(result.error || 'Failed to open folder');
        }
    } catch (error) {
        console.error('Failed to open folder:', error);
        alert('Failed to open folder');
    }
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

// 删除单个任务
async function deleteTask(taskId) {
    try {
        const response = await fetch(`/api/downloader/task/${taskId}`, {
            method: 'DELETE'
        });

        console.log('Delete response status:', response.status);
        const data = await response.json();
        console.log('Delete response data:', data);

        if (response.ok) {
            await loadTasks();
        } else {
            alert(data.error || 'Failed to delete task');
        }
    } catch (error) {
        console.error('Failed to delete task:', error);
        alert('Failed to delete task: ' + error.message);
    }
}

// 清空历史记录
async function clearHistory() {
    if (!confirm(i18nManager.t('clearHistory') + '?')) {
        return;
    }

    try {
        const response = await fetch('/api/downloader/history', {
            method: 'DELETE'
        });

        if (response.ok) {
            await loadTasks();
        } else {
            const error = await response.json();
            alert(error.error || 'Failed to clear history');
        }
    } catch (error) {
        console.error('Failed to clear history:', error);
        alert('Failed to clear history');
    }
}

// 创建新文件夹
async function createNewFolder() {
    const folderName = prompt(i18nManager.t('addNewFolder') + ':');

    if (!folderName || !folderName.trim()) {
        return;
    }

    try {
        const response = await fetch('/api/downloader/create-folder', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ folder_name: folderName.trim() })
        });

        const result = await response.json();

        if (response.ok) {
            // 重新加载文件夹列表
            await loadFolders();
            // 自动选择新创建的文件夹
            selectFolder(folderName.trim());
        } else {
            alert(result.error || 'Failed to create folder');
        }
    } catch (error) {
        console.error('Failed to create folder:', error);
        alert('Failed to create folder');
    }
}

// 认证管理
const authConfigs = [
    { platform: 'X (Twitter)', key: 'x', downloader: 'yt-dlp', type: 'cookies' },
    { platform: 'Pixiv', key: 'pixiv', downloader: 'pixiv-toolkit', type: 'token' }
];

// 打开认证弹窗
async function openAuthModal() {
    const authModal = document.getElementById('authModal');
    await loadAuthStatus();
    authModal.classList.add('show');
}

// 关闭认证弹窗
function closeAuthModal() {
    const authModal = document.getElementById('authModal');
    authModal.classList.remove('show');
}

// 加载认证状态
async function loadAuthStatus() {
    try {
        const response = await fetch('/api/downloader/config');
        const data = await response.json();

        const authList = document.getElementById('authList');
        authList.innerHTML = authConfigs.map(config => {
            const hasAuth = data.auth_status?.[config.key] || false;

            return `
                <div class="auth-item">
                    <div class="auth-item-header">
                        <div class="auth-item-info">
                            <div class="auth-item-platform">${config.platform}</div>
                            <div class="auth-item-downloader">${config.downloader}</div>
                        </div>
                        <div class="auth-status ${hasAuth ? 'active' : 'inactive'}">
                            <div class="auth-status-dot ${hasAuth ? '' : 'inactive'}"></div>
                            <span data-i18n="${hasAuth ? 'authActive' : 'authInactive'}">
                                ${hasAuth ? i18nManager.t('authActive') : i18nManager.t('authInactive')}
                            </span>
                        </div>
                    </div>
                    <div style="display: flex; gap: 8px;">
                        <button class="auth-upload-btn" onclick="uploadAuthFile('${config.key}', '${config.type}')">
                            <span class="material-symbols-outlined" style="font-size: 14px;">upload_file</span>
                            <span data-i18n="authUploadFile">上传文件</span>
                        </button>
                        <button class="auth-upload-btn" onclick="uploadAuthText('${config.key}', '${config.type}')">
                            <span class="material-symbols-outlined" style="font-size: 14px;">edit</span>
                            <span data-i18n="authInput">输入</span>
                        </button>
                        ${hasAuth ? `
                        <button class="auth-delete-btn" onclick="deleteAuth('${config.key}')" data-i18n="authDelete">
                            ${i18nManager.t('authDelete')}
                        </button>
                        ` : ''}
                    </div>
                </div>
            `;
        }).join('');

        i18nManager.updateUI();
    } catch (error) {
        console.error('Failed to load auth status:', error);
    }
}

// 上传认证文件
async function uploadAuthFile(platform, type) {
    const fileInput = document.getElementById('authFileInput');

    // 创建一个 Promise 来处理文件选择
    const content = await new Promise((resolve) => {
        fileInput.onchange = async (e) => {
            const file = e.target.files[0];
            if (!file) {
                resolve(null);
                return;
            }

            const reader = new FileReader();
            reader.onload = (event) => {
                resolve(event.target.result);
            };
            reader.readAsText(file);
        };

        // 触发文件选择
        fileInput.click();
    });

    // 重置 file input
    fileInput.value = '';

    if (!content) {
        return;
    }

    await submitAuth(platform, content);
}

// 手动输入认证信息
async function uploadAuthText(platform, type) {
    const content = prompt(`请输入 ${platform} 的 ${type}:`);

    if (!content || !content.trim()) {
        return;
    }

    await submitAuth(platform, content.trim());
}

// 提交认证信息
async function submitAuth(platform, content) {
    try {
        const response = await fetch(`/api/downloader/credentials/${platform}`, {
            method: 'POST',
            headers: { 'Content-Type': 'text/plain' },
            body: content
        });

        const result = await response.json();

        if (response.ok) {
            alert('认证信息上传成功');
            await loadAuthStatus();
        } else {
            alert(result.error || 'Failed to upload credentials');
        }
    } catch (error) {
        console.error('Failed to upload credentials:', error);
        alert('Failed to upload credentials');
    }
}

// 删除认证信息
async function deleteAuth(platform) {
    if (!confirm('确定要删除认证信息吗？')) {
        return;
    }

    try {
        const response = await fetch(`/api/downloader/credentials/${platform}`, {
            method: 'DELETE'
        });

        const result = await response.json();

        if (response.ok) {
            alert('认证信息已删除');
            await loadAuthStatus();
        } else {
            alert(result.error || 'Failed to delete credentials');
        }
    } catch (error) {
        console.error('Failed to delete credentials:', error);
        alert('Failed to delete credentials');
    }
}

