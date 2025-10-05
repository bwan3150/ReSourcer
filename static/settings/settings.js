let config = {
    mainFolder: '',
    categories: [],
    hiddenCategories: []
};

const PRESETS = [
    {
        name: 'Art Resources',
        folders: ['Character Design', 'Backgrounds', 'Color Reference', 'Composition', 'Anatomy', 'Lighting']
    },
    {
        name: 'Photography',
        folders: ['Portraits', 'Landscapes', 'Street', 'Architecture', 'Nature', 'Black & White']
    },
    {
        name: 'Design Assets',
        folders: ['UI-UX', 'Icons', 'Patterns', 'Textures', 'Mockups', 'Fonts']
    },
    {
        name: 'Development',
        folders: ['Projects', 'Resources', 'Documentation', 'Assets', 'Libraries', 'Archives']
    }
];

// 初始化
async function init() {
    await loadConfig();
    renderPresets();
    if (config.mainFolder) {
        await loadFolders();
    }
}

// 加载配置
async function loadConfig() {
    try {
        const response = await fetch('/api/settings/config');
        if (response.ok) {
            config = await response.json();
            document.getElementById('folderPath').value = config.mainFolder || '';
        }
    } catch (e) {
        console.error('Failed to load config:', e);
    }
}

// 保存主文件夹
async function saveFolder() {
    const path = document.getElementById('folderPath').value.trim();
    if (!path) {
        alert('Please enter a folder path');
        return;
    }

    try {
        const response = await fetch('/api/settings/folder', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ path })
        });

        if (response.ok) {
            config.mainFolder = path;
            await loadFolders();
            alert('Folder saved successfully');
        } else {
            alert('Failed to save folder');
        }
    } catch (e) {
        alert('Error: ' + e.message);
    }
}

// 加载文件夹列表
async function loadFolders() {
    if (!config.mainFolder) return;

    try {
        const response = await fetch('/api/settings/folders');
        if (response.ok) {
            const data = await response.json();
            config.categories = data.folders || [];
            config.hiddenCategories = data.hidden || [];
            renderFolders();
        }
    } catch (e) {
        console.error('Failed to load folders:', e);
    }
}

// 渲染文件夹列表
function renderFolders() {
    const container = document.getElementById('foldersList');

    if (config.categories.length === 0) {
        container.innerHTML = '<p style="color: #a3a3a3; font-size: 14px;">No subfolders found. Create one above.</p>';
        return;
    }

    container.innerHTML = config.categories.map(folder => {
        const isHidden = config.hiddenCategories.includes(folder);
        return `
            <div class="folder-item ${isHidden ? 'hidden' : ''}">
                <div>
                    <span class="folder-name">${folder}</span>
                    ${isHidden ? '<span class="folder-badge">Hidden</span>' : ''}
                </div>
                <div class="folder-actions">
                    <button class="btn btn-secondary btn-small" onclick="toggleFolder('${folder}')">
                        ${isHidden ? 'Show' : 'Hide'}
                    </button>
                </div>
            </div>
        `;
    }).join('');
}

// 创建新文件夹
async function createFolder() {
    const name = document.getElementById('newFolderName').value.trim();
    if (!name) {
        alert('Please enter a folder name');
        return;
    }

    if (!config.mainFolder) {
        alert('Please set main folder first');
        return;
    }

    try {
        const response = await fetch('/api/settings/folder/create', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ name })
        });

        if (response.ok) {
            document.getElementById('newFolderName').value = '';
            await loadFolders();
        } else {
            alert('Failed to create folder');
        }
    } catch (e) {
        alert('Error: ' + e.message);
    }
}

// 切换文件夹显示/隐藏
async function toggleFolder(name) {
    try {
        const isHidden = config.hiddenCategories.includes(name);
        const response = await fetch('/api/settings/folder/toggle', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ name, hide: !isHidden })
        });

        if (response.ok) {
            await loadFolders();
        }
    } catch (e) {
        alert('Error: ' + e.message);
    }
}

// 渲染预设列表
function renderPresets() {
    const container = document.getElementById('presetsList');
    container.innerHTML = PRESETS.map(preset => `
        <div class="preset-card" onclick="applyPreset('${preset.name}')">
            <h3>${preset.name}</h3>
            <p>${preset.folders.length} folders</p>
        </div>
    `).join('');
}

// 应用预设
async function applyPreset(presetName) {
    if (!config.mainFolder) {
        alert('Please set main folder first');
        return;
    }

    const preset = PRESETS.find(p => p.name === presetName);
    if (!preset) return;

    if (!confirm(`Create ${preset.folders.length} folders for "${presetName}"?`)) {
        return;
    }

    try {
        const response = await fetch('/api/settings/preset/apply', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ folders: preset.folders })
        });

        if (response.ok) {
            await loadFolders();
            alert('Preset applied successfully');
        } else {
            alert('Failed to apply preset');
        }
    } catch (e) {
        alert('Error: ' + e.message);
    }
}

// 页面加载时初始化
init();
