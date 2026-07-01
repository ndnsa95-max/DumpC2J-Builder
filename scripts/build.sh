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
echo "ACTUAL_ROOT=$ACTUAL_ROOT" >> "$GITHUB_ENV"

LTO="${INPUT_LTO:-full}"

LTO_VAL="$LTO"
echo "LTO_ACTUAL=$LTO_VAL" >> "$GITHUB_ENV"

# ==========================================
# Guard: ReSukiSU wajib pakai variant SUSFS
# ==========================================
if [ "$ROOT" == "resukisu" ] && [ "$VARIANT" != "susfs" ]; then
  echo "[!] ERROR: ReSukiSU hanya didukung dengan Variant = susfs."
  echo "[!] Root-only (no susfs) untuk resukisu sengaja diblokir karena diketahui bikin freeze/reboot."
  echo "[!] Re-run workflow dengan Variant diset ke 'susfs'."
  exit 1
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
  sukisu)   ROOT_REPO="https://github.com/sukisu-ultra/sukisu-ultra.git"; REPO_NAME="sukisu-ultra"; BRANCH="main" ;;
  resukisu) ROOT_REPO="https://github.com/ReSukiSU/ReSukiSU.git"; REPO_NAME="ReSukiSU"; BRANCH="main" ;;
  ksu-next) ROOT_REPO="https://github.com/KernelSU-Next/KernelSU-Next.git"; REPO_NAME="KernelSU-Next"; BRANCH="dev" ;;
  kowsu)    ROOT_REPO="https://github.com/KOWX712/KernelSU.git"; REPO_NAME="KOWX712-KernelSU"; BRANCH="main" ;;
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

    if grep -q "KSU_SUSFS" "$MODULES_DIR/$REPO_NAME/kernel/Kconfig" 2>/dev/null || [ "$ROOT" == "sukisu" ] || [ "$ROOT" == "resukisu" ]; then
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
    anchor = '\t\tbinder_inner_proc_unlock(target_thread->proc);\n\t\ttrace_android_vh_binder_reply(target_proc, proc, thread, tr);\n\t} else {'
    if anchor in bc:
        bc = bc.replace(anchor, '\t\tbinder_inner_proc_unlock(target_thread->proc);' + reply_hook + '\n\t\ttrace_android_vh_binder_reply(target_proc, proc, thread, tr);\n\t} else {')
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
# ReSukiSU: fix ksu_init_rc_hook_key_false typo in ksud_integration.c
if [ "$ROOT" == "resukisu" ]; then
  KSUD_INT="$MODULES_DIR/$REPO_NAME/kernel/runtime/ksud_integration.c"
  if [ -f "$KSUD_INT" ]; then
    sed -i 's/ksu_init_rc_hook_key_false/ksu_is_init_rc_hook_enabled/g' "$KSUD_INT"
    echo "[*] ReSukiSU: fixed ksu_init_rc_hook_key_false typo"
  fi
fi

# ReSukiSU susfs: define proc_unprivillege symbols as non-inline
# (static inline breaks under LTO with external callers)
# ==========================================
if [ "$ROOT" == "resukisu" ]; then
  SUCOMPAT_IMPL="$MODULES_DIR/$REPO_NAME/kernel/feature/sucompat_proc_flag.c"
  if [ ! -f "$SUCOMPAT_IMPL" ]; then
    echo "[*] Generating sucompat_proc_flag.c for ReSukiSU susfs LTO fix..."
    cat > "$SUCOMPAT_IMPL" << 'SCEOF'
#include <linux/types.h>
#include <linux/thread_info.h>
#ifdef CONFIG_64BIT
#define TIF_PROC_NON_PRIVILEGE 62
#else
#define TIF_PROC_NON_PRIVILEGE 30
#endif
bool ksu_is_current_proc_unprivillege(void) {
    return test_thread_flag(TIF_PROC_NON_PRIVILEGE);
}
void ksu_set_current_proc_unprivillege(void) {
    set_thread_flag(TIF_PROC_NON_PRIVILEGE);
}
void ksu_clear_current_proc_unprivillege(void) {
    clear_thread_flag(TIF_PROC_NON_PRIVILEGE);
}
SCEOF
    echo "kernelsu-objs += feature/sucompat_proc_flag.o" >> "$MODULES_DIR/$REPO_NAME/kernel/Kbuild"
    echo "[+] sucompat_proc_flag.c generated and added to Kbuild"
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
if [ -z "$KBUILD_COMPILER_STRING" ]; then
  echo "[-] KBUILD_COMPILER_STRING is empty — clang setup may have failed!"
  exit 1
fi
echo "[+] Using Clang: $KBUILD_COMPILER_STRING"

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

# KPM: enable for sukisu only
if [ "$ROOT" == "sukisu" ]; then
  "$KERNEL_DIR/scripts/config" --file "$OUT_DIR/.config" -e CONFIG_KPM
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
  --set-str CONFIG_CMDLINE "${CURRENT_CMDLINE:+$CURRENT_CMDLINE }$CMDLINE_APPEND"

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

# Build zip name (simple — semua detail lengkap ada di release notes)
TIME=$(date "+%Y%m%d-%H%M")
KVER=$(grep '^VERSION = ' "$KERNEL_DIR/Makefile" | awk '{print $3}')
KPL=$(grep '^PATCHLEVEL = ' "$KERNEL_DIR/Makefile" | awk '{print $3}')
KSL=$(grep '^SUBLEVEL = ' "$KERNEL_DIR/Makefile" | awk '{print $3}')
KERNEL_VER="${KVER}.${KPL}.${KSL}"
echo "KERNEL_VER=$KERNEL_VER" >> "$GITHUB_ENV"

ZIP_NAME="anykern3-DumpC2J-${KERNEL_VER}-${TIME}.zip"
cd "$TEMP_DIR" && zip -r9 "${GITHUB_WORKSPACE}/$ZIP_NAME" . \
  -x '.git*' -x 'README.md' -x '*placeholder' > /dev/null
cd "$GITHUB_WORKSPACE"
rm -rf "$TEMP_DIR"

mkdir -p "$KERNEL_DIR/DumpC2J-Release"
cp "$ZIP_NAME" "$KERNEL_DIR/DumpC2J-Release/"

echo "ZIP_NAME=$ZIP_NAME" >> "$GITHUB_ENV"
echo "INPUT_VARIANT=$VARIANT" >> "$GITHUB_ENV"
echo "INPUT_ROOT=$ROOT" >> "$GITHUB_ENV"
echo "INPUT_BYPASS=$BYPASSCHARGING" >> "$GITHUB_ENV"
echo "INPUT_NOMOUNT=$NOMOUNT" >> "$GITHUB_ENV"
echo "INPUT_DROIDSPACES=$DROIDSPACES" >> "$GITHUB_ENV"
echo "INPUT_DEBUG=$DEBUG_MODE" >> "$GITHUB_ENV"

BUILD_END=$(date +"%s")
DIFF=$((BUILD_END - BUILD_START))
echo ""
echo "=========================================="
echo "Build done in $((DIFF / 60))m $((DIFF % 60))s"
echo "Output: $ZIP_NAME"
echo "=========================================="
