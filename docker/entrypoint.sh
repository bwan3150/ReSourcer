#!/bin/bash
set -e

REPO="bwan3150/ReSourcer"
BINARY_NAME="re-sourcer"
BINARY_PATH="/app/${BINARY_NAME}"
VERSION_FILE="/app/.current_version"

# 获取 GitHub 最新 release 版本号
get_latest_version() {
    curl -s "https://api.github.com/repos/${REPO}/releases/latest" \
        | grep '"tag_name"' \
        | cut -d '"' -f 4
}

# 根据架构获取下载链接
get_download_url() {
    local arch
    arch=$(uname -m)
    local asset_name

    case "${arch}" in
        x86_64|amd64)
            asset_name="re-sourcer-linux-x86_64"
            ;;
        aarch64|arm64)
            asset_name="re-sourcer-linux-aarch64"
            ;;
        *)
            echo "不支持的架构: ${arch}" >&2
            return 1
            ;;
    esac

    curl -s "https://api.github.com/repos/${REPO}/releases/latest" \
        | grep "browser_download_url" \
        | grep "${asset_name}" \
        | cut -d '"' -f 4
}

# 获取本地已安装的版本号
get_local_version() {
    if [ -f "${VERSION_FILE}" ]; then
        cat "${VERSION_FILE}"
    else
        echo ""
    fi
}

echo "=== ReSourcer 自动更新检查 ==="

# 获取最新版本
LATEST_VERSION=$(get_latest_version)
if [ -z "${LATEST_VERSION}" ]; then
    echo "警告: 无法获取最新版本信息（网络问题？）"
    if [ -x "${BINARY_PATH}" ]; then
        echo "使用本地已有的二进制文件启动..."
        exec "${BINARY_PATH}" "$@"
    else
        echo "错误: 无法获取最新版本，且本地没有可用的二进制文件" >&2
        exit 1
    fi
fi

LOCAL_VERSION=$(get_local_version)
echo "最新版本: ${LATEST_VERSION}"
echo "本地版本: ${LOCAL_VERSION:-无}"

# 判断是否需要更新
if [ "${LATEST_VERSION}" = "${LOCAL_VERSION}" ] && [ -x "${BINARY_PATH}" ]; then
    echo "已是最新版本，跳过下载"
else
    echo "检测到新版本或二进制文件不存在，开始下载..."

    DOWNLOAD_URL=$(get_download_url)
    if [ -z "${DOWNLOAD_URL}" ]; then
        echo "错误: 无法获取下载链接" >&2
        if [ -x "${BINARY_PATH}" ]; then
            echo "使用本地已有的二进制文件启动..."
            exec "${BINARY_PATH}" "$@"
        fi
        exit 1
    fi

    echo "下载地址: ${DOWNLOAD_URL}"

    # 下载到临时文件，成功后再替换，避免下载失败导致二进制损坏
    TEMP_FILE="${BINARY_PATH}.tmp"
    if curl -L -o "${TEMP_FILE}" "${DOWNLOAD_URL}"; then
        mv "${TEMP_FILE}" "${BINARY_PATH}"
        chmod +x "${BINARY_PATH}"
        echo "${LATEST_VERSION}" > "${VERSION_FILE}"
        echo "更新完成: ${LATEST_VERSION}"
    else
        echo "下载失败" >&2
        rm -f "${TEMP_FILE}"
        if [ -x "${BINARY_PATH}" ]; then
            echo "使用本地已有的二进制文件启动..."
        else
            echo "错误: 下载失败且本地没有可用的二进制文件" >&2
            exit 1
        fi
    fi
fi

echo "=== 启动 ReSourcer ==="
exec "${BINARY_PATH}" "$@"
