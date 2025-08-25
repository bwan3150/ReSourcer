// 多语言配置
const i18n = {
    zh: {
        // 设置界面
        title: 'Toolkit ReClassifier',
        sourceFolder: '源文件夹',
        folderPlaceholder: '/path/to/your/folder',
        categoryPreset: '分类预设',
        save: '保存',
        delete: '删除',
        categories: '分类',
        addNewCategory: '添加新分类',
        add: '添加',
        editCategories: '编辑分类',
        setupCategories: '设置分类',
        startClassification: '开始分类',
        
        // 主界面
        categoriesTitle: '分类',
        quickAddCategory: '快速添加分类',
        addCategory: '添加分类',
        
        // 完成界面
        allDone: '全部完成！',
        filesProcessed: '已处理 {count} 个文件',
        outputFolder: '输出文件夹：',
        
        // 文件信息
        fileCounter: '第 {current} 个，共 {total} 个',
        
        // 快捷键
        undo: '撤销',
        skip: '跳过',
        
        // 提示信息
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
        enterFolderPath: '请输入文件夹路径',
        failedUpdateFolder: '更新源文件夹失败',
        enterSourceFolderFirst: '请先输入源文件夹路径',
        failedUndoMoved: '撤销操作失败。文件可能已被手动移动。',
        failedUndo: '撤销操作失败',
        setSourceFolderFirst: '请先设置源文件夹',
        noFilesFound: '在 {folder} 中未找到支持的文件',
        errorLoadingFiles: '从 {folder} 加载文件时出错'
    },
    en: {
        // Setup interface
        title: 'Toolkit ReClassifier',
        sourceFolder: 'Source Folder',
        folderPlaceholder: '/path/to/your/folder',
        categoryPreset: 'Category Preset',
        save: 'Save',
        delete: 'Delete',
        categories: 'Categories',
        addNewCategory: 'Add new category',
        add: 'Add',
        editCategories: 'Edit Categories',
        setupCategories: 'Setup Categories',
        startClassification: 'Start Classification',
        
        // Main interface
        categoriesTitle: 'Categories',
        quickAddCategory: 'Quick add category',
        addCategory: 'Add Category',
        
        // Complete interface
        allDone: 'All done!',
        filesProcessed: '{count} files processed',
        outputFolder: 'Output folder:',
        
        // File info
        fileCounter: '{current} of {total}',
        
        // Shortcuts
        undo: 'Undo',
        skip: 'Skip',
        
        // Messages
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
        failedUndoMoved: 'Failed to undo operation. The file might have been manually moved.',
        failedUndo: 'Failed to undo operation',
        setSourceFolderFirst: 'Please set source folder first',
        noFilesFound: 'No supported files found in: {folder}',
        errorLoadingFiles: 'Error loading files from: {folder}'
    }
};

// 语言检测和管理
class I18nManager {
    constructor() {
        this.currentLang = this.detectLanguage();
        this.translations = i18n[this.currentLang] || i18n.en;
    }
    
    // 检测用户语言
    detectLanguage() {
        // 优先从localStorage读取用户设置
        const savedLang = localStorage.getItem('userLanguage');
        if (savedLang && i18n[savedLang]) {
            return savedLang;
        }
        
        // 检测浏览器语言
        const browserLang = navigator.language || navigator.userLanguage;
        
        // 如果是中文（简体或繁体），返回中文
        if (browserLang && (browserLang.startsWith('zh') || browserLang.startsWith('cn'))) {
            return 'zh';
        }
        
        // 其他语言默认英文
        return 'en';
    }
    
    // 切换语言
    setLanguage(lang) {
        if (i18n[lang]) {
            this.currentLang = lang;
            this.translations = i18n[lang];
            localStorage.setItem('userLanguage', lang);
            this.updateUI();
        }
    }
    
    // 获取翻译文本
    t(key, params = {}) {
        let text = this.translations[key] || i18n.en[key] || key;
        
        // 替换参数
        Object.keys(params).forEach(param => {
            text = text.replace(`{${param}}`, params[param]);
        });
        
        return text;
    }
    
    // 更新界面文本
    updateUI() {
        // 更新所有带有 data-i18n 属性的元素
        document.querySelectorAll('[data-i18n]').forEach(element => {
            const key = element.getAttribute('data-i18n');
            const text = this.t(key);
            
            if (element.tagName === 'INPUT' || element.tagName === 'TEXTAREA') {
                element.placeholder = text;
            } else {
                element.textContent = text;
            }
        });
        
        // 更新文档标题
        document.title = this.t('title');
        
        // 更新语言切换按钮状态
        document.querySelectorAll('.lang-btn').forEach(btn => {
            const lang = btn.getAttribute('data-lang');
            if (lang === this.currentLang) {
                btn.classList.add('active');
            } else {
                btn.classList.remove('active');
            }
        });
    }
}

// 创建全局实例
const i18nManager = new I18nManager();
