// 设置页面逻辑
let appState = {
    source_folder: '',
    presets: []
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
    // 初始化文件浏览器(从用户主目录开始)
    await browseDirectory();
}

// 加载应用状态
async function loadAppState() {
    try {
        const response = await fetch('/api/classifier/state');
        appState = await response.json();

        // 如果已经配置了源文件夹,显示它
        if (appState.source_folder) {
            browserState.selectedPath = appState.source_folder;
            document.getElementById('selectedFolderPath').textContent = appState.source_folder;
            document.getElementById('selectedFolderDisplay').style.display = 'block';
            await loadFoldersFromPath(appState.source_folder);
        } else {
            // 如果没有源文件夹,隐藏保存按钮
            document.getElementById('saveBtn').style.display = 'none';
        }

        // 构建预设选择器
        updatePresetSelector();

    } catch (error) {
        console.error('Error loading state:', error);
    }
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
            <div class="category-item" style="${folder.hidden ? 'opacity: 0.5;' : ''}">
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

// 更新预设选择器
function updatePresetSelector() {
    const select = document.getElementById('presetSelect');

    let options = '<option value="">Select a preset...</option>';

    options += appState.presets.map(preset =>
        `<option value="${preset.name}">
            ${preset.name} (${preset.categories.length} folders)
        </option>`
    ).join('');

    select.innerHTML = options;
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

// 应用预设
function applyPreset() {
    const select = document.getElementById('presetSelect');
    const presetName = select.value;

    if (!presetName) {
        alert(i18nManager.t('selectPreset', 'Please select a preset'));
        return;
    }

    const preset = appState.presets.find(p => p.name === presetName);
    if (!preset) return;

    // 将预设中的分类添加到文件夹列表
    preset.categories.forEach(category => {
        if (!folders.some(f => f.name === category)) {
            folders.push({
                name: category,
                hidden: false,
                isNew: true  // 标记为新文件夹
            });
        }
    });

    renderFolders();
    select.value = '';
}


// 保存设置
async function saveSettings() {
    const folderPath = browserState.selectedPath;

    if (!folderPath) {
        alert('请先选择源文件夹');
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
        const response = await fetch('/api/classifier/settings/save', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({
                source_folder: folderPath,
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

// ========== 文件浏览器功能 ==========

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

// 选择当前文件夹作为源文件夹
async function selectCurrentFolder() {
    // 优先使用单击选中的文件夹,否则使用当前所在目录
    const pathToSelect = browserState.selectedItemPath || browserState.currentPath;

    if (!pathToSelect) {
        alert('请先浏览到要选择的文件夹');
        return;
    }

    browserState.selectedPath = pathToSelect;

    // 显示已选择的路径
    document.getElementById('selectedFolderPath').textContent = browserState.selectedPath;
    document.getElementById('selectedFolderDisplay').style.display = 'block';

    // 加载该文件夹下的子文件夹
    await loadFoldersFromPath(browserState.selectedPath);
}

// 从指定路径加载文件夹
async function loadFoldersFromPath(folderPath) {
    try {
        const response = await fetch(`/api/classifier/folders?source_folder=${encodeURIComponent(folderPath)}`);
        if (response.ok) {
            const existingFolders = await response.json();
            // 标记已存在的文件夹
            folders = existingFolders.map(f => ({
                ...f,
                isNew: false  // 已存在的文件夹
            }));
            document.getElementById('foldersSection').style.display = 'block';
            document.getElementById('saveBtn').style.display = 'inline-flex';
            renderFolders();
        }
    } catch (error) {
        console.error('Error loading folders:', error);
    }
}

// 页面加载完成后初始化
document.addEventListener('DOMContentLoaded', init);
