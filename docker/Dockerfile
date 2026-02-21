# 使用 Ubuntu 24.04 (提供 GLIBC 2.39,兼容最新的 Rust 二进制)
FROM ubuntu:24.04

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    vim \
    python3 \
    libfontconfig1 \
    gosu \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# 复制自动更新启动脚本
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# 创建配置和数据目录,确保任何 UID 都有权限访问
RUN mkdir -p /home/appuser/.config && \
    mkdir -p /data && \
    chmod -R 777 /home/appuser /data /app

EXPOSE 1234

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:1234/api/health || exit 1

ENV RUST_LOG=info

ENTRYPOINT ["/entrypoint.sh"]
