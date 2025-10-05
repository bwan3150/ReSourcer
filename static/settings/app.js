// 设置页面逻辑
let appState = {
    source_folder: '',
    presets: []
};

// 内存中的文件夹列表 (包含已存在的和用户新添加的)
let folders = [];

// 初始化
async function init() {
    // 初始化多语言
    i18nManager.updateUI();
    await loadAppState();
}

// 加载应用状态
async function loadAppState() {
    try {
        const response = await fetch('/api/classifier/state');
        appState = await response.json();

        // 更新界面 - 显示源文件夹
        if (appState.source_folder) {
            document.getElementById('folderInput').value = appState.source_folder;
            await loadFolders();
        }

        // 构建预设选择器
        updatePresetSelector();

    } catch (error) {
        console.error('Error loading state:', error);
    }
}

// 加载文件夹列表
async function loadFolders() {
    const folderPath = document.getElementById('folderInput').value.trim();
    if (!folderPath) return;

    try {
        const response = await fetch(`/api/classifier/folders?source_folder=${encodeURIComponent(folderPath)}`);
        if (response.ok) {
            folders = await response.json();
            document.getElementById('foldersSection').style.display = 'block';
            renderFolders();
        }
    } catch (error) {
        console.error('Error loading folders:', error);
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
            `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
                <path d="M3 3l18 18M10.5 10.5a2 2 0 102.828 2.828M6.5 6.5A8.5 8.5 0 0021 12M3 12a8.5 8.5 0 005.5-5.5" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>
            </svg>` :
            `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
                <path d="M2 12s3-7 10-7 10 7 10 7-3 7-10 7-10-7-10-7z" stroke="currentColor" stroke-width="2"/>
                <circle cx="12" cy="12" r="3" stroke="currentColor" stroke-width="2"/>
            </svg>`;

        return `
            <div class="category-item" style="${folder.hidden ? 'opacity: 0.5;' : ''}">
                <input type="text" value="${folder.name}" onchange="updateFolderName(${index}, this.value)" ${folder.hidden ? 'disabled' : ''}>
                <button class="icon-btn" style="border: none; width: auto;" onclick="toggleFolderVisibility(${index})" title="${folder.hidden ? 'Show' : 'Hide'}">
                    ${visibilityIcon}
                </button>
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
        hidden: false
    });

    input.value = '';
    renderFolders();
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
                hidden: false
            });
        }
    });

    renderFolders();
    select.value = '';
}

// 处理文件夹输入框回车
function handleFolderInputKeydown(event) {
    if (event.key === 'Enter') {
        updateSourceFolder();
    }
}

// 更新源文件夹
async function updateSourceFolder() {
    const folderPath = document.getElementById('folderInput').value.trim();

    if (!folderPath) {
        alert(i18nManager.t('enterFolderPath', 'Please enter a folder path'));
        return;
    }

    appState.source_folder = folderPath;
    await loadFolders();
}

// 保存设置
async function saveSettings() {
    const folderPath = document.getElementById('folderInput').value.trim();

    if (!folderPath) {
        alert(i18nManager.t('enterFolderPath', 'Please enter a folder path'));
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

// 页面加载完成后初始化
document.addEventListener('DOMContentLoaded', init);
