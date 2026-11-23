#!/bin/bash
# Build VanaKernel Hydra as Debian packages (.deb):
# upstream Linux 6.12 LTS + Debian's amd64 config + hydra.config.
# Output: out/kernel/linux-image-*-vanakernel-hydra_*.deb (+ headers)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:-$HERE/../out}
# newest 6.12 LTS release listed on kernel.org (override with KVER=6.12.x)
KVER=${KVER:-$(curl -fsSL https://www.kernel.org/releases.json \
    | grep -o '"version": *"6\.12\.[0-9]*"' | grep -o '6\.12\.[0-9]*' | sort -V | tail -1)}
[ -n "$KVER" ] || { echo "could not determine kernel version"; exit 1; }
SRC=$OUT/linux-$KVER
mkdir -p "$OUT/kernel"

if [ ! -d "$SRC" ]; then
    curl -fL "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-$KVER.tar.xz" | tar -xJ -C "$OUT"
fi

# Debian's configuration, taken from Debian's current amd64 kernel package
work=$(mktemp -d)
pkg=$(apt-cache depends linux-image-amd64 | awk '/Depends: linux-image-[0-9]/ {print $2; exit}')
(cd "$work" && apt-get download "$pkg" && dpkg-deb --fsys-tarfile ./*.deb | tar -x --wildcards './boot/config-*')
cp "$work"/boot/config-* "$SRC/.config"
echo "Debian config: $(basename "$work"/boot/config-*)"
rm -rf "$work"

cd "$SRC"
scripts/kconfig/merge_config.sh -m .config "$HERE/hydra.config"
make olddefconfig
# make sure the important choices survived olddefconfig
for opt in 'CONFIG_LOCALVERSION="-vanakernel-hydra"' '# CONFIG_SMB_SERVER is not set' 'CONFIG_DRM_SIMPLEDRM=y'; do
    grep -qx "$opt" .config || { echo "config check failed: $opt"; exit 1; }
done

rm -f ../linux-*.deb
make -j"$(nproc)" bindeb-pkg \
    KDEB_PKGVERSION="$KVER-1" DPKG_FLAGS=-d KBUILD_BUILD_USER=vana KBUILD_BUILD_HOST=openvana
rm -f "$OUT"/kernel/*.deb
cp ../linux-image-*-vanakernel-hydra_*.deb ../linux-headers-*-vanakernel-hydra_*.deb "$OUT/kernel/"
make -s kernelrelease > "$OUT/kernel/release"
echo "VanaKernel Hydra $(cat "$OUT/kernel/release") built:"; ls -la "$OUT/kernel"
