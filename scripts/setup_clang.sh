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
    NEUTRON_VER=$("${CLANG_BIN}/clang" --version | head -n1 | grep -oP 'clang version \K[0-9.]+' || echo "latest")
    COMPILER_STRING="Neutron Clang ${NEUTRON_VER}"
    ;;
  cirrus)
    CIRRUS_URL=$(curl -s https://api.github.com/repos/greenforce-project/greenforce_clang/releases/latest \
      | python3 -c "import json,sys; d=json.load(sys.stdin); print(next((x['browser_download_url'] for x in d.get('assets',[]) if x['name'].endswith('.tar.gz')), ''))")
    if [ -z "${CIRRUS_URL}" ]; then
      echo "[!] Cirrus release not found"
      exit 1
    fi
    echo "[*] Cirrus URL: ${CIRRUS_URL}"
    mkdir -p "${HOME}/toolchains/cirrus-clang"
    curl -Lo /tmp/cirrus-clang.tar.gz "${CIRRUS_URL}"
    tar -xf /tmp/cirrus-clang.tar.gz -C "${HOME}/toolchains/cirrus-clang" --strip-components=1
    rm /tmp/cirrus-clang.tar.gz
    CLANG_BIN="${HOME}/toolchains/cirrus-clang/bin"
    GF_VERSION=$("${CLANG_BIN}/clang" --version | head -n1 | grep -oP 'clang version \K[0-9.]+' || echo "23.0.0")
    COMPILER_STRING="Cirrus Clang ${GF_VERSION}"
    ;;
  weebx)
    WEEBX_URL=$(curl -s https://raw.githubusercontent.com/XSans0/WeebX-Clang/main/main/link.txt)
    [ -z "${WEEBX_URL}" ] && { echo "[!] WeebX URL not found"; exit 1; }
    mkdir -p "${HOME}/toolchains/weebx-clang"
    curl -Lo /tmp/weebx-clang.tar.gz "${WEEBX_URL}"
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
    if [ -z "$ZYC_URL" ]; then
      echo "[-] ZyC: Clang-main-link.txt is empty or unreachable. ZyC may be down."
      echo "[-] Please choose a different toolchain (neutron/cirrus/azure/weebx/llvm)."
      exit 1
    fi
    curl -L --fail --retry 3 -o /tmp/zyc-clang.tar.gz "${ZYC_URL}" || {
      echo "[-] ZyC: download failed. Server may be down."
      echo "[-] Please choose a different toolchain (neutron/cirrus/azure/weebx/llvm)."
      exit 1
    }
    echo "[*] ZyC tar structure (first 10):"
    tar -tf /tmp/zyc-clang.tar.gz 2>/dev/null | head -10
    echo "[*] ZyC bin location:"
    tar -tf /tmp/zyc-clang.tar.gz 2>/dev/null | grep -m3 'bin/clang'
    STRIP=0
    BIN_PATH=$(tar -tf /tmp/zyc-clang.tar.gz 2>/dev/null | grep -m1 'bin/clang$')
    [ -z "$BIN_PATH" ] && { echo "[!] bin/clang not found in ZyC tarball"; exit 1; }
    DEPTH=$(echo "$BIN_PATH" | tr '/' '\n' | wc -l)
    STRIP=$(( DEPTH - 2 ))
    [ "$STRIP" -lt 0 ] && STRIP=0
    echo "[*] bin/clang found at: ${BIN_PATH} -> strip-components=${STRIP}"
    tar -xf /tmp/zyc-clang.tar.gz -C "${HOME}/toolchains/zyc-clang" --strip-components=${STRIP}
    rm /tmp/zyc-clang.tar.gz
    CLANG_BIN="${HOME}/toolchains/zyc-clang/bin"
    ZYC_VER=$("${CLANG_BIN}/clang" --version | head -n1 | grep -oP 'clang version \K[0-9.]+' || echo "latest")
    COMPILER_STRING="ZyC Clang ${ZYC_VER}"
    ;;
  *)
    echo "[!] Unknown clang variant: ${CLANG_VARIANT}"
    exit 1
    ;;
esac

echo "CLANG_VARIANT=${CLANG_VARIANT}" >> "${GITHUB_ENV}"
echo "CLANG_PATH=${CLANG_BIN}" >> "${GITHUB_ENV}"
echo "${CLANG_BIN}" >> "${GITHUB_PATH}"
echo "KBUILD_COMPILER_STRING=${COMPILER_STRING}" >> "${GITHUB_ENV}"
echo "[+] Clang ready: ${CLANG_BIN}"
${CLANG_BIN}/clang --version
