let appState = {
    source_folder: '',
    current_preset: '',
    presets: []
};

let files = [];
let currentIndex = 0;
let processedCount = 0;
let isClassifying = false;
let currentFileExtension = '';

// 初始化
async function init() {
    await loadAppState();
    setupEventListeners();
    
    // 初始化时如果有文件夹路径，显示分类设置区域
    if (appState.source_folder) {
        document.getElementById('categoriesSetup').style.display = 'block';
    }
}

// 设置事件监听器
function setupEventListeners() {
    // 键盘快捷键
    document.addEventListener('keydown', handleKeyPress);
}

// 加载应用状态
async function loadAppState() {
    try {
        const response = await fetch('/api/state');
        appState = await response.json();
        
        // 更新界面
        if (appState.source_folder) {
            document.getElementById('folderInput').value = appState.source_folder;
            document.getElementById('setupBtn').textContent = 'Edit Categories';
        }
        
        // 构建预设选择器
        updatePresetSelector();
        
        // 显示当前预设的分类
        if (appState.current_preset) {
            const preset = appState.presets.find(p => p.name === appState.current_preset);
            if (preset) {
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
        const name = prompt('Enter preset name:');
        if (!name) {
            select.value = appState.current_preset || '';
            return;
        }
        
        if (appState.presets.some(p => p.name === name)) {
            alert('Preset name already exists');
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
        
        if (preset.categories.length > 0 && appState.source_folder) {
            document.getElementById('startBtn').disabled = false;
        }
    }
}

// 获取当前分类
function getCurrentCategories() {
    const preset = appState.presets.find(p => p.name === appState.current_preset);
    return preset ? preset.categories : [];
}

// 渲染分类列表
function renderCategories(categories) {
    const container = document.getElementById('categoriesList');
    
    if (categories.length === 0) {
        container.innerHTML = '<div style="text-align: center; color: #a3a3a3; padding: 20px;">No categories yet</div>';
        document.getElementById('startBtn').disabled = true;
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
    
    if (appState.source_folder) {
        document.getElementById('startBtn').disabled = false;
    }
}

// 保存当前配置为预设
async function saveCurrentAsPreset() {
    const categories = getCurrentCategories();
    
    if (categories.length === 0) {
        alert('Please add some categories first');
        return;
    }
    
    let name = document.getElementById('presetSelect').value;
    
    if (!name || name === '__new__') {
        name = prompt('Enter preset name:');
        if (!name) return;
    } else {
        if (!confirm(`Update preset "${name}" with current categories?`)) {
            name = prompt('Save as new preset with name:');
            if (!name) return;
        }
    }
    
    await savePresetToServer(name, categories);
    alert(`Preset "${name}" saved successfully`);
}

// 保存预设到服务器
async function savePresetToServer(name, categories) {
    try {
        const response = await fetch('/api/preset/save', {
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
        alert('Please select a preset to delete');
        return;
    }
    
    if (!confirm(`Delete preset "${selectedValue}"?`)) return;
    
    try {
        const response = await fetch('/api/preset/delete', {
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
            
            alert(`Preset "${selectedValue}" deleted`);
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
                alert('Category already exists');
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
        const folderPath = document.getElementById('folderInput').value.trim();
        if (folderPath) {
            setSourceFolder();
        }
    }
}

// 设置源文件夹
async function setSourceFolder() {
    const folderPath = document.getElementById('folderInput').value.trim();
    
    if (!folderPath) return;
    
    appState.source_folder = folderPath;
    
    try {
        const response = await fetch('/api/folder', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({
                source_folder: folderPath
            })
        });
        
        if (response.ok) {
            document.getElementById('setupBtn').textContent = 'Edit Categories';
            document.getElementById('categoriesSetup').style.display = 'block';
            
            const categories = getCurrentCategories();
            if (categories.length > 0) {
                document.getElementById('startBtn').disabled = false;
            }
        }
    } catch (error) {
        console.error('Error:', error);
    }
}

// 设置分类
function setupCategories() {
    document.getElementById('categoriesSetup').style.display = 'block';
    
    const folderPath = document.getElementById('folderInput').value.trim();
    if (folderPath && appState.source_folder !== folderPath) {
        setSourceFolder();
    }
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

// 键盘快捷键处理
function handleKeyPress(e) {
    if (document.activeElement.tagName === 'INPUT' || !isClassifying) {
        return;
    }
    
    if (files.length === 0 || currentIndex >= files.length) return;
    
    const categories = getCurrentCategories();
    
    if (e.key >= '1' && e.key <= '9') {
        const index = parseInt(e.key) - 1;
        if (index < categories.length) {
            moveToCategory(categories[index]);
        }
    }
    
    if (e.key >= 'a' && e.key <= 'z') {
        const index = 9 + (e.key.charCodeAt(0) - 97);
        if (index < categories.length) {
            moveToCategory(categories[index]);
        }
    }
    
    if (e.key === 'r' || e.key === 'R') {
        e.preventDefault();
        const renameInput = document.getElementById('renameInput');
        if (renameInput) {
            renameInput.focus();
        }
    }
}

// 开始分类
async function startClassification() {
    const categories = getCurrentCategories();
    
    if (!appState.source_folder || categories.length === 0) {
        if (!appState.source_folder) {
            alert('Please set source folder first');
        } else {
            alert('Please add categories first');
        }
        return;
    }
    
    await loadFiles();
}

// 加载文件列表
async function loadFiles() {
    try {
        const response = await fetch('/api/files');
        files = await response.json();
        
        if (files.length === 0) {
            alert('No files found in the specified folder');
            return;
        }
        
        currentIndex = 0;
        processedCount = 0;
        isClassifying = true;
        
        // 切换到主界面
        document.getElementById('setupContainer').style.display = 'none';
        document.getElementById('mainContainer').style.display = 'block';
        
        // 显示文件夹路径和预设名称
        const presetInfo = appState.current_preset ? ` | ${appState.current_preset}` : '';
        document.getElementById('folderPath').textContent = appState.source_folder + presetInfo;
        
        showCurrentFile();
        updateProgress();
        updateCategoriesGrid();
        
    } catch (error) {
        console.error('Error loading files:', error);
    }
}

// 其他功能函数保持不变...
function getFileExtension(filename) {
    const lastDot = filename.lastIndexOf('.');
    if (lastDot === -1) return '';
    return filename.substring(lastDot);
}

function getFileNameWithoutExtension(filename) {
    const lastDot = filename.lastIndexOf('.');
    if (lastDot === -1) return filename;
    return filename.substring(0, lastDot);
}

function showCurrentFile() {
    const viewer = document.getElementById('mediaViewer');
    
    if (currentIndex >= files.length) {
        isClassifying = false;
        viewer.innerHTML = `
            <div class="complete-message">
                <h1 class="complete-title">Classification Complete</h1>
                <p class="complete-stats">${processedCount} files processed</p>
                <p class="complete-path">${appState.source_folder}</p>
            </div>
        `;
        document.querySelector('.sidebar').style.display = 'none';
        return;
    }
    
    const file = files[currentIndex];
    const encodedPath = encodeURIComponent(file.path);
    
    currentFileExtension = getFileExtension(file.name);
    
    let mediaHtml = '';
    if (file.file_type === 'image') {
        mediaHtml = `<img src="/api/file/${encodedPath}" alt="${file.name}">`;
    } else if (file.file_type === 'video') {
        mediaHtml = `
            <video controls autoplay muted>
                <source src="/api/file/${encodedPath}">
            </video>
        `;
    }
    
    viewer.innerHTML = `
        <div class="media-container">
            ${mediaHtml}
        </div>
        <div class="file-info">
            <div class="file-name">${file.name}</div>
            <div class="file-counter">File ${currentIndex + 1} of ${files.length}</div>
        </div>
        <div class="rename-area">
            <div class="rename-input-group">
                <input type="text" 
                       id="renameInput" 
                       class="rename-input" 
                       placeholder="${getFileNameWithoutExtension(file.name)}"
                       onkeydown="handleRenameKeydown(event)">
                <span class="file-extension">${currentFileExtension}</span>
            </div>
        </div>
    `;
    
    updateCategoriesGrid();
}

function handleRenameKeydown(event) {
    event.stopPropagation();
    const categories = getCurrentCategories();
    if (event.key === 'Enter' && categories.length > 0) {
        moveToCategory(categories[0]);
    }
}

function updateCategoriesGrid() {
    const grid = document.getElementById('categoriesGrid');
    const categories = getCurrentCategories();
    
    let html = '';
    for (let i = 0; i < categories.length; i++) {
        const category = categories[i];
        const shortcut = getShortcutKey(i);
        
        html += `
            <button class="category-btn" onclick="moveToCategory('${category.replace(/'/g, "\\'")}')">
                <span>${category}</span>
                ${shortcut ? `<span class="shortcut-key">${shortcut}</span>` : ''}
            </button>
        `;
    }
    
    grid.innerHTML = html;
}

async function moveToCategory(category) {
    const file = files[currentIndex];
    const renameInput = document.getElementById('renameInput');
    const newName = renameInput ? renameInput.value.trim() : '';
    
    const requestBody = {
        file_path: file.path,
        category: category
    };
    
    if (newName) {
        requestBody.new_name = newName;
    }
    
    try {
        const response = await fetch('/api/move', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify(requestBody)
        });
        
        if (response.ok) {
            processedCount++;
            currentIndex++;
            updateProgress();
            showCurrentFile();
        }
    } catch (error) {
        console.error('Error moving file:', error);
    }
}

async function quickAddNewCategory() {
    const input = document.getElementById('quickAddCategory');
    const categoryName = input.value.trim();
    
    if (!categoryName) return;
    
    const categories = getCurrentCategories();
    if (categories.includes(categoryName)) return;
    
    categories.push(categoryName);
    
    if (appState.current_preset) {
        const preset = appState.presets.find(p => p.name === appState.current_preset);
        if (preset) {
            preset.categories = categories;
            await savePresetToServer(appState.current_preset, categories);
        }
    }
    
    input.value = '';
    updateCategoriesGrid();
}

function updateProgress() {
    const progressText = document.getElementById('progressText');
    const progressFill = document.getElementById('progressFill');
    
    progressText.textContent = `${processedCount} / ${files.length}`;
    const percentage = files.length > 0 ? (processedCount / files.length) * 100 : 0;
    progressFill.style.width = `${percentage}%`;
}

// 页面加载完成后初始化
document.addEventListener('DOMContentLoaded', init);
