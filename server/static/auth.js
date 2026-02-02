// API Key 管理器
const AuthManager = {
    // 获取 API Key
    getApiKey() {
        return localStorage.getItem('api_key');
    },

    // 保存 API Key
    setApiKey(key) {
        localStorage.setItem('api_key', key);

        // 同时设置 Cookie
        const expires = new Date();
        expires.setDate(expires.getDate() + 30);
        document.cookie = `api_key=${key}; expires=${expires.toUTCString()}; path=/; SameSite=Lax`;
    },

    // 清除 API Key
    clearApiKey() {
        localStorage.removeItem('api_key');
        document.cookie = 'api_key=; expires=Thu, 01 Jan 1970 00:00:00 UTC; path=/;';
    },

    // 检查是否已登录
    isAuthenticated() {
        return !!this.getApiKey();
    },

    // 登出
    logout() {
        this.clearApiKey();
        window.location.href = '/login.html';
    },

    // 检查认证状态并重定向（用于保护页面）
    checkAuthAndRedirect() {
        // 如果没有 API Key，跳转到登录页
        if (!this.isAuthenticated()) {
            window.location.href = '/login.html';
        }
    },
};
