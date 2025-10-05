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

// 添加历史记录栈
let operationHistory = [];

// 初始化
async function init() {
    // 初始化多语言
    i18nManager.updateUI();

    await loadAppState();
    setupEventListeners();

    // 直接开始分类
    await startClassification();
}

// 设置事件监听器
function setupEventListeners() {
    // 键盘快捷键
    document.addEventListener('keydown', handleKeyPress);
}

// 加载应用状态
async function loadAppState() {
    try {
        const response = await fetch('/api/classifier/state');
        appState = await response.json();
    } catch (error) {
        console.error('Error loading state:', error);
    }
}


// 当前分类列表(从文件夹加载)
let currentCategories = [];

// 加载分类列表
async function loadCategories() {
    if (!appState.source_folder) {
        currentCategories = [];
        return;
    }

    try {
        const response = await fetch(`/api/classifier/folders?source_folder=${encodeURIComponent(appState.source_folder)}`);
        if (response.ok) {
            const folders = await response.json();
            // 只保存未隐藏的文件夹
            currentCategories = folders.filter(f => !f.hidden).map(f => f.name);
        }
    } catch (error) {
        console.error('Error loading categories:', error);
        currentCategories = [];
    }
}

// 获取当前分类
function getCurrentCategories() {
    return currentCategories;
}

// 渲染分类列表
function renderCategories(categories) {
    const container = document.getElementById('categoriesList');
    
    if (categories.length === 0) {
        container.innerHTML = `<div style="text-align: center; color: #a3a3a3; padding: 20px;">${i18nManager.t('noCategoriesYet', 'No categories yet')}</div>`;
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

// 这些函数已移除，因为现在使用基于文件夹的系统，不再使用预设

// 处理文件夹输入框回车
function handleFolderInputKeydown(event) {
    if (event.key === 'Enter') {
        updateSourceFolder();
    }
}

// 更新源文件夹（通过勾号按钮或回车键）
async function updateSourceFolder() {
    const folderPath = document.getElementById('folderInput').value.trim();
    if (folderPath) {
        setSourceFolder();
    }
}

// 设置源文件夹
async function setSourceFolder() {
    const folderPath = document.getElementById('folderInput').value.trim();
    
    if (!folderPath) {
        alert(i18nManager.t('enterFolderPath', 'Please enter a folder path'));
        return;
    }
    
    // 如果路径改变了，更新它
    if (folderPath !== appState.source_folder) {
        appState.source_folder = folderPath;
        
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
                console.log('Source folder updated to:', folderPath);
            } else {
                alert(i18nManager.t('failedUpdateFolder', 'Failed to update source folder'));
                return;
            }
        } catch (error) {
            console.error('Error:', error);
            alert('Failed to update source folder');
            return;
        }
    }
    
    // 显示分类设置区域
    document.getElementById('categoriesSetup').style.display = 'block';
    document.getElementById('setupBtn').textContent = i18nManager.t('editCategories');
    
    const categories = getCurrentCategories();
    if (categories.length > 0) {
        document.getElementById('startBtn').disabled = false;
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
    
    // 如果路径变了，先更新
    if (folderPath !== appState.source_folder) {
        setSourceFolder();
    } else {
        // 直接显示分类设置
        document.getElementById('categoriesSetup').style.display = 'block';
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
    
    // 撤销快捷键 - Cmd+Z 或 Ctrl+Z
    if ((e.metaKey || e.ctrlKey) && e.key === 'z') {
        e.preventDefault();
        undoLastOperation();
        return;
    }
    
    // U 键也可以撤销
    if (e.key === 'u' || e.key === 'U') {
        e.preventDefault();
        undoLastOperation();
        return;
    }
    
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

// 撤销上一步操作
async function undoLastOperation() {
    if (operationHistory.length === 0) {
        console.log('No operation to undo');
        return;
    }
    
    const lastOp = operationHistory.pop();
    
    try {
        // 移回原位置
        const response = await fetch('/api/classifier/move', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({
                file_path: lastOp.newPath,
                category: '',  // 移回源文件夹根目录
                new_name: lastOp.originalName
            })
        });
        
        if (response.ok) {
            // 恢复文件到列表
            files.splice(lastOp.fileIndex, 0, lastOp.file);
            
            // 调整索引
            if (currentIndex > lastOp.fileIndex) {
                currentIndex = lastOp.fileIndex;
            }
            
            processedCount--;
            
            // 更新显示
            showCurrentFile();
            updateProgress();
            updateUndoButton();
            
            console.log(`Undone: ${lastOp.file.name} from ${lastOp.category}`);
        } else {
            // 如果撤销失败，把操作放回历史
            operationHistory.push(lastOp);
            alert(i18nManager.t('failedUndoMoved', 'Failed to undo operation. The file might have been manually moved.'));
        }
    } catch (error) {
        console.error('Error undoing operation:', error);
        operationHistory.push(lastOp);
        alert(i18nManager.t('failedUndo', 'Failed to undo operation'));
    }
}

// 更新撤销按钮和历史记录显示
function updateUndoButton() {
    const undoBtn = document.getElementById('undoBtn');
    const recentHistory = document.getElementById('recentHistory');
    
    if (undoBtn) {
        if (operationHistory.length > 0) {
            undoBtn.style.display = 'inline-flex';
            const undoText = undoBtn.querySelector('span:first-child');
            if (undoText) {
                undoText.textContent = `${i18nManager.t('undo')} (${operationHistory.length})`;
            }
        } else {
            undoBtn.style.display = 'none';
        }
    }
    
    // 更新历史记录显示
    if (recentHistory) {
        const existingItems = recentHistory.querySelectorAll('.history-item');
        
        // 获取最近3次操作
        const recentOps = operationHistory.slice(-3);
        
        // 获取上次的类别列表（用于判断内容是否变化）
        const lastCategories = recentHistory.dataset.lastCategories ? 
                              JSON.parse(recentHistory.dataset.lastCategories) : [];
        const currentCategories = recentOps.map(op => op.category);
        
        // 判断是新增还是撤销
        const isAdding = operationHistory.length > 0 && 
                        (!recentHistory.dataset.lastCount || 
                         parseInt(recentHistory.dataset.lastCount) < operationHistory.length);
        const isRemoving = recentHistory.dataset.lastCount && 
                          parseInt(recentHistory.dataset.lastCount) > operationHistory.length;
        
        // 判断内容是否有变化（用于处理超过3个的情况）
        const contentChanged = JSON.stringify(lastCategories) !== JSON.stringify(currentCategories);
        
        // 保存当前状态
        recentHistory.dataset.lastCount = operationHistory.length.toString();
        recentHistory.dataset.lastCategories = JSON.stringify(currentCategories);
        
        if (isAdding || (contentChanged && operationHistory.length > 0 && !isRemoving)) {
            // 新增操作或内容变化，添加向上滑入动画
            recentHistory.innerHTML = '';
            
            // 从旧到新显示（最旧的在顶部，最新的在底部）
            recentOps.forEach((op, index) => {
                const historyItem = document.createElement('div');
                // index=0是最旧的(倒数第三)，index=2是最新的(倒数第一)
                historyItem.className = `history-item history-item-${index + 1} slide-up`;
                historyItem.textContent = `→ ${op.category}`;
                
                recentHistory.appendChild(historyItem);
            });
        } else if (isRemoving && recentOps.length > 0) {
            // 撤销操作，添加向下滑出动画
            const lastItem = existingItems[existingItems.length - 1];
            if (lastItem) {
                lastItem.classList.add('slide-down');
                // 动画结束后重新渲染列表
                setTimeout(() => {
                    recentHistory.innerHTML = '';
                    recentOps.forEach((op, index) => {
                        const historyItem = document.createElement('div');
                        historyItem.className = `history-item history-item-${index + 1}`;
                        historyItem.textContent = `→ ${op.category}`;
                        recentHistory.appendChild(historyItem);
                    });
                }, 300); // 与slide-down动画时长一致
            }
        } else if (isRemoving && recentOps.length === 0) {
            // 如果撤销到没有历史记录，全部向下滑出
            existingItems.forEach((item, index) => {
                item.classList.add('slide-down');
                item.style.animationDelay = `${index * 0.05}s`;
            });
            // 动画结束后清空
            setTimeout(() => {
                recentHistory.innerHTML = '';
            }, 400);
        } else if (recentOps.length === 0) {
            // 清空状态
            recentHistory.innerHTML = '';
        }
    }
}

// 开始分类
async function startClassification() {
    // 加载分类列表
    await loadCategories();

    const categories = getCurrentCategories();

    if (!appState.source_folder || categories.length === 0) {
        // 如果没有配置,显示提示并跳转到设置页面
        if (!appState.source_folder) {
            alert(i18nManager.t('setSourceFolderFirst', 'Please go to Settings to configure source folder first'));
        } else {
            alert(i18nManager.t('pleaseAddCategories', 'Please go to Settings to configure categories first'));
        }
        window.location.href = '/settings/';
        return;
    }

    // 清空历史记录
    operationHistory = [];
    updateUndoButton();  // 更新UI显示

    await loadFiles();
}

// 加载文件列表
async function loadFiles() {
    try {
        const response = await fetch('/api/classifier/files');
        files = await response.json();
        
        if (files.length === 0) {
            alert(i18nManager.t('noFilesFound', 'No supported files found in: {folder}').replace('{folder}', appState.source_folder));
            return;
        }
        
        currentIndex = 0;
        processedCount = 0;
        isClassifying = true;

        // 显示文件夹路径
        document.getElementById('folderPath').textContent = appState.source_folder;
        
        showCurrentFile();
        updateProgress();
        updateCategoriesGrid();
        updateUndoButton();
        
    } catch (error) {
        console.error('Error loading files:', error);
        alert(i18nManager.t('errorLoadingFiles', 'Error loading files from: {folder}').replace('{folder}', appState.source_folder));
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
                <h1 class="complete-title">${i18nManager.t('allDone')}</h1>
                <p class="complete-stats">${i18nManager.t('filesProcessed', {count: processedCount})}</p>
                <p class="complete-path">${i18nManager.t('outputFolder')} ${appState.source_folder}</p>
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
        mediaHtml = `<img src="/api/classifier/file/${encodedPath}" alt="${file.name}">`;
    } else if (file.file_type === 'video') {
        mediaHtml = `
            <video controls autoplay muted>
                <source src="/api/classifier/file/${encodedPath}">
            </video>
        `;
    }
    
    viewer.innerHTML = `
        <div class="media-container">
            ${mediaHtml}
        </div>
        <div class="file-info">
            <div class="file-name">${file.name}</div>
            <div class="file-counter">${i18nManager.t('fileCounter', {current: currentIndex + 1, total: files.length})}</div>
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
    updateUndoButton();
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
        const response = await fetch('/api/classifier/move', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify(requestBody)
        });
        
        if (response.ok) {
            const result = await response.json();
            
            // 保存到历史记录
            operationHistory.push({
                file: file,
                fileIndex: currentIndex,
                category: category,
                originalName: getFileNameWithoutExtension(file.name),
                newPath: result.moved_to,
                timestamp: Date.now()
            });
            
            // 限制历史记录数量（最多保留20条）
            if (operationHistory.length > 20) {
                operationHistory.shift();
            }
            
            // 从文件列表中移除已处理的文件
            files.splice(currentIndex, 1);
            
            processedCount++;
            
            updateProgress();
            showCurrentFile();
            updateUndoButton();
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
    if (categories.includes(categoryName)) {
        alert(i18nManager.t('folderExists', 'Folder already exists'));
        return;
    }

    // 直接创建文件夹
    try {
        const response = await fetch('/api/classifier/folder/create', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({
                folder_name: categoryName
            })
        });

        if (response.ok) {
            // 添加到当前分类列表
            currentCategories.push(categoryName);
            input.value = '';
            updateCategoriesGrid();
        } else {
            alert(i18nManager.t('failedCreateFolder', 'Failed to create folder'));
        }
    } catch (error) {
        console.error('Error creating folder:', error);
        alert(i18nManager.t('failedCreateFolder', 'Failed to create folder'));
    }
}

function updateProgress() {
    const progressText = document.getElementById('progressText');
    const progressFill = document.getElementById('progressFill');
    
    const totalFiles = processedCount + files.length - currentIndex;
    progressText.textContent = `${processedCount} / ${totalFiles}`;
    const percentage = totalFiles > 0 ? (processedCount / totalFiles) * 100 : 0;
    progressFill.style.width = `${percentage}%`;
}

// 页面加载完成后初始化
document.addEventListener('DOMContentLoaded', init);
