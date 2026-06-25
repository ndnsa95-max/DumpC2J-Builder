#!/usr/bin/env bash
# setup_nomount.sh — Apply NoMount / ZeroMount patch to kernel source
# Usage: bash setup_nomount.sh <kernel_dir> <method: nomount|zeromount>
set -e

KERNEL_DIR="${1:-${GITHUB_WORKSPACE}/kernel-source}"
METHOD="${2:-nomount}"
NAMESPACE_C="$KERNEL_DIR/fs/namespace.c"
KCONFIG="$KERNEL_DIR/fs/Kconfig"

if [ ! -f "$NAMESPACE_C" ]; then
  echo "[!] fs/namespace.c not found"
  exit 1
fi

echo "[*] Applying $METHOD patch..."

# Skip if already patched
if grep -q "KSU_NOMOUNT\|KSU_ZEROMOUNT" "$NAMESPACE_C" 2>/dev/null; then
  echo "[+] Already patched, skipping"
  exit 0
fi

python3 - "$NAMESPACE_C" "$METHOD" << 'PYEOF'
import sys

path   = sys.argv[1]
method = sys.argv[2]
content = open(path).read()

# Config flag
config = "CONFIG_KSU_NOMOUNT" if method == "nomount" else "CONFIG_KSU_ZEROMOUNT"

# Helper function — injected before path_mount
if method == "nomount":
    helper = r"""
#ifdef CONFIG_KSU_NOMOUNT
static bool ksu_nomount_skip(struct path *path, unsigned long flags)
{
	static const char * const blocked[] = {
		"/system", "/vendor", "/product",
		"/system_ext", "/odm", "/apex", NULL
	};
	const char * const *p;
	char buf[256];
	char *str;

	/* Only intercept bind mounts */
	if (!(flags & MS_BIND))
		return false;

	str = d_path(path, buf, sizeof(buf));
	if (IS_ERR_OR_NULL(str))
		return false;

	for (p = blocked; *p; p++) {
		if (strncmp(str, *p, strlen(*p)) == 0)
			return true;
	}
	return false;
}
#endif /* CONFIG_KSU_NOMOUNT */

"""
    hook = r"""
#ifdef CONFIG_KSU_NOMOUNT
	if (ksu_nomount_skip(path, flags))
		return 0;
#endif
"""
else:  # zeromount
    helper = r"""
#ifdef CONFIG_KSU_ZEROMOUNT
static bool ksu_zeromount_skip(struct path *path, unsigned long flags)
{
	static const char * const blocked[] = {
		"/system", "/vendor", "/product",
		"/system_ext", "/odm", "/apex", NULL
	};
	const char * const *p;
	char buf[256];
	char *str;

	if (!(flags & MS_BIND))
		return false;

	str = d_path(path, buf, sizeof(buf));
	if (IS_ERR_OR_NULL(str))
		return false;

	for (p = blocked; *p; p++) {
		if (strncmp(str, *p, strlen(*p)) == 0)
			return true;
	}
	return false;
}
#endif /* CONFIG_KSU_ZEROMOUNT */

"""
    hook = r"""
#ifdef CONFIG_KSU_ZEROMOUNT
	if (ksu_zeromount_skip(path, flags))
		return 0;
#endif
"""

# 1. Inject helper before path_mount
anchor = 'int path_mount(const char *dev_name, struct path *path,'
if anchor in content and helper not in content:
    content = content.replace(anchor, helper + anchor)
    print(f"[+] Helper function injected")
else:
    print("[!] anchor not found or already patched")
    sys.exit(1)

# 2. Inject hook after may_mount() check
hook_anchor = '\tif (!may_mount())\n\t\treturn -EPERM;'
if hook_anchor in content and hook not in content:
    content = content.replace(hook_anchor, hook_anchor + hook)
    print(f"[+] Hook injected after may_mount()")
else:
    print("[!] hook anchor not found")
    sys.exit(1)

open(path, 'w').write(content)
print(f"[+] {method} patch done")
PYEOF

echo "[+] $METHOD applied to namespace.c"
