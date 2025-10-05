// 共享的多语言管理器
const i18nManager = {
    currentLang: localStorage.getItem('lang') || 'en',

    translations: {
        zh: {
            // 首页
            homeTitle: 'ReSourcer',
            homeSubtitle: '个人资源管理工具',
            scanToAccess: '同局域网下扫描访问',
            settings: '设置',
            classifier: '分类器',
            downloader: '下载器',
            transmitter: '传输器',
            comingSoon: '即将推出',

            // Settings 页面
            settingsTitle: '设置',
            sourceFolder: '源文件夹',
            folderPlaceholder: '/path/to/your/folder',
            categoryFolders: '分类文件夹',
            addNewFolder: '添加新文件夹',
            applyPreset: '或应用预设',
            apply: '应用',
            backToHome: '返回首页',
            noFoldersYet: '暂无文件夹',
            folderExists: '文件夹已存在',
            selectPreset: '请选择一个预设',
            enterFolderPath: '请输入文件夹路径',
            needAtLeastOneFolder: '请至少添加一个可见文件夹',
            settingsSaved: '设置保存成功!',
            failedSaveSettings: '保存设置失败',

            // Classifier 页面
            title: 'Toolkit ReClassifier',
            categoryPreset: '分类预设',
            categories: '分类',
            addNewCategory: '添加新分类',
            add: '添加',
            editCategories: '编辑分类',
            setupCategories: '设置分类',
            startClassification: '开始分类',
            categoriesTitle: '分类',
            quickAddCategory: '快速添加分类',
            addCategory: '添加分类',
            allDone: '全部完成！',
            filesProcessed: '已处理 {count} 个文件',
            outputFolder: '输出文件夹：',
            fileCounter: '第 {current} 个，共 {total} 个',
            undo: '撤销',
            skip: '跳过',
            enterPresetName: '请输入预设名称：',
            presetExists: '预设名称已存在',
            noCategoriesYet: '暂无分类',
            categoryExists: '分类已存在',
            updatePreset: '要更新预设 "{name}" 吗？',
            saveAsNewPreset: '另存为新预设，名称：',
            presetSaved: '预设 "{name}" 保存成功',
            pleaseAddCategories: '请先添加一些分类',
            presetDeleted: '预设 "{name}" 已删除',
            confirmDelete: '确定要删除预设 "{name}" 吗？',
            selectPresetToDelete: '请选择要删除的预设',
            failedUpdateFolder: '更新源文件夹失败',
            enterSourceFolderFirst: '请先输入源文件夹路径',
            failedUndoMoved: '撤销操作失败。文件可能已被手动移动。',
            failedUndo: '撤销操作失败',
            setSourceFolderFirst: '请先设置源文件夹',
            noFilesFound: '在 {folder} 中未找到支持的文件',
            errorLoadingFiles: '从 {folder} 加载文件时出错',
            failedCreateFolder: '创建文件夹失败',

            // Downloader 页面
            downloaderTitle: '下载器',
            downloaderSubtitle: '从各个平台下载媒体内容',
            urlLabel: 'URL 地址',
            urlPlaceholder: 'https://...',
            folderLabel: '保存文件夹',
            sourceFolder: '源文件夹',
            downloadBtn: '下载',
            tasksTitle: '任务列表',
            noTasks: '暂无任务',
            cancelBtn: '取消',
            openFolder: '打开',
            previewBtn: '预览',
            openUrl: '打开网址',
            clearHistory: '清空历史',
            settingsLink: '设置',
            authBtn: '认证',
            authTitle: '认证管理',
            authActive: '已配置',
            authInactive: '未配置',
            authUploadFile: '上传文件',
            authInput: '输入',
            authDelete: '删除',

            // 通用
            save: '保存',
            delete: '删除',
            cancel: '取消',
            confirm: '确认'
        },
        en: {
            // Home
            homeTitle: 'ReSourcer',
            scanToAccess: 'Scan to access on LAN',
            settings: 'Settings',
            classifier: 'Classifier',
            downloader: 'Downloader',
            transmitter: 'Transmitter',
            comingSoon: 'coming soon',

            // Settings page
            settingsTitle: 'Settings',
            sourceFolder: 'Source Folder',
            folderPlaceholder: '/path/to/your/folder',
            categoryFolders: 'Category Folders',
            addNewFolder: 'Add new folder',
            applyPreset: 'Or apply a preset',
            apply: 'Apply',
            backToHome: 'Back to Home',
            noFoldersYet: 'No folders yet',
            folderExists: 'Folder already exists',
            selectPreset: 'Please select a preset',
            enterFolderPath: 'Please enter a folder path',
            needAtLeastOneFolder: 'Please add at least one visible folder',
            settingsSaved: 'Settings saved successfully!',
            failedSaveSettings: 'Failed to save settings',

            // Classifier page
            title: 'Toolkit ReClassifier',
            categoryPreset: 'Category Preset',
            categories: 'Categories',
            addNewCategory: 'Add new category',
            add: 'Add',
            editCategories: 'Edit Categories',
            setupCategories: 'Setup Categories',
            startClassification: 'Start Classification',
            categoriesTitle: 'Categories',
            quickAddCategory: 'Quick add category',
            addCategory: 'Add Category',
            allDone: 'All done!',
            filesProcessed: '{count} files processed',
            outputFolder: 'Output folder:',
            fileCounter: '{current} of {total}',
            undo: 'Undo',
            skip: 'Skip',
            enterPresetName: 'Enter preset name:',
            presetExists: 'Preset name already exists',
            noCategoriesYet: 'No categories yet',
            categoryExists: 'Category already exists',
            updatePreset: 'Update preset "{name}" with current categories?',
            saveAsNewPreset: 'Save as new preset with name:',
            presetSaved: 'Preset "{name}" saved successfully',
            pleaseAddCategories: 'Please add some categories first',
            presetDeleted: 'Preset "{name}" deleted',
            confirmDelete: 'Delete preset "{name}"?',
            selectPresetToDelete: 'Please select a preset to delete',
            failedUpdateFolder: 'Failed to update source folder',
            enterSourceFolderFirst: 'Please enter source folder path first',
            failedUndoMoved: 'Failed to undo operation. The file might have been manually moved.',
            failedUndo: 'Failed to undo operation',
            setSourceFolderFirst: 'Please set source folder first',
            noFilesFound: 'No supported files found in: {folder}',
            errorLoadingFiles: 'Error loading files from: {folder}',
            failedCreateFolder: 'Failed to create folder',

            // Downloader page
            downloaderTitle: 'Downloader',
            downloaderSubtitle: 'Download media from various platforms',
            urlLabel: 'URL',
            urlPlaceholder: 'https://...',
            folderLabel: 'Folder',
            sourceFolder: 'Source Folder',
            downloadBtn: 'Download',
            tasksTitle: 'Tasks',
            noTasks: 'No tasks',
            cancelBtn: 'Cancel',
            openFolder: 'Open',
            previewBtn: 'Preview',
            openUrl: 'Open URL',
            clearHistory: 'Clear History',
            settingsLink: 'Settings',
            authBtn: 'Auth',
            authTitle: 'Authentication',
            authActive: 'Configured',
            authInactive: 'Not configured',
            authUploadFile: 'Upload File',
            authInput: 'Input',
            authDelete: 'Delete',

            // Common
            save: 'Save',
            delete: 'Delete',
            cancel: 'Cancel',
            confirm: 'Confirm'
        }
    },

    t(key, placeholders = {}) {
        let text = this.translations[this.currentLang][key] || key;

        // 替换占位符
        Object.keys(placeholders).forEach(placeholder => {
            text = text.replace(`{${placeholder}}`, placeholders[placeholder]);
        });

        return text;
    },

    setLang(lang) {
        this.currentLang = lang;
        localStorage.setItem('lang', lang);
        this.updateUI();
    },

    updateUI() {
        // 更新所有带 data-i18n 属性的元素
        document.querySelectorAll('[data-i18n]').forEach(el => {
            const key = el.getAttribute('data-i18n');
            el.textContent = this.t(key);
        });

        // 更新所有带 data-i18n-placeholder 属性的输入框
        document.querySelectorAll('[data-i18n-placeholder]').forEach(el => {
            const key = el.getAttribute('data-i18n-placeholder');
            el.placeholder = this.t(key);
        });

        // 更新语言切换按钮状态
        document.querySelectorAll('.lang-btn').forEach(btn => {
            btn.classList.toggle('active', btn.dataset.lang === this.currentLang);
        });
    }
};
