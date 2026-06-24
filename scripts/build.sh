#!/bin/bash
set -e

# ==========================================
# DumpC2J Kernel Build Script (Builder repo)
# ==========================================

KERNEL_DIR="${GITHUB_WORKSPACE}/kernel-source"
BUILDER_DIR="${GITHUB_WORKSPACE}/builder"
ANYKERNEL_DIR="${GITHUB_WORKSPACE}/anykernel"
OUT_DIR="${KERNEL_DIR}/out"
ZIMAGE_DIR="${OUT_DIR}/arch/arm64/boot"
MODULES_DIR="${KERNEL_DIR}/.root_modules"
BUILD_START=$(date +"%s")

VERSION="1.0"

# ==========================================
# Read inputs from env
# ==========================================
HZ="${INPUT_HZ:-250}"
VARIANT="${INPUT_VARIANT:-stock}"
ROOT="${INPUT_ROOT:-none}"
KPM="${INPUT_KPM:-off}"
KPM_SUPERKEY="${KPM_SUPERKEY_SECRET:-}"
HARDENED="${INPUT_HARDENED:-off}"
BYPASSCHARGING="${INPUT_BYPASS:-on}"
HTSR="${INPUT_HTSR:-on}"
WIFI_EXPLOIT="${INPUT_WIFI:-on}"
KGSL_EXPLOIT="${INPUT_KGSL:-on}"
DATA_EXPLOIT="${INPUT_DATA:-on}"
DROIDSPACES="${INPUT_DROIDSPACES:-off}"
DEBUG_MODE="${INPUT_DEBUG:-off}"
KERNEL_NAME="${INPUT_KERNEL_NAME:--DumpC2J-Kernel}"
SPOOF_UNAME="${INPUT_SPOOF_UNAME:-on}"
VERSION_SPOOF="${INPUT_VERSION_SPOOF:-}"

# Map HZ label to number
case "$HZ" in
  powersave) HZ_ID=100 ;;
  balance) HZ_ID=250 ;;
  performance) HZ_ID=500 ;;
  ultra-performance) HZ_ID=1000 ;;
  *) HZ_ID="${HZ}" ;;
esac

# Hostname spoof
export KBUILD_BUILD_USER="adennnqt"
export KBUILD_BUILD_HOST="DumpC2J"

# ==========================================
# Adjust inputs
# ==========================================
[ "$VARIANT" == "stock" ] && ROOT="none"

ACTUAL_ROOT="$ROOT"

KPM_PATCH="on"
if [ "$KPM" == "on" ] && [ "$ACTUAL_ROOT" == "resukisu" ]; then
  KPM_PATCH="off"
fi

LTO_VAL="full"
if [ "$KPM" == "on" ] || [ "$ACTUAL_ROOT" == "apatch" ] || [ "$ACTUAL_ROOT" == "folkpatch" ]; then
  LTO_VAL="thin"
fi

KPM_KEY=""
if [ "$KPM" == "on" ] || [ "$ACTUAL_ROOT" == "apatch" ] || [ "$ACTUAL_ROOT" == "folkpatch" ]; then
  KPM_KEY="$KPM_SUPERKEY"
  if [ -z "$KPM_KEY" ]; then
    KPM_KEY=$(tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 16)
    echo "[+] Auto-generated KPM SuperKey: $KPM_KEY"
  fi
fi

# ==========================================
# Apply kernel name & spoof uname to defconfig
# ==========================================
cd "$KERNEL_DIR"

echo "[*] Applying kernel name: $KERNEL_NAME"
if [ -n "$KERNEL_NAME" ]; then
  sed -i "s/CONFIG_LOCALVERSION=\".*\"/CONFIG_LOCALVERSION=\"$KERNEL_NAME\"/g" \
    arch/arm64/configs/konoha_defconfig
fi

if [ "$SPOOF_UNAME" == "on" ]; then
  sed -i "s/# CONFIG_KSU_SUSFS_SPOOF_UNAME is not set/CONFIG_KSU_SUSFS_SPOOF_UNAME=y/g" \
    arch/arm64/configs/konoha_defconfig
elif [ "$SPOOF_UNAME" == "off" ]; then
  sed -i "s/CONFIG_KSU_SUSFS_SPOOF_UNAME=y/# CONFIG_KSU_SUSFS_SPOOF_UNAME is not set/g" \
    arch/arm64/configs/konoha_defconfig
fi

# ==========================================
# Resolve Root
# ==========================================
case "$ROOT" in
  ksu)      ROOT_REPO="https://github.com/tiann/KernelSU.git"; REPO_NAME="KernelSU"; BRANCH="main" ;;
  sukisu)   ROOT_REPO="https://github.com/sukisu-ultra/sukisu-ultra.git"; REPO_NAME="sukisu-ultra"; BRANCH="main" ;;
  yukisu)   ROOT_REPO="https://github.com/Anatdx/YukiSU.git"; REPO_NAME="YukiSU"; BRANCH="main" ;;
  resukisu) ROOT_REPO="https://github.com/ReSukiSU/ReSukiSU.git"; REPO_NAME="ReSukiSU"; BRANCH="main" ;;
  mambosu)  ROOT_REPO="https://github.com/RapliVx/KernelSU.git"; REPO_NAME="MamboSU"; BRANCH="master" ;;
  apatch)   REPO_NAME="APatch" ;;
  folkpatch) REPO_NAME="FolkPatch" ;;
  ksu-next) ROOT_REPO="https://github.com/KernelSU-Next/KernelSU-Next.git"; REPO_NAME="KernelSU-Next"; BRANCH="dev" ;;
  *)        REPO_NAME="none" ;;
esac

# ==========================================
# Setup Root Module
# ==========================================
rm -rf "$KERNEL_DIR/drivers/kernelsu"

if [ "$VARIANT" == "stock" ]; then
  mkdir -p "$KERNEL_DIR/drivers/kernelsu"
  touch "$KERNEL_DIR/drivers/kernelsu/Kconfig"
  touch "$KERNEL_DIR/drivers/kernelsu/Makefile"
elif [ "$ROOT" == "apatch" ] || [ "$ROOT" == "folkpatch" ]; then
  echo "[+] Using $REPO_NAME (binary patcher) — creating dummy KernelSU module"
  mkdir -p "$KERNEL_DIR/drivers/kernelsu"
  touch "$KERNEL_DIR/drivers/kernelsu/Kconfig"
  touch "$KERNEL_DIR/drivers/kernelsu/Makefile"
  KPM="on"
else
  mkdir -p "$MODULES_DIR"
  if [ ! -d "$MODULES_DIR/$REPO_NAME" ]; then
    echo "[+] Cloning $REPO_NAME..."
    git clone -b "$BRANCH" "$ROOT_REPO" "$MODULES_DIR/$REPO_NAME"
  else
    echo "[+] Updating $REPO_NAME..."
    (cd "$MODULES_DIR/$REPO_NAME" && git fetch origin && git reset --hard "origin/$BRANCH" || true)
  fi

  # SUSFS
  if [ "$VARIANT" == "susfs" ]; then
    SUSFS_DIR="$MODULES_DIR/susfs4ksu"
    if [ ! -d "$SUSFS_DIR" ]; then
      git clone https://gitlab.com/simonpunk/susfs4ksu.git -b gki-android15-6.6-dev "$SUSFS_DIR"
    else
      (cd "$SUSFS_DIR" && git fetch origin && git reset --hard origin/gki-android15-6.6-dev || true)
    fi

    echo "[+] Injecting SUSFS kernel sources..."
    cp "$SUSFS_DIR/kernel_patches/fs/susfs.c" "$KERNEL_DIR/fs/susfs.c"
    cp "$SUSFS_DIR/kernel_patches/include/linux/susfs.h" "$KERNEL_DIR/include/linux/susfs.h"
    [ -f "$SUSFS_DIR/kernel_patches/include/linux/susfs_def.h" ] && \
      cp "$SUSFS_DIR/kernel_patches/include/linux/susfs_def.h" "$KERNEL_DIR/include/linux/susfs_def.h"

    SUSFS_DEF_H="$KERNEL_DIR/include/linux/susfs_def.h"
    if [ -f "$SUSFS_DEF_H" ] && ! grep -q "linux/sched.h" "$SUSFS_DEF_H" 2>/dev/null; then
      sed -i '/#include <linux\/bits.h>/a\
#include <linux\/sched.h>\
#include <linux\/thread_info.h>\
#include <linux\/cred.h>\
#include <asm\/current.h>' "$SUSFS_DEF_H"
    fi

    if grep -q "config KSU_SUSFS" "$MODULES_DIR/$REPO_NAME/kernel/Kconfig" 2>/dev/null; then
      echo "[+] $REPO_NAME already has native SUSFS integration. Skipping patch..."
    else
      echo "[+] Patching $REPO_NAME for SUSFS..."
      (cd "$MODULES_DIR/$REPO_NAME" && \
        patch -p1 --forward -f --reject-file=- \
        < "$SUSFS_DIR/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch" || true)
    fi
  fi

  # SukiSU/YukiSU uapi symlink
  if [ ! -d "$MODULES_DIR/$REPO_NAME/kernel/uapi" ] && [ -d "$MODULES_DIR/$REPO_NAME/uapi" ]; then
    ln -sfn ../uapi "$MODULES_DIR/$REPO_NAME/kernel/uapi"
  fi

  # SukiSU/YukiSU KPM header fixes
  if { [ "$ROOT" == "sukisu" ] || [ "$ROOT" == "yukisu" ]; } && [ "$KPM" == "on" ]; then
    KPM_HEADER="$MODULES_DIR/$REPO_NAME/kernel/kpm/kpm.h"
    KPM_COMPACT="$MODULES_DIR/$REPO_NAME/kernel/kpm/compact.c"
    SUPERCALL_UAPI="$MODULES_DIR/$REPO_NAME/uapi/supercall.h"
    ALLOWLIST_H="$MODULES_DIR/$REPO_NAME/kernel/policy/allowlist.h"
    KSU_KBUILD="$MODULES_DIR/$REPO_NAME/kernel/Kbuild"

    [ -f "$KPM_HEADER" ] && grep -q '#include "uapi/supercall.h"' "$KPM_HEADER" && \
      sed -i 's|#include "uapi/supercall.h"|#include "../../uapi/supercall.h"|' "$KPM_HEADER"
    [ -f "$SUPERCALL_UAPI" ] && grep -q '#include "uapi/app_profile.h"' "$SUPERCALL_UAPI" && \
      sed -i 's|#include "uapi/app_profile.h"|#include "app_profile.h"|' "$SUPERCALL_UAPI"
    [ -f "$KPM_COMPACT" ] && grep -q '#include "policy/allowlist.h"' "$KPM_COMPACT" && \
      sed -i 's|#include "policy/allowlist.h"|#include "../policy/allowlist.h"|' "$KPM_COMPACT"
    [ -f "$KPM_COMPACT" ] && grep -q '#include "manager/manager_identity.h"' "$KPM_COMPACT" && \
      sed -i 's|#include "manager/manager_identity.h"|#include "../manager/manager_identity.h"|' "$KPM_COMPACT"
    [ -f "$ALLOWLIST_H" ] && grep -q '#include "uapi/app_profile.h"' "$ALLOWLIST_H" && \
      sed -i 's|#include "uapi/app_profile.h"|#include "../uapi/app_profile.h"|' "$ALLOWLIST_H"
    [ -f "$KSU_KBUILD" ] && ! grep -q '\-I$(KSU_KERNEL_DIR)/\.\.' "$KSU_KBUILD" && \
      sed -i 's|ccflags-y += -I$(KSU_KERNEL_DIR) -I$(KSU_KERNEL_DIR)/include|ccflags-y += -I$(KSU_KERNEL_DIR) -I$(KSU_KERNEL_DIR)/include -I$(KSU_KERNEL_DIR)/..|' "$KSU_KBUILD"
  fi

  echo "[+] Symlinking $REPO_NAME to drivers/kernelsu..."
  ln -sf "$MODULES_DIR/$REPO_NAME/kernel" "$KERNEL_DIR/drivers/kernelsu"
fi

# SUSFS fixup
if [ "$VARIANT" == "susfs" ]; then
  echo "[+] Running SUSFS fixup..."
  bash "$KERNEL_DIR/ksu_susfs_fixup.sh" "$KERNEL_DIR/drivers/kernelsu" "$ROOT"
fi

# ==========================================
# Baseband-guard
# ==========================================
BBG_DIR="$KERNEL_DIR/Baseband-guard"
if [ ! -d "$BBG_DIR" ]; then
  git clone https://github.com/vc-teahouse/Baseband-guard.git "$BBG_DIR"
fi
echo "[+] Running Baseband-guard setup..."
(cd "$KERNEL_DIR" && sh "$BBG_DIR/setup.sh")

# ==========================================
# KPM Tools
# ==========================================
if [ "$KPM" == "on" ]; then
  KPM_TOOLS_DIR="$MODULES_DIR/kpm_tools"
  mkdir -p "$KPM_TOOLS_DIR"

  if [ "$ROOT" == "apatch" ] || [ "$ROOT" == "folkpatch" ]; then
    if [ "$ROOT" == "folkpatch" ]; then
      KPM_RELEASE_BASE="https://github.com/LyraVoid/KernelPatch/releases/download/0.13.1"
      KPIMG_NAME="kpimg-android"
    else
      KPM_RELEASE_BASE="https://github.com/bmax121/KernelPatch/releases/latest/download"
      KPIMG_NAME="kpimg-android"
    fi
  else
    KPM_RELEASE_BASE="https://github.com/SukiSU-Ultra/SukiSU_KernelPatch_patch/releases/latest/download"
    KPIMG_NAME="kpimg"
  fi

  KPTOOLS_BIN="$KPM_TOOLS_DIR/kptools-linux"
  KPIMG_BIN="$KPM_TOOLS_DIR/$KPIMG_NAME"

  if [ ! -f "$KPTOOLS_BIN" ] || [ ! -f "$KPIMG_BIN" ]; then
    echo "[+] Downloading KPM tools..."
    if [ "$ROOT" == "folkpatch" ]; then
      KPTOOLS_URL="https://github.com/LyraVoid/KernelPatch/releases/download/0.13.1/kptools-linux"
    else
      KPTOOLS_URL="$KPM_RELEASE_BASE/kptools-linux"
    fi
    curl -LSs -o "$KPTOOLS_BIN" "$KPTOOLS_URL"
    curl -LSs -o "$KPIMG_BIN" "$KPM_RELEASE_BASE/$KPIMG_NAME"
    chmod +x "$KPTOOLS_BIN"
  fi
fi

# ==========================================
# Export ARCH
# ==========================================
export ARCH=arm64
export SUBARCH=arm64

# ==========================================
# Clang flags
# ==========================================
EXTREME_CLANG_FLAGS=(
  -O2 -mcpu=cortex-x4 -mtune=cortex-x4
  -mno-fmv -mno-outline-atomics -Wno-all
  -fomit-frame-pointer -fslp-vectorize
  -fdelete-null-pointer-checks -moutline
  -mharden-sls=none -mbranch-protection=none
  -fno-semantic-interposition -fno-stack-protector
  -fno-math-errno -fno-trapping-math
  -fno-signed-zeros -fassociative-math -freciprocal-math
)
KERNEL_KCFLAGS="-w ${EXTREME_CLANG_FLAGS[*]}"

[ "$BYPASSCHARGING" == "on" ] && KERNEL_KCFLAGS="$KERNEL_KCFLAGS -DCONFIG_MCA_BYPASS=1"
[ "$HTSR" == "on" ] && KERNEL_KCFLAGS="$KERNEL_KCFLAGS -DCONFIG_HTSR_240=1"
[ "$WIFI_EXPLOIT" == "on" ] && KERNEL_KCFLAGS="$KERNEL_KCFLAGS -DCONFIG_WIFI_EXPLOIT=1"
[ "$KGSL_EXPLOIT" == "on" ] && KERNEL_KCFLAGS="$KERNEL_KCFLAGS -DCONFIG_KGSL_EXPLOIT=1"
[ "$DATA_EXPLOIT" == "on" ] && KERNEL_KCFLAGS="$KERNEL_KCFLAGS -DCONFIG_DATA_EXPLOIT=1"

if [ "$DEBUG_MODE" == "off" ]; then
  KERNEL_KCFLAGS="$KERNEL_KCFLAGS -fmerge-all-constants"
  KERNEL_LDFLAGS="--icf=all"
else
  KERNEL_LDFLAGS=""
fi

# ==========================================
# Clang path
# ==========================================
export PATH="${CLANG_PATH}:$PATH"

# ccache-ECS integration (LuminaireProtocol pattern)
CCACHE_BIN="${HOME}/ccache-bin/ccache"
if [ -f "$CCACHE_BIN" ]; then
  export CCACHE_COMPILER="${CLANG_PATH}/clang"
  export CCACHE_BASEDIR="${KERNEL_DIR}"
  export CCACHE_IS_KERNEL_COMPILING="true"
  export CCACHE_COMPRESS=1
  export CCACHE_COMPRESSLEVEL=1
  export PATH="${HOME}/ccache-bin:${PATH}"
  # Bikin wrapper script clang -> ccache
  WRAPPER="${GITHUB_WORKSPACE}/clang-ccache"
  {
    echo "#!/bin/sh"
    echo "export CCACHE_IS_KERNEL_COMPILING=true"
    echo "export CCACHE_BASEDIR=${KERNEL_DIR}"
    echo "export CCACHE_DIR=/home/runner/.ccache"
    echo "export CCACHE_COMPILER=${CLANG_PATH}/clang"
    echo "exec ${CCACHE_BIN} ${CLANG_PATH}/clang \"\$@\""
  } > "$WRAPPER"
  chmod +x "$WRAPPER"
  export CC_CCACHE="$WRAPPER"
  echo "[+] ccache-ECS active via wrapper"
else
  echo "[!] ccache-ECS not found, skipping"
fi
CLANG_BIN="${CLANG_PATH}/clang"
# KBUILD_COMPILER_STRING already set by setup_clang.sh
echo "[+] Using Clang: $COMPILER_VER"

# ==========================================
# Kernel config
# ==========================================
mkdir -p "$OUT_DIR"
make -C "$KERNEL_DIR" O="$OUT_DIR" CC=clang LLVM=1 LLVM_IAS=1 \
  KCFLAGS="$KERNEL_KCFLAGS" LDFLAGS="$KERNEL_LDFLAGS" konoha_defconfig

# Disable VDSO32 & COMPAT_VDSO (wajib untuk Cirrus)
"$KERNEL_DIR/scripts/config" --file "$OUT_DIR/.config" \
  -d CONFIG_VDSO32 -d CONFIG_COMPAT_VDSO

# Root config
case "$VARIANT" in
  stock) "$KERNEL_DIR/scripts/config" --file "$OUT_DIR/.config" \
    -d CONFIG_KSU -d CONFIG_KSU_SUSFS -d CONFIG_KPM ;;
  root)  "$KERNEL_DIR/scripts/config" --file "$OUT_DIR/.config" \
    -e CONFIG_KSU -d CONFIG_KSU_SUSFS ;;
  susfs) "$KERNEL_DIR/scripts/config" --file "$OUT_DIR/.config" \
    -e CONFIG_KSU -e CONFIG_KSU_SUSFS -e CONFIG_KSU_SUSFS_SUS_MAP ;;
esac

# KPM config
if [ "$ROOT" == "apatch" ] || [ "$ROOT" == "folkpatch" ]; then
  "$KERNEL_DIR/scripts/config" --file "$OUT_DIR/.config" \
    -d CONFIG_KSU -e CONFIG_KPM -e CONFIG_KALLSYMS -e CONFIG_KALLSYMS_ALL
elif [ "$KPM" == "on" ]; then
  "$KERNEL_DIR/scripts/config" --file "$OUT_DIR/.config" \
    -e CONFIG_KPM -e CONFIG_KALLSYMS -e CONFIG_KALLSYMS_ALL
else
  "$KERNEL_DIR/scripts/config" --file "$OUT_DIR/.config" -d CONFIG_KPM
fi

# HZ config
case "$HZ_ID" in
  100)  "$KERNEL_DIR/scripts/config" --file "$OUT_DIR/.config" \
    -d CONFIG_HZ_300 -d CONFIG_HZ_250 -d CONFIG_HZ_500 -d CONFIG_HZ_1000 \
    -e CONFIG_HZ_100 --set-val CONFIG_HZ 100 -e CONFIG_RCU_LAZY ;;
  500)  "$KERNEL_DIR/scripts/config" --file "$OUT_DIR/.config" \
    -d CONFIG_HZ_300 -d CONFIG_HZ_250 -d CONFIG_HZ_100 -d CONFIG_HZ_1000 \
    -e CONFIG_HZ_500 --set-val CONFIG_HZ 500 -d CONFIG_RCU_LAZY ;;
  1000) "$KERNEL_DIR/scripts/config" --file "$OUT_DIR/.config" \
    -d CONFIG_HZ_300 -d CONFIG_HZ_250 -d CONFIG_HZ_100 -d CONFIG_HZ_500 \
    -e CONFIG_HZ_1000 --set-val CONFIG_HZ 1000 -d CONFIG_RCU_LAZY ;;
  *)    "$KERNEL_DIR/scripts/config" --file "$OUT_DIR/.config" \
    -d CONFIG_HZ_300 -d CONFIG_HZ_1000 -d CONFIG_HZ_100 -d CONFIG_HZ_500 \
    -e CONFIG_HZ_250 --set-val CONFIG_HZ 250 ;;
esac

# Hardened
[ "$HARDENED" == "off" ] && "$KERNEL_DIR/scripts/config" --file "$OUT_DIR/.config" \
  -d CONFIG_CPU_MITIGATIONS -d CONFIG_MITIGATE_SPECTRE_BRANCH_HISTORY

# LTO
case "$LTO_VAL" in
  full) "$KERNEL_DIR/scripts/config" --file "$OUT_DIR/.config" \
    -d CONFIG_LTO_NONE -d CONFIG_LTO_CLANG_THIN -e CONFIG_LTO_CLANG -e CONFIG_LTO_CLANG_FULL ;;
  none) "$KERNEL_DIR/scripts/config" --file "$OUT_DIR/.config" \
    -d CONFIG_LTO_CLANG -d CONFIG_LTO_CLANG_FULL -d CONFIG_LTO_CLANG_THIN -e CONFIG_LTO_NONE ;;
  *)    "$KERNEL_DIR/scripts/config" --file "$OUT_DIR/.config" \
    -d CONFIG_LTO_NONE -d CONFIG_LTO_CLANG_FULL -e CONFIG_LTO_CLANG -e CONFIG_LTO_CLANG_THIN ;;
esac

# Debug reduction
"$KERNEL_DIR/scripts/config" --file "$OUT_DIR/.config" \
  -e CONFIG_DEBUG_INFO_REDUCED \
  -d CONFIG_DEBUG_MISC -d CONFIG_BT_DEBUGFS \
  -d CONFIG_DEBUG_MEMORY_INIT -d CONFIG_PROFILING \
  -d CONFIG_PRINTK_CALLER -d CONFIG_RCU_TRACE \
  -d CONFIG_CMA_DEBUGFS \
  -d CONFIG_UBSAN -d CONFIG_UBSAN_BOUNDS \
  -d CONFIG_UBSAN_ARRAY_BOUNDS -d CONFIG_UBSAN_LOCAL_BOUNDS \
  -d CONFIG_UBSAN_SANITIZE_ALL -d CONFIG_UBSAN_TRAP \
  -d CONFIG_CLEANCACHE -d CONFIG_PRINTK_TIME

# Kernel version spoof
if [ -n "$VERSION_SPOOF" ]; then
  echo "[*] Spoofing kernel version: $VERSION_SPOOF"
  IFS='.' read -r V PL SL <<< "$VERSION_SPOOF"
  sed -i "s/^VERSION = .*/VERSION = $V/" "$KERNEL_DIR/Makefile"
  sed -i "s/^PATCHLEVEL = .*/PATCHLEVEL = $PL/" "$KERNEL_DIR/Makefile"
  sed -i "s/^SUBLEVEL = .*/SUBLEVEL = $SL/" "$KERNEL_DIR/Makefile"
fi

# Cmdline extras
CURRENT_CMDLINE=$(grep '^CONFIG_CMDLINE=' "$OUT_DIR/.config" | sed 's/^CONFIG_CMDLINE="//' | sed 's/"$//')
CMDLINE_APPEND=""
echo "$CURRENT_CMDLINE" | grep -q "kasan=off" || CMDLINE_APPEND="$CMDLINE_APPEND kasan=off"
echo "$CURRENT_CMDLINE" | grep -q "panic_on_rcu_stall" || CMDLINE_APPEND="$CMDLINE_APPEND kernel.panic_on_rcu_stall=0"
echo "$CURRENT_CMDLINE" | grep -q "init_on_alloc=" || CMDLINE_APPEND="$CMDLINE_APPEND init_on_alloc=0"
echo "$CURRENT_CMDLINE" | grep -q "page_alloc.shuffle=" || CMDLINE_APPEND="$CMDLINE_APPEND page_alloc.shuffle=0"
echo "$CURRENT_CMDLINE" | grep -q "randomize_kstack_offset=" || CMDLINE_APPEND="$CMDLINE_APPEND randomize_kstack_offset=0"
echo "$CURRENT_CMDLINE" | grep -q "loglevel=" || CMDLINE_APPEND="$CMDLINE_APPEND loglevel=0"
[ "$DEBUG_MODE" == "on" ] && echo "$CURRENT_CMDLINE" | grep -q "nokaslr" || \
  { [ "$DEBUG_MODE" == "on" ] && CMDLINE_APPEND="$CMDLINE_APPEND nokaslr"; }
[ -n "$CMDLINE_APPEND" ] && \
  "$KERNEL_DIR/scripts/config" --file "$OUT_DIR/.config" \
  --set-str CONFIG_CMDLINE "$CURRENT_CMDLINE$CMDLINE_APPEND"

# Droidspaces
[ "$DROIDSPACES" == "on" ] && \
  bash "$KERNEL_DIR/setup_droidspaces.sh" "$OUT_DIR"

# Finalize config
make -C "$KERNEL_DIR" O="$OUT_DIR" CC=clang LLVM=1 LLVM_IAS=1 olddefconfig

# ==========================================
# Build
# ==========================================
CPUS=$(nproc --all)
echo "[+] Building with ${CPUS} threads..."

echo "[DEBUG] CC_CCACHE=${CC_CCACHE:-EMPTY}"
[ -f "${CC_CCACHE}" ] && cat "${CC_CCACHE}" || echo "[DEBUG] wrapper not found"
make -C "$KERNEL_DIR" \
  "-j${CPUS}" O="$OUT_DIR" \
  LD=ld.lld AR=llvm-ar NM=llvm-nm \
  OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip \
  LLVM=1 LLVM_IAS=1 \
  KCFLAGS="$KERNEL_KCFLAGS" LDFLAGS="$KERNEL_LDFLAGS" \
  || { echo "[-] Build failed!"; exit 1; }

# ==========================================
# KPM Post-Build
# ==========================================
if [ "$KPM" == "on" ] && [ "$KPM_PATCH" == "on" ]; then
  RAW_IMAGE="$ZIMAGE_DIR/Image"
  [ ! -f "$RAW_IMAGE" ] && [ -f "$ZIMAGE_DIR/Image.gz" ] && gzip -dk "$ZIMAGE_DIR/Image.gz"
  cp "$RAW_IMAGE" "${RAW_IMAGE}.orig"
  "$KPTOOLS_BIN" -p -i "${RAW_IMAGE}.orig" -S "$KPM_KEY" -k "$KPIMG_BIN" -o "$RAW_IMAGE"
  rm -f "${RAW_IMAGE}.orig"
  [ -f "$ZIMAGE_DIR/Image.gz" ] && gzip -nkf "$RAW_IMAGE"
  echo "[+] KPM patching done. SuperKey: $KPM_KEY"
fi

# ==========================================
# Package
# ==========================================
TIME=$(date "+%Y%m%d-%H%M%S")
TEMP_DIR="${GITHUB_WORKSPACE}/anykernel_temp"
rm -rf "$TEMP_DIR"
cp -r "$ANYKERNEL_DIR" "$TEMP_DIR"

for img in Image.gz-dtb Image.gz Image; do
  [ -f "$ZIMAGE_DIR/$img" ] && { cp -v "$ZIMAGE_DIR/$img" "$TEMP_DIR/"; break; }
done

# Build zip name
ZIP_SUFFIX=""
case "$VARIANT" in
  stock) ZIP_SUFFIX="-stock" ;;
  root)  ZIP_SUFFIX="-root-$REPO_NAME" ;;
  susfs) ZIP_SUFFIX="-susfs-$REPO_NAME" ;;
esac
[ "$KPM" == "on" ] && ZIP_SUFFIX="${ZIP_SUFFIX}-kpm"
[ "$HARDENED" == "on" ] && ZIP_SUFFIX="${ZIP_SUFFIX}-hardened"
[ "$BYPASSCHARGING" == "on" ] && ZIP_SUFFIX="${ZIP_SUFFIX}-bypasscharging"
[ "$DROIDSPACES" == "on" ] && ZIP_SUFFIX="${ZIP_SUFFIX}-droidspaces"
[ "$HTSR" == "off" ] && ZIP_SUFFIX="${ZIP_SUFFIX}-nohtsr"
[ "$WIFI_EXPLOIT" == "off" ] && ZIP_SUFFIX="${ZIP_SUFFIX}-nowifi"
[ "$KGSL_EXPLOIT" == "off" ] && ZIP_SUFFIX="${ZIP_SUFFIX}-nokgsl"
[ "$DATA_EXPLOIT" == "off" ] && ZIP_SUFFIX="${ZIP_SUFFIX}-nodata"

case "$HZ_ID" in
  100) HZ_LABEL="-powersave" ;;
  500) HZ_LABEL="-performance" ;;
  1000) HZ_LABEL="-ultra-performance" ;;
  *) HZ_LABEL="-balance" ;;
esac

ZIP_NAME="DumpC2J-${VERSION}${ZIP_SUFFIX}${HZ_LABEL}-${TIME}.zip"
cd "$TEMP_DIR" && zip -r9 "${GITHUB_WORKSPACE}/$ZIP_NAME" . \
  -x '.git*' -x 'README.md' -x '*placeholder' > /dev/null
cd "$GITHUB_WORKSPACE"
rm -rf "$TEMP_DIR"

mkdir -p "$KERNEL_DIR/DumpC2J-Release"
cp "$ZIP_NAME" "$KERNEL_DIR/DumpC2J-Release/"

echo "ZIP_NAME=$ZIP_NAME" >> "$GITHUB_ENV"
[ "$KPM" == "on" ] && echo "KPM_SUPERKEY=$KPM_KEY" >> "$GITHUB_ENV"

# ccache stats
[ -f "${HOME}/ccache-bin/ccache" ] && ${HOME}/ccache-bin/ccache --show-stats || true

BUILD_END=$(date +"%s")
DIFF=$((BUILD_END - BUILD_START))
echo ""
echo "=========================================="
echo "Build done in $((DIFF / 60))m $((DIFF % 60))s"
echo "Output: $ZIP_NAME"
echo "=========================================="
