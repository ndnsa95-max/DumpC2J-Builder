#!/usr/bin/env bash
# setup_nomount.sh — Apply NoMount / ZeroMount kernel patch
# Usage: bash setup_nomount.sh <kernel_dir> <method: nomount|zeromount>
set -e

KERNEL_DIR="${1:-${GITHUB_WORKSPACE}/kernel-source}"
METHOD="${2:-nomount}"
NOMOUNT_DIR="${GITHUB_WORKSPACE}/builder/nomount-src"
NAMESPACE_C="$KERNEL_DIR/fs/namespace.c"

if [ ! -d "$KERNEL_DIR" ]; then
  echo "[!] Kernel dir not found: $KERNEL_DIR"
  exit 1
fi

echo "[*] Setting up $METHOD..."

# ── ZeroMount: driver sudah ada di drivers/zeromount/, tinggal enable config ──
if [ "$METHOD" == "zeromount" ]; then
  echo "[+] ZeroMount driver already integrated in drivers/zeromount/"
  echo "[+] CONFIG_ZEROMOUNT will be enabled via build config"
  echo "[+] ZeroMount setup complete"
  exit 0
fi

# ── NoMount: apply patch dari maxsteeel/NoMount ──
if [ ! -d "$NOMOUNT_DIR" ]; then
  mkdir -p "$NOMOUNT_DIR"
  echo "[*] Downloading NoMount source..."
  curl -sL https://raw.githubusercontent.com/maxsteeel/NoMount/main/kernel/src/nomount.c \
    -o "$NOMOUNT_DIR/nomount.c"
  curl -sL https://raw.githubusercontent.com/maxsteeel/NoMount/main/kernel/src/nomount.h \
    -o "$NOMOUNT_DIR/nomount.h"
  curl -sL https://raw.githubusercontent.com/maxsteeel/NoMount/main/kernel/patches/nomount_6.6_kernel_integration.patch \
    -o "$NOMOUNT_DIR/nomount_6.6.patch"
fi

if grep -q "CONFIG_NOMOUNT" "$KERNEL_DIR/fs/Kconfig" 2>/dev/null; then
  echo "[+] NoMount already patched, skipping"
else
  echo "[*] Applying nomount_6.6.patch..."
  if grep -q "KSU_NOMOUNT\|KSU_ZEROMOUNT" "$NAMESPACE_C" 2>/dev/null; then
    echo "[*] Removing old custom patch from namespace.c..."
    python3 - "$NAMESPACE_C" << 'PYEOF'
import sys, re
path = sys.argv[1]
content = open(path).read()
content = re.sub(r'\n#ifdef CONFIG_KSU_NOMOUNT.*?#endif /\* CONFIG_KSU_NOMOUNT \*/\n\n', '\n', content, flags=re.DOTALL)
content = re.sub(r'\n#ifdef CONFIG_KSU_ZEROMOUNT.*?#endif /\* CONFIG_KSU_ZEROMOUNT \*/\n\n', '\n', content, flags=re.DOTALL)
content = re.sub(r'\n#ifdef CONFIG_KSU_NOMOUNT\n\tif \(ksu_nomount_skip.*?#endif\n', '\n', content, flags=re.DOTALL)
content = re.sub(r'\n#ifdef CONFIG_KSU_ZEROMOUNT\n\tif \(ksu_zeromount_skip.*?#endif\n', '\n', content, flags=re.DOTALL)
open(path, 'w').write(content)
print("[+] Old custom patch removed")
PYEOF
  fi

  git -C "$KERNEL_DIR" apply --ignore-whitespace "$NOMOUNT_DIR/nomount_6.6.patch" && \
    echo "[+] Patch applied successfully" || \
    { echo "[!] Patch failed, trying with --reject..."; \
      git -C "$KERNEL_DIR" apply --ignore-whitespace --reject "$NOMOUNT_DIR/nomount_6.6.patch" || true; }
fi

cp "$NOMOUNT_DIR/nomount.c" "$KERNEL_DIR/fs/nomount.c"
cp "$NOMOUNT_DIR/nomount.h" "$KERNEL_DIR/fs/nomount.h"

echo "[+] NoMount setup complete"
