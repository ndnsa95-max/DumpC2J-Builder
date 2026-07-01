#!/bin/bash
set -e

KERNEL_DIR="${GITHUB_WORKSPACE}/kernel-source"
cd "$KERNEL_DIR"

git fetch origin --tags 2>/dev/null || true

TAG_NAME="dumpc2j-last-notified"

if git rev-parse "$TAG_NAME" >/dev/null 2>&1; then
  CHANGELOG=$(git log "${TAG_NAME}..HEAD" --no-merges --pretty=format:"%s" | grep -vi '\[ci\]' || true)
else
  CHANGELOG=$(git log -10 --no-merges --pretty=format:"%s" | grep -vi '\[ci\]' || true)
fi

if [ -z "$CHANGELOG" ]; then
  CHANGELOG_TEXT="No kernel changes since last build."
else
  CHANGELOG_TEXT=$(echo "$CHANGELOG" | sed 's/^/- /')
fi

# Variant label
case "$INPUT_VARIANT" in
  stock) VARIANT_LABEL="📦 Stock (No Root)" ;;
  root)  VARIANT_LABEL="🔓 Root Only » ${ACTUAL_ROOT:-?}" ;;
  susfs) VARIANT_LABEL="🛡️ SUSFS » ${ACTUAL_ROOT:-?}" ;;
  *)     VARIANT_LABEL="${INPUT_VARIANT:-unknown}" ;;
esac

# Features (selalu on, tampilin aja)
FEAT=""
FEAT="${FEAT}✅ HTSR 240Hz Touch\n"
FEAT="${FEAT}✅ WiFi Performance Exploits\n"
FEAT="${FEAT}✅ KGSL GPU Bypass\n"
FEAT="${FEAT}✅ Mobile Data Exploits\n"
[ "${INPUT_BYPASS:-off}" == "on" ]      && FEAT="${FEAT}✅ Bypass Charging\n"
[ "${INPUT_NOMOUNT:-off}" == "on" ]     && FEAT="${FEAT}✅ NoMount (VFS)\n"
[ "${INPUT_DROIDSPACES:-off}" == "on" ] && FEAT="${FEAT}✅ Droidspaces\n"
[ "${INPUT_DEBUG:-off}" == "on" ]       && FEAT="${FEAT}🐛 Debug Mode\n"

MESSAGE="🔧 *DumpC2J Kernel Build*

📦 *Version:* \`${KERNEL_VER}\`
🌿 *Variant:* ${VARIANT_LABEL}
🔢 *HZ:* ${HZ_ID} Hz
🔗 *LTO:* ${LTO_ACTUAL}
⚙️ *Clang:* ${KBUILD_COMPILER_STRING}

*Features:*
$(printf '%b' "$FEAT")
*Changes:*
${CHANGELOG_TEXT}

📁 \`${ZIP_NAME}\`"

curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
  -d chat_id="${TELEGRAM_CHAT_ID}" \
  -d parse_mode="Markdown" \
  --data-urlencode text="$MESSAGE" > /dev/null

git tag -f "$TAG_NAME"
git push origin "$TAG_NAME" --force 2>/dev/null || echo "[!] Gagal push tag (cek GH_TOKEN)"
