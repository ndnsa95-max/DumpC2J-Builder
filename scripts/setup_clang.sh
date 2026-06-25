#!/usr/bin/env bash
set -e

CLANG_VARIANT="${1:-neutron}"

echo "[*] Setting up Clang: ${CLANG_VARIANT}"

case "${CLANG_VARIANT}" in
  neutron)
    mkdir -p "${HOME}/toolchains/neutron-clang"
    cd "${HOME}/toolchains/neutron-clang"
    curl -Lo antman https://raw.githubusercontent.com/Neutron-Toolchains/antman/main/antman
    chmod +x antman
    ./antman -S
    ./antman --patch=glibc
    CLANG_BIN="${HOME}/toolchains/neutron-clang/bin"
    COMPILER_STRING="Neutron Clang 23.0.0"
    ;;
  cirrus)
    curl -Lo ~/get_clang.sh \
      https://raw.githubusercontent.com/greenforce-project/greenforce_clang/refs/heads/main/get_clang.sh
    bash ~/get_clang.sh
    CLANG_BIN="${GITHUB_WORKSPACE}/greenforce-clang/bin"
    GF_VERSION=$("${CLANG_BIN}/clang" --version | head -n1 | grep -oP 'clang version \K[0-9.]+' || echo "23.0.0")
    COMPILER_STRING="Cirrus Clang ${GF_VERSION}"
    ;;
  azure)
    AZURE_URL=$(curl -s https://api.github.com/repos/Panchajanya1999/clang-llvm/releases/latest       | python3 -c "import json,sys; d=json.load(sys.stdin); print(next((x['browser_download_url'] for x in d.get('assets',[]) if x['name'].endswith('.tar.gz')), ''))")
    if [ -z "${AZURE_URL}" ]; then
      echo "[!] Azure Clang release not found, falling back to WeebX"
      AZURE_URL=$(curl -s https://raw.githubusercontent.com/XSans0/WeebX-Clang/main/main/link.txt)
    fi
    mkdir -p "${HOME}/toolchains/azure-clang"
    curl -Lo /tmp/azure-clang.tar.gz "${AZURE_URL}"
    tar -xf /tmp/azure-clang.tar.gz -C "${HOME}/toolchains/azure-clang" --strip-components=1
    rm /tmp/azure-clang.tar.gz
    CLANG_BIN="${HOME}/toolchains/azure-clang/bin"
    AZ_VER=$("${CLANG_BIN}/clang" --version | head -n1 | grep -oP 'clang version \K[0-9.]+' || echo "latest")
    COMPILER_STRING="Azure Clang ${AZ_VER}"
    ;;
  weebx)
    WEEBX_URL=$(curl -s https://raw.githubusercontent.com/XSans0/WeebX-Clang/main/main/link.txt)
    mkdir -p "${HOME}/toolchains/weebx-clang"
    wget -q "${WEEBX_URL}" -O /tmp/weebx-clang.tar.gz
    tar -xf /tmp/weebx-clang.tar.gz -C "${HOME}/toolchains/weebx-clang" --strip-components=1
    rm /tmp/weebx-clang.tar.gz
    CLANG_BIN="${HOME}/toolchains/weebx-clang/bin"
    WX_VER=$("${CLANG_BIN}/clang" --version | head -n1 | grep -oP 'clang version \K[0-9.]+' || echo "latest")
    COMPILER_STRING="WeebX Clang ${WX_VER}"
    ;;
  zyc)
    ZYC_URL=$(curl -sL https://raw.githubusercontent.com/ZyCromerZ/Clang/main/Clang-main-link.txt | tr -d '[:space:]')
    echo "[*] ZyC URL: ${ZYC_URL}"
    mkdir -p "${HOME}/toolchains/zyc-clang"
    curl -L --fail --retry 3 -o /tmp/zyc-clang.tar.gz "${ZYC_URL}"
    echo "[*] ZyC tar structure (first 5):"
    tar -tf /tmp/zyc-clang.tar.gz 2>/dev/null | head -5
    tar -xf /tmp/zyc-clang.tar.gz -C "${HOME}/toolchains/zyc-clang" --strip-components=1
    rm /tmp/zyc-clang.tar.gz
    CLANG_BIN="${HOME}/toolchains/zyc-clang/bin"
    ZYC_VER=$("${CLANG_BIN}/clang" --version | head -n1 | grep -oP 'clang version \K[0-9.]+' || echo "latest")
    COMPILER_STRING="ZyC Clang ${ZYC_VER}"
    ;;
  llvm)
    LLVM_VER=$(curl -s https://api.github.com/repos/llvm/llvm-project/releases/latest       | python3 -c "import json,sys; print(json.load(sys.stdin)['tag_name'].replace('llvmorg-',''))")
    LLVM_URL="https://github.com/llvm/llvm-project/releases/download/llvmorg-${LLVM_VER}/clang+llvm-${LLVM_VER}-aarch64-linux-gnu.tar.xz"
    mkdir -p "${HOME}/toolchains/llvm-clang"
    curl -Lo /tmp/llvm-clang.tar.xz "${LLVM_URL}"
    tar -xf /tmp/llvm-clang.tar.xz -C "${HOME}/toolchains/llvm-clang" --strip-components=1
    rm /tmp/llvm-clang.tar.xz
    CLANG_BIN="${HOME}/toolchains/llvm-clang/bin"
    LLVM_VER_OUT=$("${CLANG_BIN}/clang" --version | head -n1 | grep -oP 'clang version \K[0-9.]+' || echo "latest")
    COMPILER_STRING="LLVM Clang ${LLVM_VER_OUT}"
    ;;
  *)
    echo "[!] Unknown clang variant: ${CLANG_VARIANT}"
    exit 1
    ;;
esac

echo "CLANG_PATH=${CLANG_BIN}" >> "${GITHUB_ENV}"
echo "${CLANG_BIN}" >> "${GITHUB_PATH}"
echo "KBUILD_COMPILER_STRING=${COMPILER_STRING}" >> "${GITHUB_ENV}"
echo "KBUILD_BUILD_USER=adennnqt" >> "${GITHUB_ENV}"
echo "KBUILD_BUILD_HOST=DumpC2J" >> "${GITHUB_ENV}"
echo "[+] Clang ready: ${CLANG_BIN}"
${CLANG_BIN}/clang --version
