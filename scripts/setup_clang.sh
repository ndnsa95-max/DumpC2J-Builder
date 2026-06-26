#!/usr/bin/env bash
set -e

CLANG_VARIANT="${1:-neutron}"
CACHE_HIT="${2:-}"

echo "[*] Setting up Clang: ${CLANG_VARIANT}"

if [ "${CACHE_HIT}" == "--cache-hit" ]; then
  echo "[+] Clang restored from cache"
  case "${CLANG_VARIANT}" in
    neutron) CLANG_BIN="${GITHUB_WORKSPACE}/toolchains/neutron-clang/bin" ;;
    cirrus)  CLANG_BIN="${GITHUB_WORKSPACE}/toolchains/cirrus-clang/bin" ;;
    weebx)   CLANG_BIN="${GITHUB_WORKSPACE}/toolchains/weebx-clang/bin" ;;
    zyc)     CLANG_BIN="${GITHUB_WORKSPACE}/toolchains/zyc-clang/bin" ;;
  esac
  if ! "${CLANG_BIN}/clang" --version > /dev/null 2>&1; then
    if [ "${CLANG_VARIANT}" == "neutron" ]; then
      cd "${GITHUB_WORKSPACE}/toolchains/neutron-clang"
      [ -f antman ] && ./antman --patch=glibc || true
      cd -
    fi
  fi
  COMPILER_VER=$("${CLANG_BIN}/clang" --version | head -n1 | grep -oP 'clang version \K[0-9.]+' || echo "latest")
  case "${CLANG_VARIANT}" in
    neutron) COMPILER_STRING="Neutron Clang ${COMPILER_VER}" ;;
    cirrus)  COMPILER_STRING="Cirrus Clang ${COMPILER_VER}" ;;
    weebx)   COMPILER_STRING="WeebX Clang ${COMPILER_VER}" ;;
    zyc)     COMPILER_STRING="ZyC Clang ${COMPILER_VER}" ;;
  esac
  echo "CLANG_PATH=${CLANG_BIN}" >> "${GITHUB_ENV}"
  echo "${CLANG_BIN}" >> "${GITHUB_PATH}"
  echo "KBUILD_COMPILER_STRING=${COMPILER_STRING}" >> "${GITHUB_ENV}"
  "${CLANG_BIN}/clang" --version
  exit 0
fi

case "${CLANG_VARIANT}" in
  neutron)
    mkdir -p "${GITHUB_WORKSPACE}/toolchains/neutron-clang"
    cd "${GITHUB_WORKSPACE}/toolchains/neutron-clang"
    curl -Lo antman https://raw.githubusercontent.com/Neutron-Toolchains/antman/main/antman
    chmod +x antman
    ./antman -S
    ./antman --patch=glibc
    CLANG_BIN="${GITHUB_WORKSPACE}/toolchains/neutron-clang/bin"
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
    mkdir -p "${GITHUB_WORKSPACE}/toolchains/cirrus-clang"
    curl -Lo /tmp/cirrus-clang.tar.gz "${CIRRUS_URL}"
    tar -xf /tmp/cirrus-clang.tar.gz -C "${GITHUB_WORKSPACE}/toolchains/cirrus-clang" --strip-components=1
    rm /tmp/cirrus-clang.tar.gz
    CLANG_BIN="${GITHUB_WORKSPACE}/toolchains/cirrus-clang/bin"
    GF_VERSION=$("${CLANG_BIN}/clang" --version | head -n1 | grep -oP 'clang version \K[0-9.]+' || echo "23.0.0")
    COMPILER_STRING="Cirrus Clang ${GF_VERSION}"
    ;;
  weebx)
    WEEBX_URL=$(curl -s https://raw.githubusercontent.com/XSans0/WeebX-Clang/main/main/link.txt)
    mkdir -p "${GITHUB_WORKSPACE}/toolchains/weebx-clang"
    wget -q "${WEEBX_URL}" -O /tmp/weebx-clang.tar.gz
    tar -xf /tmp/weebx-clang.tar.gz -C "${GITHUB_WORKSPACE}/toolchains/weebx-clang" --strip-components=1
    rm /tmp/weebx-clang.tar.gz
    CLANG_BIN="${GITHUB_WORKSPACE}/toolchains/weebx-clang/bin"
    WX_VER=$("${CLANG_BIN}/clang" --version | head -n1 | grep -oP 'clang version \K[0-9.]+' || echo "latest")
    COMPILER_STRING="WeebX Clang ${WX_VER}"
    ;;
  zyc)
    ZYC_URL=$(curl -sL https://raw.githubusercontent.com/ZyCromerZ/Clang/main/Clang-main-link.txt | tr -d '[:space:]')
    echo "[*] ZyC URL: ${ZYC_URL}"
    mkdir -p "${GITHUB_WORKSPACE}/toolchains/zyc-clang"
    curl -L --fail --retry 3 -o /tmp/zyc-clang.tar.gz "${ZYC_URL}"
    echo "[*] ZyC tar structure (first 10):"
    tar -tf /tmp/zyc-clang.tar.gz 2>/dev/null | head -10
    echo "[*] ZyC bin location:"
    tar -tf /tmp/zyc-clang.tar.gz 2>/dev/null | grep -m3 'bin/clang'
    STRIP=0
    BIN_PATH=$(tar -tf /tmp/zyc-clang.tar.gz 2>/dev/null | grep -m1 'bin/clang$')
    DEPTH=$(echo "$BIN_PATH" | tr '/' '\n' | wc -l)
    STRIP=$(( DEPTH - 2 ))
    [ "$STRIP" -lt 0 ] && STRIP=0
    echo "[*] bin/clang found at: ${BIN_PATH} -> strip-components=${STRIP}"
    tar -xf /tmp/zyc-clang.tar.gz -C "${GITHUB_WORKSPACE}/toolchains/zyc-clang" --strip-components=${STRIP}
    rm /tmp/zyc-clang.tar.gz
    CLANG_BIN="${GITHUB_WORKSPACE}/toolchains/zyc-clang/bin"
    ZYC_VER=$("${CLANG_BIN}/clang" --version | head -n1 | grep -oP 'clang version \K[0-9.]+' || echo "latest")
    COMPILER_STRING="ZyC Clang ${ZYC_VER}"
    ;;
  *)
    echo "[!] Unknown clang variant: ${CLANG_VARIANT}"
    exit 1
    ;;
esac

echo "CLANG_PATH=${CLANG_BIN}" >> "${GITHUB_ENV}"
echo "${CLANG_BIN}" >> "${GITHUB_PATH}"
echo "KBUILD_COMPILER_STRING=${COMPILER_STRING}" >> "${GITHUB_ENV}"
echo "[+] Clang ready: ${CLANG_BIN}"
${CLANG_BIN}/clang --version
