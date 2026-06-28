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
NOMOUNT="${INPUT_NOMOUNT:-off}"

# Map HZ label to number
case "$HZ" in
  powersave) HZ_ID=100 ;;
  balance) HZ_ID=250 ;;
  smooth) HZ_ID=300 ;;
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
    git clone --depth=1 -b "$BRANCH" "$ROOT_REPO" "$MODULES_DIR/$REPO_NAME"
  else
    echo "[+] Updating $REPO_NAME..."
    (cd "$MODULES_DIR/$REPO_NAME" && git fetch origin && git reset --hard "origin/$BRANCH" || true)
  fi

  # SUSFS
  if [ "$VARIANT" == "susfs" ]; then
    SUSFS_DIR="$MODULES_DIR/susfs4ksu"
    if [ ! -d "$SUSFS_DIR" ]; then
      git clone --depth=1 https://gitlab.com/simonpunk/susfs4ksu.git -b gki-android15-6.6-dev "$SUSFS_DIR"
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
  git clone --depth=1 https://github.com/vc-teahouse/Baseband-guard.git "$BBG_DIR"
else
  (cd "$BBG_DIR" && git fetch origin && git reset --hard origin/main || true)
fi
echo "[+] Running Baseband-guard setup..."
(cd "$KERNEL_DIR" && sh "$BBG_DIR/setup.sh")

# ==========================================
# Re-Kernel Integration
# ==========================================
echo "[*] Integrating Re-Kernel..."

# Tulis rekernel.h
python3 -c "
import os
h = open('$KERNEL_DIR/drivers/android/rekernel.h', 'w')
h.write('''#ifndef REKERNEL_H\n#define REKERNEL_H\n#include <linux/init.h>\n#include <linux/types.h>\n#include <net/sock.h>\n#include <linux/netlink.h>\n#include <linux/proc_fs.h>\n#include <linux/freezer.h>\n#include <linux/sched/jobctl.h>\n\n#define NETLINK_REKERNEL_MAX 26\n#define NETLINK_REKERNEL_MIN 22\n#define USER_PORT 100\n#define PACKET_SIZE 128\n#define MIN_USERAPP_UID (10000)\n#define MAX_SYSTEM_UID (2000)\n#define RESERVE_ORDER 17\n#define WARN_AHEAD_SPACE (1 << RESERVE_ORDER)\n\nstatic struct sock *rekernel_netlink = NULL;\nextern struct net init_net;\nstatic int netlink_unit = NETLINK_REKERNEL_MIN;\n\nstatic inline bool line_is_frozen(struct task_struct *task) {\n    return frozen(task->group_leader) || freezing(task->group_leader);\n}\n\nstatic int send_netlink_message(char *msg, uint16_t len) {\n    struct sk_buff *skbuffer;\n    struct nlmsghdr *nlhdr;\n    skbuffer = nlmsg_new(len, GFP_ATOMIC);\n    if (!skbuffer) { printk(\"netlink alloc failure.\\\\n\"); return -1; }\n    nlhdr = nlmsg_put(skbuffer, 0, 0, netlink_unit, len, 0);\n    if (!nlhdr) { printk(\"nlmsg_put failure.\\\\n\"); nlmsg_free(skbuffer); return -1; }\n    memcpy(nlmsg_data(nlhdr), msg, len);\n    return netlink_unicast(rekernel_netlink, skbuffer, USER_PORT, MSG_DONTWAIT);\n}\n\nstatic void netlink_rcv_msg(struct sk_buff *skbuffer) {}\nstatic struct netlink_kernel_cfg rekernel_cfg = { .input = netlink_rcv_msg };\n\nstatic int rekernel_unit_show(struct seq_file *m, void *v) {\n    seq_printf(m, \"%d\\\\n\", netlink_unit); return 0;\n}\nstatic int rekernel_unit_open(struct inode *inode, struct file *file) {\n    return single_open(file, rekernel_unit_show, NULL);\n}\nstatic const struct proc_ops rekernel_unit_fops = {\n    .proc_open = rekernel_unit_open, .proc_read = seq_read,\n    .proc_lseek = seq_lseek, .proc_release = single_release,\n};\n\nstatic struct proc_dir_entry *rekernel_dir, *rekernel_unit_entry;\n\nstatic int start_rekernel_server(void) {\n    if (rekernel_netlink != NULL) return 0;\n    for (netlink_unit = NETLINK_REKERNEL_MIN; netlink_unit < NETLINK_REKERNEL_MAX; netlink_unit++) {\n        rekernel_netlink = (struct sock *)netlink_kernel_create(&init_net, netlink_unit, &rekernel_cfg);\n        if (rekernel_netlink != NULL) break;\n    }\n    if (rekernel_netlink == NULL) { printk(\"Failed to create Re:Kernel server!\\\\n\"); return -1; }\n    printk(\"Created Re:Kernel server! NETLINK UNIT: %d\\\\n\", netlink_unit);\n    rekernel_dir = proc_mkdir(\"rekernel\", NULL);\n    if (!rekernel_dir) printk(\"create /proc/rekernel failed!\\\\n\");\n    else {\n        char buff[32];\n        sprintf(buff, \"%d\", netlink_unit);\n        rekernel_unit_entry = proc_create(buff, 0644, rekernel_dir, &rekernel_unit_fops);\n        if (!rekernel_unit_entry) printk(\"create rekernel unit failed!\\\\n\");\n    }\n    return 0;\n}\n#endif\n''')
h.close()
print('[+] rekernel.h written')
"

# Patch binder.c dan signal.c via Python
python3 << RKPY
import sys

import os; KERNEL_DIR = os.path.join(os.environ.get('GITHUB_WORKSPACE', ''), 'kernel-source')

# === binder.c ===
bc_path = f"{KERNEL_DIR}/drivers/android/binder.c"
with open(bc_path) as f:
    bc = f.read()

if '#include "rekernel.h"' not in bc:
    bc = bc.replace('#include "binder_trace.h"', '#include "binder_trace.h"\n#include "rekernel.h"')
    print("[+] binder.c: header injected")

reply_hook = '\n\t\t/* rekernel reply hook */\n\t\tif (start_rekernel_server() == 0) {\n\t\t\tif (target_proc && target_proc->tsk && proc->tsk\n\t\t\t\t&& (task_uid(target_proc->tsk).val <= MAX_SYSTEM_UID)\n\t\t\t\t&& (proc->pid != target_proc->pid)\n\t\t\t\t&& line_is_frozen(target_proc->tsk)) {\n\t\t\t\tchar binder_kmsg[PACKET_SIZE];\n\t\t\t\tsnprintf(binder_kmsg, sizeof(binder_kmsg), "type=Binder,bindertype=reply,oneway=0,from_pid=%d,from=%d,target_pid=%d,target=%d;", proc->pid, task_uid(proc->tsk).val, target_proc->pid, task_uid(target_proc->tsk).val);\n\t\t\t\tsend_netlink_message(binder_kmsg, strlen(binder_kmsg));\n\t\t\t}\n\t\t}'

txn_hook = '\n\t\t/* rekernel txn hook */\n\t\tif (start_rekernel_server() == 0) {\n\t\t\tif (target_proc && target_proc->tsk && proc->tsk\n\t\t\t\t&& (task_uid(target_proc->tsk).val > MIN_USERAPP_UID)\n\t\t\t\t&& (proc->pid != target_proc->pid)\n\t\t\t\t&& line_is_frozen(target_proc->tsk)) {\n\t\t\t\tchar binder_kmsg[PACKET_SIZE];\n\t\t\t\tsnprintf(binder_kmsg, sizeof(binder_kmsg), "type=Binder,bindertype=transaction,oneway=%d,from_pid=%d,from=%d,target_pid=%d,target=%d;", tr->flags & TF_ONE_WAY, proc->pid, task_uid(proc->tsk).val, target_proc->pid, task_uid(target_proc->tsk).val);\n\t\t\t\tsend_netlink_message(binder_kmsg, strlen(binder_kmsg));\n\t\t\t}\n\t\t}'

if 'rekernel reply hook' not in bc:
    anchor = '\t\t\tbinder_inner_proc_unlock(target_thread->proc);\n\t\t\ttrace_android_vh_binder_reply(target_proc, proc, thread, tr);\n\t} else {'
    if anchor in bc:
        bc = bc.replace(anchor, '\t\t\tbinder_inner_proc_unlock(target_thread->proc);' + reply_hook + '\n\t\t\ttrace_android_vh_binder_reply(target_proc, proc, thread, tr);\n\t} else {')
        print("[+] binder.c: reply hook injected")
    else:
        print("[-] binder.c: reply anchor NOT FOUND", file=sys.stderr)

if 'rekernel txn hook' not in bc:
    anchor = '\t\tif (security_binder_transaction(proc->cred,'
    if anchor in bc:
        bc = bc.replace(anchor, txn_hook + '\n\t\tif (security_binder_transaction(proc->cred,')
        print("[+] binder.c: txn hook injected")
    else:
        print("[-] binder.c: txn anchor NOT FOUND", file=sys.stderr)

with open(bc_path, 'w') as f:
    f.write(bc)

# === signal.c ===
sc_path = f"{KERNEL_DIR}/kernel/signal.c"
with open(sc_path) as f:
    sc = f.read()

if '#include "../drivers/android/rekernel.h"' not in sc:
    sc = sc.replace('#include <linux/freezer.h>', '#include <linux/freezer.h>\n#include "../drivers/android/rekernel.h"')
    print("[+] signal.c: header injected")

sig_hook = '\n\t/* rekernel signal hook */\n\tif (start_rekernel_server() == 0) {\n\t\tif (line_is_frozen(current) && (sig == SIGKILL || sig == SIGTERM || sig == SIGABRT || sig == SIGQUIT)) {\n\t\t\tchar binder_kmsg[PACKET_SIZE];\n\t\t\tsnprintf(binder_kmsg, sizeof(binder_kmsg), "type=Signal,signal=%d,killer_pid=%d,killer=%d,dst_pid=%d,dst=%d;", sig, task_tgid_nr(p), task_uid(p).val, task_tgid_nr(current), task_uid(current).val);\n\t\t\tsend_netlink_message(binder_kmsg, strlen(binder_kmsg));\n\t\t}\n\t}'

if 'rekernel signal hook' not in sc:
    anchor = '\tint ret = -ESRCH;\n\ttrace_android_vh_do_send_sig_info(sig, current, p);\n\tif (lock_task_sighand'
    if anchor in sc:
        sc = sc.replace(anchor, '\tint ret = -ESRCH;' + sig_hook + '\n\ttrace_android_vh_do_send_sig_info(sig, current, p);\n\tif (lock_task_sighand')
        print("[+] signal.c: signal hook injected")
    else:
        print("[-] signal.c: anchor NOT FOUND", file=sys.stderr)

with open(sc_path, 'w') as f:
    f.write(sc)

print("[+] Re-Kernel patching done!")
RKPY

echo "[+] Re-Kernel integration done!"




# ==========================================
# KPM Tools
# ==========================================
if [ "$KPM" == "on" ]; then
  KPM_TOOLS_DIR="$MODULES_DIR/kpm_tools"
  mkdir -p "$KPM_TOOLS_DIR"

  if [ "$ROOT" == "apatch" ] || [ "$ROOT" == "folkpatch" ]; then
    if [ "$ROOT" == "folkpatch" ]; then
      FOLKPATCH_VER=$(curl -s https://api.github.com/repos/LyraVoid/KernelPatch/releases/latest | python3 -c "import json,sys; print(json.load(sys.stdin)['tag_name'])" 2>/dev/null || echo "0.13.1")
      KPM_RELEASE_BASE="https://github.com/LyraVoid/KernelPatch/releases/download/${FOLKPATCH_VER}"
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
      KPTOOLS_URL="${KPM_RELEASE_BASE}/kptools-linux"
    else
      KPTOOLS_URL="$KPM_RELEASE_BASE/kptools-linux"
    fi
    curl -LSs -o "$KPTOOLS_BIN" "$KPTOOLS_URL" || { echo "[-] Failed to download kptools"; exit 1; }
    curl -LSs -o "$KPIMG_BIN" "$KPM_RELEASE_BASE/$KPIMG_NAME" || { echo "[-] Failed to download kpimg"; exit 1; }
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
  300)  "$KERNEL_DIR/scripts/config" --file "$OUT_DIR/.config" \
    -d CONFIG_HZ_100 -d CONFIG_HZ_250 -d CONFIG_HZ_500 -d CONFIG_HZ_1000 \
    -e CONFIG_HZ_300 --set-val CONFIG_HZ 300 -d CONFIG_RCU_LAZY ;;
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


# NoMount config
if [ "$NOMOUNT" == "on" ]; then
    "$KERNEL_DIR/scripts/config" --file "$OUT_DIR/.config" -e CONFIG_NOMOUNT
else
    "$KERNEL_DIR/scripts/config" --file "$OUT_DIR/.config" -d CONFIG_NOMOUNT
fi

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
  if [ -z "$V" ] || [ -z "$PL" ] || [ -z "$SL" ] || ! [[ "$V" =~ ^[0-9]+$ ]] || ! [[ "$PL" =~ ^[0-9]+$ ]] || ! [[ "$SL" =~ ^[0-9]+$ ]]; then
    echo "[!] Invalid VERSION_SPOOF format: '$VERSION_SPOOF' (expected x.x.x), skipping spoof."
  else
    sed -i "s/^VERSION = .*/VERSION = $V/" "$KERNEL_DIR/Makefile"
    sed -i "s/^PATCHLEVEL = .*/PATCHLEVEL = $PL/" "$KERNEL_DIR/Makefile"
    sed -i "s/^SUBLEVEL = .*/SUBLEVEL = $SL/" "$KERNEL_DIR/Makefile"
  fi
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
if [ "$DEBUG_MODE" == "on" ]; then
  echo "$CURRENT_CMDLINE" | grep -q "nokaslr" || CMDLINE_APPEND="$CMDLINE_APPEND nokaslr"
fi
CMDLINE_APPEND="${CMDLINE_APPEND# }"
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

make -C "$KERNEL_DIR" \
  "-j${CPUS}" O="$OUT_DIR" \
  CC=clang LD=ld.lld AR=llvm-ar NM=llvm-nm \
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
# Verify image exists
IMAGE_FOUND=0
for img in Image.gz-dtb Image.gz Image; do
  [ -f "$ZIMAGE_DIR/$img" ] && { IMAGE_FOUND=1; break; }
done
[ "$IMAGE_FOUND" == "0" ] && { echo "[-] No kernel image found!"; exit 1; }

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
# Variant label (hanya tulis kalau bukan stock)
VARIANT_LABEL=""
case "$VARIANT" in
  root)  VARIANT_LABEL="-root-${ACTUAL_ROOT}" ;;
  susfs) VARIANT_LABEL="-susfs-${ACTUAL_ROOT}" ;;
esac

# Optional features (hanya tulis kalau aktif)
OPT_LABEL=""
[ "$KPM" == "on" ]          && OPT_LABEL="${OPT_LABEL}-kpm"
[ "$HARDENED" == "on" ]     && OPT_LABEL="${OPT_LABEL}-hardened"
[ "$BYPASSCHARGING" == "on" ] && OPT_LABEL="${OPT_LABEL}-bypasscharging"
[ "$DROIDSPACES" == "on" ]  && OPT_LABEL="${OPT_LABEL}-droidspaces"
[ "$HTSR" == "off" ]        && OPT_LABEL="${OPT_LABEL}-nohtsr"
[ "$WIFI_EXPLOIT" == "off" ] && OPT_LABEL="${OPT_LABEL}-nowifi"
[ "$KGSL_EXPLOIT" == "off" ] && OPT_LABEL="${OPT_LABEL}-nokgsl"
[ "$DATA_EXPLOIT" == "off" ] && OPT_LABEL="${OPT_LABEL}-nodata"
[ "$NOMOUNT" == "on" ] && OPT_LABEL="${OPT_LABEL}-nomount"
[ "$DEBUG_MODE" == "on" ]   && OPT_LABEL="${OPT_LABEL}-debug"

case "$HZ_ID" in
  100)  HZ_LABEL="-powersave" ;;
  300)  HZ_LABEL="-smooth" ;;
  500)  HZ_LABEL="-performance" ;;
  1000) HZ_LABEL="-ultra-performance" ;;
  *)    HZ_LABEL="-balance" ;;
esac

# Clang label: "Neutron Clang 23.0.0" -> "NeutronClang23.0.0"
CLANG_SHORT=$(echo "${KBUILD_COMPILER_STRING:-UnknownClang}" | sed 's/ Clang/Clang/g' | tr ' ' '-')

# Spoof label (hanya tulis kalau ada)
SPOOF_LABEL=""
[ -n "${VERSION_SPOOF}" ] && SPOOF_LABEL="-spoof${VERSION_SPOOF}"

ZIP_NAME="anykern3-DumpC2J${VARIANT_LABEL}-${CLANG_SHORT}${HZ_LABEL}${OPT_LABEL}${SPOOF_LABEL}-${TIME}.zip"
cd "$TEMP_DIR" && zip -r9 "${GITHUB_WORKSPACE}/$ZIP_NAME" . \
  -x '.git*' -x 'README.md' -x '*placeholder' > /dev/null
cd "$GITHUB_WORKSPACE"
rm -rf "$TEMP_DIR"

mkdir -p "$KERNEL_DIR/DumpC2J-Release"
cp "$ZIP_NAME" "$KERNEL_DIR/DumpC2J-Release/"

echo "ZIP_NAME=$ZIP_NAME" >> "$GITHUB_ENV"
[ "$KPM" == "on" ] && echo "KPM_SUPERKEY=$KPM_KEY" >> "$GITHUB_ENV"

BUILD_END=$(date +"%s")
DIFF=$((BUILD_END - BUILD_START))
echo ""
echo "=========================================="
echo "Build done in $((DIFF / 60))m $((DIFF % 60))s"
echo "Output: $ZIP_NAME"
echo "=========================================="
