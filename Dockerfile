# 使用 Ubuntu 24.04 (提供 GLIBC 2.39,兼容最新的 Rust 二进制)
FROM ubuntu:24.04

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    vim \
    python3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# 下载最新版本的 ReSourcer Linux 二进制文件
RUN DOWNLOAD_URL=$(curl -s https://api.github.com/repos/bwan3150/ReSourcer/releases/latest \
    | grep "browser_download_url" \
    | grep "re-sourcer-linux-x86_64" \
    | cut -d '"' -f 4) && \
    echo "Downloading from: ${DOWNLOAD_URL}" && \
    curl -L -o /app/re-sourcer "${DOWNLOAD_URL}" && \
    chmod +x /app/re-sourcer

# 创建配置和数据目录,确保任何 UID 都有权限访问
RUN mkdir -p /home/appuser/.config && \
    mkdir -p /data && \
    chmod -R 777 /home/appuser /data

EXPOSE 1234

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:1234/api/health || exit 1

ENV RUST_LOG=info

CMD ["/app/re-sourcer"]
