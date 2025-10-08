// 设置页面逻辑
let appState = {
    source_folder: '',
    backup_source_folders: []
};

// 内存中的文件夹列表 (包含已存在的和用户新添加的)
let folders = [];

// 文件浏览器状态
let browserState = {
    currentPath: null,
    selectedPath: null,
    selectedItemPath: null, // 单击选中的文件夹路径
    items: []
};

// 初始化
async function init() {
    // 初始化多语言
    i18nManager.updateUI();
    await loadAppState();
}

// 加载应用状态
async function loadAppState() {
    try {
        const response = await fetch('/api/settings/state');
        appState = await response.json();

        // 渲染源文件夹列表
        renderSourceFolders();

        // 如果已经配置了源文件夹,加载分类文件夹
        if (appState.source_folder) {
            await loadFoldersFromPath(appState.source_folder);
        }

    } catch (error) {
        console.error('Error loading state:', error);
    }
}

// 渲染源文件夹列表
function renderSourceFolders() {
    const section = document.getElementById('sourceFoldersSection');
    const container = document.getElementById('sourceFoldersList');

    // 收集所有源文件夹（当前+备用）
    const allSources = [];
    if (appState.source_folder) {
        allSources.push({
            path: appState.source_folder,
            isActive: true
        });
    }
    if (appState.backup_source_folders && appState.backup_source_folders.length > 0) {
        appState.backup_source_folders.forEach(path => {
            allSources.push({
                path: path,
                isActive: false
            });
        });
    }

    // 如果没有源文件夹,隐藏列表区域
    if (allSources.length === 0) {
        section.style.display = 'none';
        return;
    }

    section.style.display = 'block';

    container.innerHTML = allSources.map(source => {
        const activeClass = source.isActive ? 'active' : '';
        const activeBadge = source.isActive ?
            `<span class="source-folder-badge" data-i18n="currentActive">当前</span>` : '';

        return `
            <div class="source-folder-item ${activeClass}">
                ${activeBadge}
                <span class="source-folder-path">${source.path}</span>
                <div class="source-folder-actions">
                    ${!source.isActive ? `
                        <button class="icon-btn" onclick="switchToSourceFolder('${source.path.replace(/'/g, "\\'")}')"
                                data-i18n-title="switchTo" title="切换到此文件夹">
                            <span class="material-symbols-outlined">swap_horiz</span>
                        </button>
                    ` : ''}
                    ${!source.isActive ? `
                        <button class="icon-btn" onclick="removeSourceFolder('${source.path.replace(/'/g, "\\'")}')"
                                data-i18n-title="remove" title="移除">
                            <span class="material-symbols-outlined">delete</span>
                        </button>
                    ` : ''}
                </div>
            </div>
        `;
    }).join('');

    // 更新i18n
    i18nManager.updateUI();
}

// 渲染文件夹列表
function renderFolders() {
    const container = document.getElementById('foldersList');

    if (folders.length === 0) {
        container.innerHTML = `<div style="text-align: center; color: #a3a3a3; padding: 20px;">${i18nManager.t('noFoldersYet', 'No folders yet')}</div>`;
        return;
    }

    container.innerHTML = folders.map((folder, index) => {
        const visibilityIcon = folder.hidden ?
            `<span class="material-symbols-outlined">visibility_off</span>` :
            `<span class="material-symbols-outlined">visibility</span>`;

        // 删除按钮(仅新文件夹显示)
        const deleteBtn = folder.isNew ?
            `<button class="delete-btn" onclick="removeFolder(${index})" title="Delete">×</button>` :
            `<span style="margin-left: 4px; color: #a3a3a3;"><span class="material-symbols-outlined" style="font-size: 18px;">save</span></span>`;

        return `
            <div class="folder-item" style="${folder.hidden ? 'opacity: 0.5;' : ''}">
                <input type="text" value="${folder.name}" onchange="updateFolderName(${index}, this.value)" ${folder.hidden ? 'disabled' : ''}>
                <div style="display: flex; align-items: center; gap: 4px;">
                    <button class="icon-btn" style="border: none; width: auto; padding: 4px;" onclick="toggleFolderVisibility(${index})" title="${folder.hidden ? 'Show' : 'Hide'}">
                        ${visibilityIcon}
                    </button>
                    ${deleteBtn}
                </div>
            </div>
        `;
    }).join('');
}

// 添加文件夹
function addFolder() {
    const input = document.getElementById('newFolderInput');
    const folderName = input.value.trim();

    if (!folderName) return;

    if (folders.some(f => f.name === folderName)) {
        alert(i18nManager.t('folderExists', 'Folder already exists'));
        return;
    }

    folders.push({
        name: folderName,
        hidden: false,
        isNew: true  // 标记为新文件夹
    });

    input.value = '';
    renderFolders();
}

// 删除文件夹(仅新添加的文件夹可删除)
function removeFolder(index) {
    if (folders[index].isNew) {
        folders.splice(index, 1);
        renderFolders();
    }
}

// 更新文件夹名称
function updateFolderName(index, newName) {
    newName = newName.trim();
    if (!newName) return;

    // 检查是否与其他文件夹重名
    if (folders.some((f, i) => i !== index && f.name === newName)) {
        alert(i18nManager.t('folderExists', 'Folder already exists'));
        renderFolders(); // 恢复原名称
        return;
    }

    folders[index].name = newName;
}

// 切换文件夹显示/隐藏
function toggleFolderVisibility(index) {
    folders[index].hidden = !folders[index].hidden;
    renderFolders();
}

// 添加新源文件夹
async function addNewSourceFolder() {
    const folderPath = document.getElementById('sourceFolderInput').value.trim();

    if (!folderPath) {
        alert(i18nManager.t('enterFolderPath'));
        return;
    }

    try {
        // 如果是第一个源文件夹,直接设为当前源
        if (!appState.source_folder) {
            appState.source_folder = folderPath;
            await loadFoldersFromPath(folderPath);
            renderSourceFolders();
            document.getElementById('sourceFolderInput').value = '';
            return;
        }

        // 否则添加到备用列表
        const response = await fetch('/api/settings/sources/add', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({
                folder_path: folderPath
            })
        });

        if (response.ok) {
            // 重新加载状态
            await loadAppState();
            document.getElementById('sourceFolderInput').value = '';
            alert(i18nManager.t('sourceFolderAdded', '源文件夹添加成功'));
        } else {
            const error = await response.json();
            alert(error.error || i18nManager.t('failedAddSourceFolder', '添加源文件夹失败'));
        }
    } catch (error) {
        console.error('Error adding source folder:', error);
        alert(i18nManager.t('failedAddSourceFolder', '添加源文件夹失败'));
    }
}

// 切换到指定源文件夹
async function switchToSourceFolder(folderPath) {
    if (!confirm(i18nManager.t('confirmSwitchSource', `确定要切换到此源文件夹吗?\n${folderPath}`))) {
        return;
    }

    try {
        const response = await fetch('/api/settings/sources/switch', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({
                folder_path: folderPath
            })
        });

        if (response.ok) {
            // 重新加载状态和分类文件夹
            await loadAppState();
            alert(i18nManager.t('sourceFolderSwitched', '已切换源文件夹'));
        } else {
            const error = await response.json();
            alert(error.error || i18nManager.t('failedSwitchSourceFolder', '切换源文件夹失败'));
        }
    } catch (error) {
        console.error('Error switching source folder:', error);
        alert(i18nManager.t('failedSwitchSourceFolder', '切换源文件夹失败'));
    }
}

// 移除源文件夹
async function removeSourceFolder(folderPath) {
    if (!confirm(i18nManager.t('confirmRemoveSource', `确定要移除此源文件夹吗?\n${folderPath}`))) {
        return;
    }

    try {
        const response = await fetch('/api/settings/sources/remove', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({
                folder_path: folderPath
            })
        });

        if (response.ok) {
            // 重新加载状态
            await loadAppState();
            alert(i18nManager.t('sourceFolderRemoved', '已移除源文件夹'));
        } else {
            const error = await response.json();
            alert(error.error || i18nManager.t('failedRemoveSourceFolder', '移除源文件夹失败'));
        }
    } catch (error) {
        console.error('Error removing source folder:', error);
        alert(i18nManager.t('failedRemoveSourceFolder', '移除源文件夹失败'));
    }
}

// 保存完整设置
async function saveSettings() {
    if (!appState.source_folder) {
        alert(i18nManager.t('setSourceFolderFirst', '请先添加源文件夹'));
        return;
    }

    // 收集所有要显示的分类(不包括隐藏的)
    const categories = folders.filter(f => !f.hidden).map(f => f.name);
    const hiddenFolders = folders.filter(f => f.hidden).map(f => f.name);

    if (categories.length === 0) {
        alert(i18nManager.t('needAtLeastOneFolder', 'Please add at least one visible folder'));
        return;
    }

    try {
        const response = await fetch('/api/settings/save', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({
                source_folder: appState.source_folder,
                categories: categories,
                hidden_folders: hiddenFolders
            })
        });

        if (response.ok) {
            alert(i18nManager.t('settingsSaved', 'Settings saved successfully!'));
            window.location.href = '/';
        } else {
            const error = await response.json();
            alert(i18nManager.t('failedSaveSettings', 'Failed to save settings: ') + (error.error || ''));
        }
    } catch (error) {
        console.error('Error saving settings:', error);
        alert(i18nManager.t('failedSaveSettings', 'Failed to save settings'));
    }
}

// ========== 文件浏览器模态弹窗 ==========

// 打开文件浏览器
async function openFileBrowser() {
    document.getElementById('fileBrowserModal').classList.add('active');
    document.body.classList.add('modal-open');  // 防止背景滚动

    // 如果已有源文件夹,从该路径开始,否则从用户主目录开始
    const startPath = document.getElementById('sourceFolderInput').value.trim() || null;
    await browseDirectory(startPath);
}

// 关闭文件浏览器
function closeFileBrowser() {
    document.getElementById('fileBrowserModal').classList.remove('active');
    document.body.classList.remove('modal-open');  // 恢复背景滚动
}

// 浏览目录
async function browseDirectory(path = null) {
    try {
        const response = await fetch('/api/filesystem/browse', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({ path })
        });

        if (response.ok) {
            const data = await response.json();
            browserState.currentPath = data.current_path;
            browserState.items = data.items;
            browserState.parentPath = data.parent_path;
            // 切换目录时清除选中的项
            browserState.selectedItemPath = null;

            renderBreadcrumb();
            renderFileList();
        } else {
            const error = await response.json();
            alert('无法浏览目录: ' + (error.error || ''));
        }
    } catch (error) {
        console.error('Error browsing directory:', error);
        alert('无法浏览目录');
    }
}

// 渲染面包屑导航
function renderBreadcrumb() {
    const breadcrumb = document.getElementById('breadcrumb');

    if (!browserState.currentPath) {
        breadcrumb.innerHTML = '';
        return;
    }

    // 分割路径
    const parts = browserState.currentPath.split(/[/\\]/).filter(p => p);

    let html = '';
    let currentPath = '';

    // 根目录
    const isWindows = browserState.currentPath.includes('\\') || /^[A-Z]:/.test(browserState.currentPath);
    if (isWindows) {
        // Windows路径
        const drive = parts[0];
        currentPath = drive;
        html += `<span class="breadcrumb-item" onclick="browseDirectory('${currentPath}\\\\')">${drive}</span>`;

        for (let i = 1; i < parts.length; i++) {
            html += '<span class="breadcrumb-separator">/</span>';
            currentPath += '\\\\' + parts[i];
            html += `<span class="breadcrumb-item" onclick="browseDirectory('${currentPath}')">${parts[i]}</span>`;
        }
    } else {
        // Unix/Mac路径 - "/"只在最前面显示一次,可点击跳转到根目录
        html += `<span class="breadcrumb-item" onclick="browseDirectory('/')">/</span>`;

        for (let i = 0; i < parts.length; i++) {
            html += '<span class="breadcrumb-separator">/</span>';
            currentPath += '/' + parts[i];
            html += `<span class="breadcrumb-item" onclick="browseDirectory('${currentPath}')">${parts[i]}</span>`;
        }
    }

    breadcrumb.innerHTML = html;
}

// 渲染文件列表
function renderFileList() {
    const fileList = document.getElementById('fileList');

    if (browserState.items.length === 0) {
        fileList.innerHTML = '<div class="loading">此目录为空</div>';
        return;
    }

    let html = '';

    // 添加"返回上一级"选项
    if (browserState.parentPath) {
        html += `
            <div class="file-item" onclick="browseDirectory('${browserState.parentPath.replace(/\\/g, '\\\\')}')">
                <span class="material-symbols-outlined file-icon">arrow_upward</span>
                <span class="file-name">..</span>
            </div>
        `;
    }

    // 渲染文件和文件夹
    browserState.items.forEach((item, index) => {
        const icon = item.is_directory ? 'folder' : 'description';
        const iconClass = item.is_directory ? 'file-icon folder' : 'file-icon';
        const itemId = `item-${index}`;

        if (item.is_directory) {
            // 文件夹:单击选中,双击打开
            html += `
                <div class="file-item" id="${itemId}"
                     onclick="selectFileItem('${item.path.replace(/\\/g, '\\\\').replace(/'/g, "\\'")}', '${itemId}')"
                     ondblclick="browseDirectory('${item.path.replace(/\\/g, '\\\\').replace(/'/g, "\\'")}')">
                    <span class="material-symbols-outlined ${iconClass}">${icon}</span>
                    <span class="file-name">${item.name}</span>
                </div>
            `;
        } else {
            // 文件:置灰,不可操作
            html += `
                <div class="file-item" style="opacity: 0.5; cursor: default;">
                    <span class="material-symbols-outlined ${iconClass}">${icon}</span>
                    <span class="file-name">${item.name}</span>
                </div>
            `;
        }
    });

    fileList.innerHTML = html;
}

// 选中文件夹项
function selectFileItem(path, itemId) {
    // 清除之前的选中状态
    document.querySelectorAll('.file-item').forEach(el => {
        el.classList.remove('selected');
    });

    // 设置新的选中状态
    const item = document.getElementById(itemId);
    if (item) {
        item.classList.add('selected');
    }

    // 保存选中的路径
    browserState.selectedItemPath = path;
}

// 创建新文件夹
async function createNewFolder() {
    const input = document.getElementById('newFolderName');
    const folderName = input.value.trim();

    if (!folderName) {
        alert('请输入文件夹名称');
        return;
    }

    if (!browserState.currentPath) {
        alert('请先选择一个位置');
        return;
    }

    try {
        const response = await fetch('/api/filesystem/create', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({
                parent_path: browserState.currentPath,
                directory_name: folderName
            })
        });

        if (response.ok) {
            input.value = '';
            // 刷新当前目录
            await browseDirectory(browserState.currentPath);
        } else {
            const error = await response.json();
            alert('无法创建文件夹: ' + (error.error || ''));
        }
    } catch (error) {
        console.error('Error creating folder:', error);
        alert('无法创建文件夹');
    }
}

// 选择当前文件夹
function selectCurrentFolder() {
    // 优先使用单击选中的文件夹,否则使用当前所在目录
    const pathToSelect = browserState.selectedItemPath || browserState.currentPath;

    if (!pathToSelect) {
        alert(i18nManager.t('pleaseSelectFolder', '请先选择文件夹'));
        return;
    }

    // 设置到输入框
    document.getElementById('sourceFolderInput').value = pathToSelect;

    // 关闭模态窗口
    closeFileBrowser();
}

// 从指定路径加载文件夹
async function loadFoldersFromPath(folderPath) {
    try {
        const response = await fetch(`/api/settings/folders?source_folder=${encodeURIComponent(folderPath)}`);
        if (response.ok) {
            const existingFolders = await response.json();
            // 标记已存在的文件夹
            folders = existingFolders.map(f => ({
                ...f,
                isNew: false  // 已存在的文件夹
            }));
            // 显示分类文件夹部分和保存设置按钮
            document.getElementById('foldersSection').style.display = 'block';
            document.getElementById('saveSettingsSection').style.display = 'block';
            renderFolders();
        }
    } catch (error) {
        console.error('Error loading folders:', error);
    }
}

// 页面加载完成后初始化
document.addEventListener('DOMContentLoaded', init);
