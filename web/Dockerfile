FROM nginx:alpine

# 复制前端页面
COPY . /usr/share/nginx/html/

# 复制 nginx 配置（排除自身不被复制到 html 目录已由 .dockerignore 处理）
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget -qO- http://localhost/ || exit 1
