#!/usr/bin/env bash
#
# Build the patched NVIDIA 620.73.04 open kernel modules through DKMS and
# install them for the running kernel (override with KVER=<uname -r>).
#
# Usage:
#   sudo ./dkms/install.sh          # build + install + rebuild initramfs
#
# The source tree staged in /usr/src is a snapshot of this repository; keep
# the repository around and re-run this script after rebasing the patches on
# a new driver release.
#
set -euo pipefail

PKG="nvidia-va"
VER="620.73.04"
SRC="/usr/src/${PKG}-${VER}"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KVER="${KVER:-$(uname -r)}"

if [ "$(id -u)" -ne 0 ]; then
    exec sudo -- "$0" "$@"
fi

if [ ! -d "/lib/modules/${KVER}/build" ]; then
    echo "error: kernel build tree for ${KVER} is missing (install the headers)" >&2
    exit 1
fi

if [ ! -f "$REPO_DIR/dkms/dkms.conf" ]; then
    echo "error: ${REPO_DIR} does not look like the NVIDIA source tree" >&2
    exit 1
fi

echo "== staging ${REPO_DIR} in ${SRC}"
rm -rf "$SRC"
mkdir -p "$SRC"
cp -a --reflink=auto "$REPO_DIR"/. "$SRC"/
rm -rf "$SRC/.git"
install -m 0644 "$REPO_DIR/dkms/dkms.conf" "$SRC/dkms.conf"

echo "== removing previous ${PKG}/${VER} registrations"
dkms remove -m "$PKG" -v "$VER" --all >/dev/null 2>&1 || true

echo "== dkms add"
dkms add -m "$PKG" -v "$VER"

echo "== dkms build for ${KVER} (this takes a while)"
dkms build -m "$PKG" -v "$VER" -k "$KVER" --force

echo "== dkms install"
dkms install -m "$PKG" -v "$VER" -k "$KVER" --force

echo "== update module dependencies"
depmod -a "$KVER"

echo "== rebuild initramfs"
if command -v limine-mkinitcpio >/dev/null 2>&1; then
    limine-mkinitcpio
elif compgen -G "/etc/mkinitcpio.d/*.preset" >/dev/null; then
    mkinitcpio -P
else
    echo "warning: no mkinitcpio presets found; rebuild the initramfs manually" >&2
fi

echo
echo "installed module: $(modinfo -n nvidia)"
echo "marker count:     $(strings "$(modinfo -n nvidia)" | grep -c 'keeping VA block')"
echo
echo "reboot, then:"
echo "  journalctl -k -b | grep -E 'NVRM|nvidia-drm'"
echo "  modinfo nvidia | grep -E 'version|filename'"
