// 共享的多语言管理器
const i18nManager = {
    currentLang: localStorage.getItem('lang') || 'en',

    translations: {
        zh: {
            // 首页
            homeTitle: 'ReSourcer',
            homeSubtitle: '个人资源管理工具',
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

            // 通用
            save: '保存',
            delete: '删除',
            cancel: '取消',
            confirm: '确认'
        },
        en: {
            // Home
            homeTitle: 'ReSourcer',
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
