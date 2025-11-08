FROM debian:bookworm-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    vim \
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

RUN mkdir -p /root/.config/re-sourcer && \
    mkdir -p /data

EXPOSE 1234

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:1234/api/health || exit 1

ENV RUST_LOG=info

CMD ["/app/re-sourcer"]
