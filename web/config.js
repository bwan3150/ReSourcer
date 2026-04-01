// 后端 API 基础 URL 配置
// 当前端和后端分离部署时，设置 window.__RESOURCER_API_BASE 指向后端地址
// 例如：window.__RESOURCER_API_BASE = 'http://192.168.1.100:1234';
const API_BASE = window.__RESOURCER_API_BASE || '';

// 统一 API 请求函数，自动加上 API_BASE 前缀和 API Key header
function apiFetch(path, options = {}) {
    const headers = { ...options.headers };
    const apiKey = AuthManager.getApiKey();
    if (apiKey) {
        headers['X-API-Key'] = apiKey;
    }
    return fetch(API_BASE + path, { ...options, headers });
}

// 生成 API 资源 URL（用于图片 src、视频 src 等）
function apiUrl(path) {
    return API_BASE + path;
}
