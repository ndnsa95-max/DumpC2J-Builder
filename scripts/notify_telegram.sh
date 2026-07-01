#!/bin/bash
set -e

KERNEL_DIR="${GITHUB_WORKSPACE}/kernel-source"
cd "$KERNEL_DIR"

git fetch origin --tags 2>/dev/null || true

TAG_NAME="dumpc2j-last-notified"

if git rev-parse "$TAG_NAME" >/dev/null 2>&1; then
  RAW_LOG=$(git log "${TAG_NAME}..HEAD" --no-merges --pretty=format:"%s" | grep -vi '\[ci\]' || true)
else
  RAW_LOG=$(git log -10 --no-merges --pretty=format:"%s" | grep -vi '\[ci\]' || true)
fi

declare -A CL_GROUPS
CL_ORDER=(added fixed changed)
declare -A CL_LABELS=(
  [added]="Added"
  [fixed]="Fixed"
  [changed]="Changed"
)

while IFS= read -r line; do
  [ -z "$line" ] && continue
  type=$(echo "$line" | grep -oP '^[a-zA-Z]+(?=(\([^)]*\))?:)' || true)
  type=$(echo "$type" | tr '[:upper:]' '[:lower:]')
  desc="$line"
  while echo "$desc" | grep -qP '^[a-zA-Z]+(\([^)]*\))?:\s*'; do
    desc=$(echo "$desc" | sed -E 's/^[a-zA-Z]+(\([^)]*\))?:\s*//')
  done
  desc="$(tr '[:lower:]' '[:upper:]' <<< "${desc:0:1}")${desc:1}"

  case "$type" in
    feat) key="added" ;;
    fix)  key="fixed" ;;
    *)    key="changed" ;;
  esac
  CL_GROUPS[$key]="${CL_GROUPS[$key]}• ${desc}\n"
done <<< "$RAW_LOG"

CHANGELOG_TEXT=""
for key in "${CL_ORDER[@]}"; do
  if [ -n "${CL_GROUPS[$key]:-}" ]; then
    CHANGELOG_TEXT="${CHANGELOG_TEXT}*${CL_LABELS[$key]}:*\n$(printf '%b' "${CL_GROUPS[$key]}")\n"
  fi
done

[ -z "$CHANGELOG_TEXT" ] && CHANGELOG_TEXT="No changes since last build."

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
$(printf '%b' "$CHANGELOG_TEXT")

📁 \`${ZIP_NAME}\`"

curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
  -d chat_id="${TELEGRAM_CHAT_ID}" \
  -d parse_mode="Markdown" \
  --data-urlencode text="$MESSAGE" > /dev/null

git tag -f "$TAG_NAME"
git push origin "$TAG_NAME" --force 2>/dev/null || echo "[!] Gagal push tag (cek GH_TOKEN)"
