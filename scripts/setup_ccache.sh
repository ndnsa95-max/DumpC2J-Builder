#!/usr/bin/env bash
set -euo pipefail

CCACHE_ECS_VERSION="ccache-ECS-v1.0"
CCACHE_ECS_REPO="cctv18/ccache-ECS"
CCACHE_CACHE_DIR="${HOME}/ccache-bin"
CCACHE_DIR="${CCACHE_DIR:-/home/runner/.ccache}"
CCACHE_MAXSIZE="${CCACHE_MAXSIZE:-5G}"

echo "[ccache-ECS] Setting up..."

if [ -f "${CCACHE_CACHE_DIR}/ccache" ]; then
    echo "[ccache-ECS] Restoring from cache..."
else
    echo "[ccache-ECS] Downloading binary..."
    DOWNLOAD_URL="https://github.com/${CCACHE_ECS_REPO}/releases/download/${CCACHE_ECS_VERSION}/linux-x86_64-musl-static-binary.zip"
    wget -q "${DOWNLOAD_URL}" -O /tmp/ccache-ecs.zip
    unzip -q /tmp/ccache-ecs.zip -d /tmp/ccache-ecs-extract
    CCACHE_BIN=$(find /tmp/ccache-ecs-extract -name "ccache" -type f | head -1)
    mkdir -p "${CCACHE_CACHE_DIR}"
    cp "$CCACHE_BIN" "${CCACHE_CACHE_DIR}/ccache"
    chmod +x "${CCACHE_CACHE_DIR}/ccache"
    rm -rf /tmp/ccache-ecs.zip /tmp/ccache-ecs-extract
fi

# Symlink ke /usr/local/bin biar override system ccache
sudo ln -sf "${CCACHE_CACHE_DIR}/ccache" /usr/local/bin/ccache

echo "[ccache-ECS] Version: $("${CCACHE_CACHE_DIR}/ccache" --version | head -1)"

# Config
export CCACHE_DIR
export CCACHE_IS_KERNEL_COMPILING="true"
export CCACHE_COMPRESS=1
export CCACHE_COMPRESSLEVEL=1
mkdir -p "$CCACHE_DIR"
"${CCACHE_CACHE_DIR}/ccache" --set-config="cache_dir=${CCACHE_DIR}"
"${CCACHE_CACHE_DIR}/ccache" --set-config="max_size=${CCACHE_MAXSIZE}"
"${CCACHE_CACHE_DIR}/ccache" --set-config="compiler_check=content"
"${CCACHE_CACHE_DIR}/ccache" --zero-stats > /dev/null 2>&1 || true

echo "[ccache-ECS] Setup done! dir: ${CCACHE_DIR} | max: ${CCACHE_MAXSIZE}"
