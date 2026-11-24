#!/bin/bash
# Pack the rootfs into a hybrid ISO (BIOS + UEFI, USB stick + DVD) booted by live-boot.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:-$HERE/../out}
ROOT=$OUT/rootfs
ISO=$OUT/isodir
NAME=${NAME:-openvana-server-1.0-amd64.iso}

newest() { ls "$ROOT"/boot/$1 2>/dev/null | sort -V | tail -1 || true; }   # empty when none
hydra=$(newest 'vmlinuz-*-vanakernel-hydra')
debian=$(newest 'vmlinuz-*-amd64')
[ -n "$debian" ] || { echo "Debian fallback kernel missing"; exit 1; }
if [ -z "$hydra" ]; then
    [ "${ALLOW_NO_HYDRA:-0}" = 1 ] || { echo "VanaKernel Hydra missing"; exit 1; }
    hydra=$debian
fi

rm -rf "$ISO"; mkdir -p "$ISO/live" "$ISO/boot/grub"
cp "$hydra" "$ISO/live/vmlinuz"
cp "$ROOT/boot/initrd.img-${hydra#*/vmlinuz-}" "$ISO/live/initrd.img"
cp "$debian" "$ISO/live/vmlinuz-debian"
cp "$ROOT/boot/initrd.img-${debian#*/vmlinuz-}" "$ISO/live/initrd-debian.img"
cp "$HERE/grub.cfg" "$ISO/boot/grub/grub.cfg"
[ -d "$OUT/pool" ] && cp -r "$OUT/pool" "$ISO/"          # GNOME packages for the installer

mksquashfs "$ROOT" "$ISO/live/filesystem.squashfs" -comp zstd -Xcompression-level 19 -b 1M \
    -noappend -no-progress -wildcards -e 'proc/*' 'sys/*' 'dev/*' 'run/*' 'tmp/*'

grub-mkrescue -o "$OUT/$NAME" "$ISO" -volid OPENVANA_SRV
echo "ISO: $OUT/$NAME ($(du -h "$OUT/$NAME" | cut -f1))"
