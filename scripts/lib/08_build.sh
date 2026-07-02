#!/bin/bash
set -e

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
  KCFLAGS="$KERNEL_KCFLAGS" LDFLAGS_vmlinux="$KERNEL_LDFLAGS" \
  || { echo "[-] Build failed!"; exit 1; }
