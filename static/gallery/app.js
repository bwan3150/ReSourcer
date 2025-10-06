// Gallery 应用逻辑

let currentFolder = null;
let currentFiles = [];
let currentFileIndex = 0;
let videoElement = null;
let allFolders = []; // 存储所有文件夹

// 页面加载完成后初始化
window.addEventListener('load', async () => {
    i18nManager.updateUI();
    await loadFolders();
});

// 加载文件夹列表
async function loadFolders() {
    try {
        const response = await fetch('/api/gallery/folders');
        const data = await response.json();

        allFolders = data.folders; // 保存所有文件夹
        const folderList = document.getElementById('folderList');
        const folderDropdown = document.getElementById('folderDropdown');

        folderList.innerHTML = '';
        folderDropdown.innerHTML = '';

        data.folders.forEach((folder, index) => {
            // 翻译文件夹名称
            const displayName = folder.is_source ? i18nManager.t('sourceFolder') : folder.name;

            // 侧边栏项
            const folderItem = document.createElement('div');
            folderItem.className = 'folder-item' + (index === 0 ? ' active' : '');
            folderItem.onclick = () => selectFolder(folder, folderItem, displayName);

            folderItem.innerHTML = `
                <div class="folder-info">
                    <span class="material-symbols-outlined">${folder.is_source ? 'source' : 'folder'}</span>
                    <span class="folder-name">${displayName}</span>
                </div>
                <span class="folder-count">${folder.file_count}</span>
            `;

            folderList.appendChild(folderItem);

            // 下拉菜单项
            const dropdownItem = document.createElement('div');
            dropdownItem.className = 'folder-dropdown-item' + (index === 0 ? ' active' : '');
            dropdownItem.onclick = () => selectFolderFromDropdown(folder, index, displayName);

            dropdownItem.innerHTML = `
                <div class="folder-dropdown-info">
                    <span class="material-symbols-outlined">${folder.is_source ? 'source' : 'folder'}</span>
                    <span class="folder-dropdown-name">${displayName}</span>
                </div>
                <span class="folder-dropdown-count">${folder.file_count}</span>
            `;

            folderDropdown.appendChild(dropdownItem);
        });

        // 默认选择第一个文件夹
        if (data.folders.length > 0) {
            currentFolder = data.folders[0];
            const displayName = data.folders[0].is_source ? i18nManager.t('sourceFolder') : data.folders[0].name;
            document.getElementById('currentFolderName').textContent = displayName;
            await loadFiles(data.folders[0].path);
        }
    } catch (error) {
        console.error('Failed to load folders:', error);
    }
}

// 选择文件夹
async function selectFolder(folder, element, displayName) {
    // 更新选中状态
    document.querySelectorAll('.folder-item').forEach(item => {
        item.classList.remove('active');
    });
    element.classList.add('active');

    currentFolder = folder;
    document.getElementById('currentFolderName').textContent = displayName;

    // 检查预览是否已打开
    const inlinePreview = document.getElementById('inlinePreview');
    const isPreviewOpen = inlinePreview.style.display === 'flex';

    await loadFiles(folder.path);

    // 如果预览已打开且有文件,自动打开第一个文件
    if (isPreviewOpen && currentFiles.length > 0) {
        openPreview(0);
    }
}

// 加载文件列表
async function loadFiles(folderPath) {
    try {
        const response = await fetch(`/api/gallery/files?folder=${encodeURIComponent(folderPath)}`);
        const data = await response.json();

        currentFiles = data.files;

        // 更新标题和文件数
        document.getElementById('currentFolderName').textContent = currentFolder.name;
        const fileCountText = data.files.length === 1 ? i18nManager.t('file') : i18nManager.t('files');
        document.getElementById('fileCount').textContent = `${data.files.length} ${fileCountText}`;

        const galleryGrid = document.getElementById('galleryGrid');
        const emptyState = document.getElementById('emptyState');

        if (data.files.length === 0) {
            galleryGrid.style.display = 'none';
            emptyState.style.display = 'flex';
            return;
        }

        galleryGrid.style.display = 'grid';
        emptyState.style.display = 'none';
        galleryGrid.innerHTML = '';

        data.files.forEach((file, index) => {
            const item = document.createElement('div');
            item.className = 'gallery-item';
            item.onclick = () => openPreview(index);

            if (file.file_type === 'image') {
                item.innerHTML = `
                    <img src="/api/classifier/file/${encodeURIComponent(file.path)}" alt="${file.name}">
                    <div class="file-type-badge">${file.extension}</div>
                `;
            } else if (file.file_type === 'video' || file.file_type === 'gif') {
                item.innerHTML = `
                    <video src="/api/classifier/file/${encodeURIComponent(file.path)}" preload="metadata"></video>
                    <div class="file-type-badge">${file.extension}</div>
                `;
            } else {
                // 其他文件显示图标
                const iconName = getFileIcon(file.extension);
                item.innerHTML = `
                    <div class="file-icon">
                        <span class="material-symbols-outlined">${iconName}</span>
                        <div class="file-icon-name">${file.name}</div>
                    </div>
                    <div class="file-type-badge">${file.extension}</div>
                `;
            }

            galleryGrid.appendChild(item);
        });
    } catch (error) {
        console.error('Failed to load files:', error);
    }
}

// 根据扩展名获取文件图标
function getFileIcon(extension) {
    const iconMap = {
        '.zip': 'folder_zip',
        '.rar': 'folder_zip',
        '.7z': 'folder_zip',
        '.pdf': 'picture_as_pdf',
        '.doc': 'description',
        '.docx': 'description',
        '.txt': 'description',
        '.md': 'description',
        default: 'insert_drive_file'
    };
    return iconMap[extension] || iconMap.default;
}

// 打开预览（内嵌式）
function openPreview(index) {
    currentFileIndex = index;
    updateInlinePreview();
    document.getElementById('inlinePreview').style.display = 'flex';
}

// 更新内嵌预览内容
function updateInlinePreview() {
    const file = currentFiles[currentFileIndex];
    const media = document.getElementById('previewMedia');
    const fileName = document.getElementById('previewFileNameInline');
    const counter = document.getElementById('previewCounter');
    const videoControls = document.getElementById('videoControlsInline');

    fileName.textContent = file.name;
    counter.textContent = `${currentFileIndex + 1} / ${currentFiles.length}`;

    if (file.file_type === 'image' || file.file_type === 'gif') {
        media.innerHTML = `<img src="/api/classifier/file/${encodeURIComponent(file.path)}" alt="${file.name}">`;
        videoControls.style.display = 'none';
    } else if (file.file_type === 'video') {
        media.innerHTML = `<video id="previewVideoInline" src="/api/classifier/file/${encodeURIComponent(file.path)}" autoplay onclick="togglePlayPauseInline()"></video>`;
        videoElement = document.getElementById('previewVideoInline');
        videoControls.style.display = 'flex';
        setupVideoControlsInline();
    } else {
        const iconName = getFileIcon(file.extension);
        media.innerHTML = `<div class="file-icon"><span class="material-symbols-outlined">${iconName}</span><p>${file.name}</p></div>`;
        videoControls.style.display = 'none';
    }
}

// 左右切换预览
function navigatePreview(direction) {
    currentFileIndex += direction;

    // 循环切换
    if (currentFileIndex < 0) {
        currentFileIndex = currentFiles.length - 1;
    } else if (currentFileIndex >= currentFiles.length) {
        currentFileIndex = 0;
    }

    updateInlinePreview();
}

// 关闭内嵌预览
function closeInlinePreview() {
    document.getElementById('inlinePreview').style.display = 'none';
    if (videoElement) {
        videoElement.pause();
        videoElement = null;
    }
}

// 关闭预览
function closePreview() {
    document.getElementById('previewModal').style.display = 'none';
    if (videoElement) {
        videoElement.pause();
        videoElement = null;
    }
}

// 设置视频控制
function setupVideoControls() {
    const video = videoElement;
    const playPauseBtn = document.getElementById('playPauseBtn');
    const progressBar = document.getElementById('progressBar');
    const timeDisplay = document.getElementById('timeDisplay');

    video.addEventListener('timeupdate', () => {
        const progress = (video.currentTime / video.duration) * 100;
        progressBar.value = progress;

        const current = formatTime(video.currentTime);
        const total = formatTime(video.duration);
        timeDisplay.textContent = `${current} / ${total}`;
    });

    video.addEventListener('play', () => {
        playPauseBtn.innerHTML = '<span class="material-symbols-outlined">pause</span>';
    });

    video.addEventListener('pause', () => {
        playPauseBtn.innerHTML = '<span class="material-symbols-outlined">play_arrow</span>';
    });
}

// 播放/暂停切换
function togglePlayPause() {
    if (videoElement) {
        if (videoElement.paused) {
            videoElement.play();
        } else {
            videoElement.pause();
        }
    }
}

// 进度条跳转
function seekVideo(value) {
    if (videoElement) {
        const time = (value / 100) * videoElement.duration;
        videoElement.currentTime = time;
    }
}

// 静音切换
function toggleMute() {
    if (videoElement) {
        videoElement.muted = !videoElement.muted;
        const muteBtn = document.getElementById('muteBtn');
        muteBtn.innerHTML = videoElement.muted
            ? '<span class="material-symbols-outlined">volume_off</span>'
            : '<span class="material-symbols-outlined">volume_up</span>';
    }
}

// 格式化时间
function formatTime(seconds) {
    if (isNaN(seconds)) return '0:00';
    const mins = Math.floor(seconds / 60);
    const secs = Math.floor(seconds % 60);
    return `${mins}:${secs.toString().padStart(2, '0')}`;
}

// 设置内嵌视频控制
function setupVideoControlsInline() {
    const video = videoElement;
    const playPauseBtn = document.getElementById('playPauseBtnInline');
    const progressBar = document.getElementById('progressBarInline');
    const timeDisplay = document.getElementById('timeDisplayInline');

    video.addEventListener('timeupdate', () => {
        const progress = (video.currentTime / video.duration) * 100;
        progressBar.value = progress;

        const current = formatTime(video.currentTime);
        const total = formatTime(video.duration);
        timeDisplay.textContent = `${current} / ${total}`;
    });

    video.addEventListener('play', () => {
        playPauseBtn.innerHTML = '<span class="material-symbols-outlined">pause</span>';
    });

    video.addEventListener('pause', () => {
        playPauseBtn.innerHTML = '<span class="material-symbols-outlined">play_arrow</span>';
    });
}

// 内嵌视频播放/暂停
function togglePlayPauseInline() {
    if (videoElement) {
        if (videoElement.paused) {
            videoElement.play();
        } else {
            videoElement.pause();
        }
    }
}

// 内嵌视频进度跳转
function seekVideoInline(value) {
    if (videoElement) {
        const time = (value / 100) * videoElement.duration;
        videoElement.currentTime = time;
    }
}

// 内嵌视频静音切换
function toggleMuteInline() {
    if (videoElement) {
        videoElement.muted = !videoElement.muted;
        const muteBtn = document.getElementById('muteBtnInline');
        muteBtn.innerHTML = videoElement.muted
            ? '<span class="material-symbols-outlined">volume_off</span>'
            : '<span class="material-symbols-outlined">volume_up</span>';
    }
}

// 显示文件信息
function showFileInfo() {
    const file = currentFiles[currentFileIndex];
    const modal = document.getElementById('infoModal');
    const content = document.getElementById('infoContent');

    content.innerHTML = `
        <div class="info-row">
            <div class="info-label" data-i18n="fileName">文件名</div>
            <div class="info-value">${file.name}</div>
        </div>
        <div class="info-row">
            <div class="info-label" data-i18n="fileType">类型</div>
            <div class="info-value">${file.extension.toUpperCase()}</div>
        </div>
        <div class="info-row">
            <div class="info-label" data-i18n="fileSize">大小</div>
            <div class="info-value">${formatFileSize(file.size)}</div>
        </div>
        <div class="info-row">
            <div class="info-label" data-i18n="modified">修改时间</div>
            <div class="info-value">${file.modified}</div>
        </div>
        ${file.width && file.height ? `
        <div class="info-row">
            <div class="info-label" data-i18n="dimensions">尺寸</div>
            <div class="info-value">${file.width} × ${file.height}</div>
        </div>
        ` : ''}
        ${file.duration ? `
        <div class="info-row">
            <div class="info-label" data-i18n="duration">时长</div>
            <div class="info-value">${formatTime(file.duration)}</div>
        </div>
        ` : ''}
    `;

    modal.style.display = 'block';
}

// 关闭文件信息
function closeFileInfo() {
    document.getElementById('infoModal').style.display = 'none';
}

// 格式化文件大小
function formatFileSize(bytes) {
    if (bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
}

// 从下拉菜单选择文件夹
async function selectFolderFromDropdown(folder, index, displayName) {
    // 更新侧边栏选中状态
    document.querySelectorAll('.folder-item').forEach((item, i) => {
        item.classList.toggle('active', i === index);
    });

    // 更新下拉菜单选中状态
    document.querySelectorAll('.folder-dropdown-item').forEach((item, i) => {
        item.classList.toggle('active', i === index);
    });

    currentFolder = folder;
    document.getElementById('currentFolderName').textContent = displayName;

    // 检查预览是否已打开
    const inlinePreview = document.getElementById('inlinePreview');
    const isPreviewOpen = inlinePreview.style.display === 'flex';

    await loadFiles(folder.path);

    // 如果预览已打开且有文件,自动打开第一个文件
    if (isPreviewOpen && currentFiles.length > 0) {
        openPreview(0);
    }

    // 关闭下拉菜单
    toggleFolderDropdown();
}

// 切换侧边栏
function toggleSidebar() {
    const sidebar = document.getElementById('sidebar');
    const overlay = document.getElementById('sidebarOverlay');

    // 桌面端和移动端使用不同的类
    if (window.innerWidth > 768) {
        // 桌面端：使用 hidden 类
        sidebar.classList.toggle('hidden');
    } else {
        // 移动端：使用 active 类和遮罩
        sidebar.classList.toggle('active');
        overlay.classList.toggle('active');
    }
}

// 切换文件夹下拉菜单
function toggleFolderDropdown() {
    const dropdown = document.getElementById('folderDropdown');
    const selector = document.querySelector('.folder-selector');

    dropdown.classList.toggle('active');
    selector.classList.toggle('active');
}

// 点击外部关闭下拉菜单
document.addEventListener('click', (e) => {
    const dropdown = document.getElementById('folderDropdown');
    const selector = document.querySelector('.folder-selector');

    if (dropdown && dropdown.classList.contains('active')) {
        if (!selector.contains(e.target) && !dropdown.contains(e.target)) {
            dropdown.classList.remove('active');
            selector.classList.remove('active');
        }
    }
});

// 键盘事件处理
document.addEventListener('keydown', (e) => {
    const inlinePreview = document.getElementById('inlinePreview');
    const infoModal = document.getElementById('infoModal');
    const folderDropdown = document.getElementById('folderDropdown');

    if (e.key === 'Escape') {
        if (infoModal.style.display === 'block') {
            closeFileInfo();
        } else if (inlinePreview.style.display === 'flex') {
            closeInlinePreview();
        } else if (document.getElementById('previewModal').style.display === 'block') {
            closePreview();
        } else if (folderDropdown.classList.contains('active')) {
            toggleFolderDropdown();
        }
    } else if (inlinePreview.style.display === 'flex') {
        // 内嵌预览打开时，左右箭头切换
        if (e.key === 'ArrowLeft') {
            navigatePreview(-1);
        } else if (e.key === 'ArrowRight') {
            navigatePreview(1);
        }
    }
});
