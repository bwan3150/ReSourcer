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
            settingsSubtitle: '配置您的工作区和分类',
            mainFolder: '主文件夹',
            workspacePath: '工作区文件夹路径',
            saveFolder: '保存文件夹',
            categories: '分类',
            categoriesDesc: '分类基于主文件夹中的子文件夹',
            addNewCategory: '添加新分类文件夹',
            create: '创建',
            hidden: '已隐藏',
            show: '显示',
            hide: '隐藏',
            presetTemplates: '预设模板',
            presetTemplatesDesc: '基于预设模板快速创建多个文件夹',
            backToHome: '返回首页',
            folders: '个文件夹',

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
            mainFolder: 'Main Folder',
            workspacePath: 'Workspace Folder Path',
            saveFolder: 'Save Folder',
            categories: 'Categories',
            categoriesDesc: 'Categories are based on subfolders in your main folder',
            addNewCategory: 'Add New Category Folder',
            create: 'Create',
            hidden: 'Hidden',
            show: 'Show',
            hide: 'Hide',
            presetTemplates: 'Preset Templates',
            presetTemplatesDesc: 'Quickly create multiple folders based on preset templates',
            backToHome: 'Back to Home',
            folders: 'folders',

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
