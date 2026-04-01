FROM nginx:alpine

# 复制前端页面
COPY web/ /usr/share/nginx/html/

# 复制 nginx 配置
COPY docker/nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget -qO- http://localhost/ || exit 1
