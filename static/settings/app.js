// 设置页面逻辑
let appState = {
    source_folder: '',
    current_preset: '',
    presets: []
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
        const response = await fetch('/api/classifier/state');
        appState = await response.json();

        // 更新界面 - 显示源文件夹
        if (appState.source_folder) {
            document.getElementById('folderInput').value = appState.source_folder;
        }

        // 构建预设选择器
        updatePresetSelector();

        // 显示当前预设的分类
        if (appState.current_preset) {
            const preset = appState.presets.find(p => p.name === appState.current_preset);
            if (preset) {
                document.getElementById('categoriesSetup').style.display = 'block';
                renderCategories(preset.categories);
            }
        }

    } catch (error) {
        console.error('Error loading state:', error);
    }
}

// 更新预设选择器
function updatePresetSelector() {
    const select = document.getElementById('presetSelect');

    let options = '<option value="">Custom (No Preset)</option>';

    options += appState.presets.map(preset =>
        `<option value="${preset.name}" ${preset.name === appState.current_preset ? 'selected' : ''}>
            ${preset.name} (${preset.categories.length} categories)
        </option>`
    ).join('');

    options += '<option value="__new__">+ Create New Preset</option>';

    select.innerHTML = options;
}

// 加载选中的预设
async function loadSelectedPreset() {
    const select = document.getElementById('presetSelect');
    const selectedValue = select.value;

    // 显示分类设置区域
    document.getElementById('categoriesSetup').style.display = 'block';

    if (selectedValue === '__new__') {
        const name = prompt(i18nManager.t('enterPresetName', 'Enter preset name:'));
        if (!name) {
            select.value = appState.current_preset || '';
            return;
        }

        if (appState.presets.some(p => p.name === name)) {
            alert(i18nManager.t('presetExists', 'Preset name already exists'));
            select.value = appState.current_preset || '';
            return;
        }

        // 创建新预设
        const newPreset = {
            name: name,
            categories: []
        };
        appState.presets.push(newPreset);
        appState.current_preset = name;

        await savePresetToServer(name, []);
        updatePresetSelector();
        renderCategories([]);
        return;
    }

    if (selectedValue === '') {
        // Custom - 不关联预设
        appState.current_preset = '';
        renderCategories([]);
        return;
    }

    // 加载选中预设的分类
    const preset = appState.presets.find(p => p.name === selectedValue);
    if (preset) {
        appState.current_preset = selectedValue;
        renderCategories(preset.categories);
    }
}

// 获取当前分类
function getCurrentCategories() {
    const preset = appState.presets.find(p => p.name === appState.current_preset);
    return preset ? preset.categories : [];
}

// 获取快捷键
function getShortcutKey(index) {
    if (index < 9) {
        return (index + 1).toString();
    } else if (index < 35) {
        return String.fromCharCode(97 + (index - 9));
    }
    return null;
}

// 渲染分类列表
function renderCategories(categories) {
    const container = document.getElementById('categoriesList');

    if (categories.length === 0) {
        container.innerHTML = `<div style="text-align: center; color: #a3a3a3; padding: 20px;">${i18nManager.t('noCategoriesYet', 'No categories yet')}</div>`;
        return;
    }

    container.innerHTML = categories.map((category, index) => {
        const shortcut = getShortcutKey(index);
        const shortcutText = shortcut ?
            `<span style="font-family: monospace; font-size: 12px; color: #a3a3a3; margin-right: 8px;">[${shortcut}]</span>` : '';
        return `
            <div class="category-item">
                ${shortcutText}
                <input type="text" value="${category}" onchange="updateCategoryInSetup(${index}, this.value)">
                <button class="delete-btn" onclick="removeCategoryInSetup(${index})">×</button>
            </div>
        `;
    }).join('');
}

// 保存当前配置为预设
async function saveCurrentAsPreset() {
    const categories = getCurrentCategories();

    if (categories.length === 0) {
        alert(i18nManager.t('pleaseAddCategories'));
        return;
    }

    let name = document.getElementById('presetSelect').value;

    if (!name || name === '__new__') {
        name = prompt(i18nManager.t('enterPresetName', 'Enter preset name:'));
        if (!name) return;
    } else {
        if (!confirm(i18nManager.t('updatePreset', {name}))) {
            name = prompt(i18nManager.t('saveAsNewPreset'));
            if (!name) return;
        }
    }

    await savePresetToServer(name, categories);
    alert(i18nManager.t('presetSaved', {name}));
}

// 保存预设到服务器
async function savePresetToServer(name, categories) {
    try {
        const response = await fetch('/api/classifier/preset/save', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({
                name: name,
                categories: categories
            })
        });

        if (response.ok) {
            const data = await response.json();
            appState = data.state;
            updatePresetSelector();
            renderCategories(categories);
            return true;
        }
    } catch (error) {
        console.error('Error saving preset:', error);
    }
    return false;
}

// 删除选中的预设
async function deleteSelectedPreset() {
    const select = document.getElementById('presetSelect');
    const selectedValue = select.value;

    if (!selectedValue || selectedValue === '__new__') {
        alert(i18nManager.t('selectPresetToDelete', 'Please select a preset to delete'));
        return;
    }

    if (!confirm(i18nManager.t('confirmDelete', {name: selectedValue}))) return;

    try {
        const response = await fetch('/api/classifier/preset/delete', {
            method: 'DELETE',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({ name: selectedValue })
        });

        if (response.ok) {
            const data = await response.json();
            appState = data.state;
            updatePresetSelector();

            // 显示第一个预设或清空
            if (appState.presets.length > 0) {
                renderCategories(appState.presets[0].categories);
            } else {
                renderCategories([]);
            }

            alert(i18nManager.t('presetDeleted', {name: selectedValue}));
        }
    } catch (error) {
        console.error('Error deleting preset:', error);
    }
}

// 在设置界面添加分类
function addCategoryInSetup() {
    const input = document.getElementById('newCategoryInput');
    const categoryName = input.value.trim();

    if (!categoryName) return;

    if (appState.current_preset) {
        const preset = appState.presets.find(p => p.name === appState.current_preset);
        if (preset) {
            if (preset.categories.includes(categoryName)) {
                alert(i18nManager.t('categoryExists', 'Category already exists'));
                return;
            }
            preset.categories.push(categoryName);
            input.value = '';
            renderCategories(preset.categories);
            savePresetToServer(appState.current_preset, preset.categories);
        }
    }
}

// 更新分类
function updateCategoryInSetup(index, value) {
    if (!value.trim() || !appState.current_preset) return;

    const preset = appState.presets.find(p => p.name === appState.current_preset);
    if (preset) {
        preset.categories[index] = value.trim();
        savePresetToServer(appState.current_preset, preset.categories);
    }
}

// 删除分类
function removeCategoryInSetup(index) {
    if (!appState.current_preset) return;

    const preset = appState.presets.find(p => p.name === appState.current_preset);
    if (preset) {
        preset.categories.splice(index, 1);
        renderCategories(preset.categories);
        savePresetToServer(appState.current_preset, preset.categories);
    }
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

    try {
        const response = await fetch('/api/classifier/folder', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({
                source_folder: folderPath
            })
        });

        if (response.ok) {
            appState.source_folder = folderPath;
            console.log('Source folder updated to:', folderPath);
            alert(i18nManager.t('folderUpdated', 'Source folder updated successfully!'));
        } else {
            alert(i18nManager.t('failedUpdateFolder', 'Failed to update source folder'));
        }
    } catch (error) {
        console.error('Error:', error);
        alert('Failed to update source folder');
    }
}

// 设置分类
function setupCategories() {
    // 先确保源文件夹已设置
    const folderPath = document.getElementById('folderInput').value.trim();
    if (!folderPath) {
        alert(i18nManager.t('enterSourceFolderFirst', 'Please enter source folder path first'));
        document.getElementById('folderInput').focus();
        return;
    }

    // 显示分类设置
    document.getElementById('categoriesSetup').style.display = 'block';
}

// 页面加载完成后初始化
document.addEventListener('DOMContentLoaded', init);
