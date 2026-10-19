#!/bin/sh
# Build VanaKernel: upstream Linux LTS + the openVana configuration fragment.
# Output: out/kernel/bzImage and out/kernel/modules/lib/modules/<ver>/
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:-$HERE/../out}
KVER=${KVER:-6.12.50}
SRC=$OUT/linux-$KVER

mkdir -p "$OUT/kernel"
if [ ! -d "$SRC" ]; then
    curl -fL "https://cdn.kernel.org/pub/linux/kernel/v${KVER%%.*}.x/linux-$KVER.tar.xz" \
        | tar -xJ -C "$OUT"
fi

cd "$SRC"
# Apply VanaKernel branding patches, if any (idempotent via a stamp file).
for p in "$HERE"/patches/*.patch; do
    [ -e "$p" ] || continue
    stamp=".vana-$(basename "$p").applied"
    [ -e "$stamp" ] || { patch -p1 < "$p"; touch "$stamp"; }
done

make x86_64_defconfig
scripts/kconfig/merge_config.sh -m .config "$HERE/vanakernel.config"
make olddefconfig
make -j"$(nproc)" bzImage modules

cp arch/x86/boot/bzImage "$OUT/kernel/bzImage"
rm -rf "$OUT/kernel/modules"
make INSTALL_MOD_PATH="$OUT/kernel/modules" INSTALL_MOD_STRIP=1 modules_install
make -s kernelrelease > "$OUT/kernel/release"
echo "VanaKernel $(cat "$OUT/kernel/release") built."
