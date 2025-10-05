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
            categoryPreset: '分类预设',
            categories: '分类',
            addNewCategory: '添加新分类',
            editCategories: '编辑分类',
            done: '完成',
            backToHome: '返回首页',
            enterPresetName: '请输入预设名称:',
            presetExists: '预设名称已存在',
            noCategoriesYet: '暂无分类',
            categoryExists: '分类已存在',
            updatePreset: '要更新预设 "{name}" 吗?',
            saveAsNewPreset: '另存为新预设，名称:',
            presetSaved: '预设 "{name}" 保存成功',
            pleaseAddCategories: '请先添加一些分类',
            presetDeleted: '预设 "{name}" 已删除',
            confirmDelete: '确定要删除预设 "{name}" 吗?',
            selectPresetToDelete: '请选择要删除的预设',
            enterFolderPath: '请输入文件夹路径',
            failedUpdateFolder: '更新源文件夹失败',
            enterSourceFolderFirst: '请先输入源文件夹路径',
            folderUpdated: '源文件夹更新成功!',

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
            categoryPreset: 'Category Preset',
            categories: 'Categories',
            addNewCategory: 'Add new category',
            editCategories: 'Edit Categories',
            done: 'Done',
            backToHome: 'Back to Home',
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
            enterFolderPath: 'Please enter a folder path',
            failedUpdateFolder: 'Failed to update source folder',
            enterSourceFolderFirst: 'Please enter source folder path first',
            folderUpdated: 'Source folder updated successfully!',

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
