#!/bin/sh
# Pack rootfs + VanaKernel into a hybrid (BIOS + UEFI, USB + DVD) ISO.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:-$HERE/../out}
ISO=$OUT/isodir
NAME=${NAME:-openvana-1.0-x86_64.iso}

rm -rf "$ISO" "$OUT/initramfs"; mkdir -p "$ISO/boot/grub" "$ISO/openvana" "$OUT/initramfs/bin"

# initramfs: static busybox + init script, nothing else (drivers are built into VanaKernel)
cp /bin/busybox.static "$OUT/initramfs/bin/busybox"
cp "$HERE/init" "$OUT/initramfs/init"; chmod +x "$OUT/initramfs/init"
(cd "$OUT/initramfs" && find . | cpio -o -H newc --quiet | zstd -19 -q) > "$ISO/boot/initramfs.img"

cp "$OUT/kernel/bzImage" "$ISO/boot/vmlinuz"
cp "$HERE/grub.cfg" "$ISO/boot/grub/grub.cfg"
mksquashfs "$OUT/rootfs" "$ISO/openvana/rootfs.sqfs" -comp zstd -Xcompression-level 19 \
    -b 1M -noappend -no-progress -wildcards -e 'proc/*' 'sys/*' 'dev/*' 'tmp/*'

grub-mkrescue -o "$OUT/$NAME" "$ISO" -volid OPENVANA
echo "ISO: $OUT/$NAME ($(du -h "$OUT/$NAME" | cut -f1))"
