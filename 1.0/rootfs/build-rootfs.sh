#!/bin/sh
# Assemble the openVana root filesystem from Alpine packages + VanaKernel
# modules + the openVana shell + the overlay. Run as root on Alpine (see Containerfile).
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
TOP=$HERE/..
OUT=${OUT:-$TOP/out}
ROOT=$OUT/rootfs
ALPINE=${ALPINE:-v3.22}
MIRROR=${MIRROR:-https://dl-cdn.alpinelinux.org/alpine}
KEYMAP=${KEYMAP:-us}
USERNAME=${USERNAME:-vana}

rm -rf "$ROOT"; mkdir -p "$ROOT/etc/apk"
cp -r /etc/apk/keys "$ROOT/etc/apk/"
printf '%s/%s/main\n%s/%s/community\n' "$MIRROR" "$ALPINE" "$MIRROR" "$ALPINE" > "$ROOT/etc/apk/repositories"

PKGS=$(grep -v '^\s*#' "$HERE/packages.txt" | tr '\n' ' ')
# shellcheck disable=SC2086
apk add --root "$ROOT" --initdb --no-cache --update-cache $PKGS

# --- VanaKernel modules ---
KREL=$(cat "$OUT/kernel/release")
mkdir -p "$ROOT/lib/modules"
cp -a "$OUT/kernel/modules/lib/modules/$KREL" "$ROOT/lib/modules/$KREL"
rm -f "$ROOT/lib/modules/$KREL/build" "$ROOT/lib/modules/$KREL/source"
depmod -b "$ROOT" "$KREL"

# --- openVana shell + branding + overlay ---
make -C "$TOP/shell" install DESTDIR="$ROOT"
cp -a "$HERE/overlay/." "$ROOT/"
# cp -a keeps the build user's ownership; system files must belong to root
(cd "$HERE/overlay" && find . -mindepth 1) | while read -r f; do chown -h root:root "$ROOT/$f"; done
chown root:root "$ROOT"
sed -i "s/@KEYMAP@/$KEYMAP/" "$ROOT/etc/xdg/labwc/environment"

# --- bundled APKs (put yours into ./apks/) ---
mkdir -p "$ROOT/usr/share/openvana/apks"
cp "$TOP"/apks/*.apk "$ROOT/usr/share/openvana/apks/" 2>/dev/null || true

# --- optional: bake the Android system image in, so no download on first boot ---
if [ -d "$TOP/android-images" ]; then
    mkdir -p "$ROOT/usr/share/waydroid-extra/images"
    cp "$TOP"/android-images/system.img "$TOP"/android-images/vendor.img \
        "$ROOT/usr/share/waydroid-extra/images/"
fi

# --- system identity ---
echo openvana > "$ROOT/etc/hostname"
cat > "$ROOT/etc/os-release" <<OSR
NAME="openVana"
PRETTY_NAME="openVana 1.0"
ID=openvana
ID_LIKE=alpine
VERSION_ID=1.0
HOME_URL="https://github.com/crasyonyt-max/openVana"
OSR
printf 'auto lo\niface lo inet loopback\n' > "$ROOT/etc/network/interfaces"

# --- user with autologin on tty1 ---
chroot "$ROOT" adduser -D -s /bin/sh -g "openVana user" "$USERNAME"
for g in wheel video input audio seat netdev; do
    chroot "$ROOT" addgroup "$USERNAME" "$g" 2>/dev/null || true
done
chroot "$ROOT" passwd -d "$USERNAME" >/dev/null
# no root logins; admin tasks go through doas (see /etc/doas.d/openvana.conf)
chroot "$ROOT" passwd -l root >/dev/null
printf 'openVana 1.0 - Kernel \\r on \\m (\\l)\n\n' > "$ROOT/etc/issue"
sed -i "s|^tty1::.*|tty1::respawn:/sbin/agetty --autologin $USERNAME --noclear tty1 linux|" "$ROOT/etc/inittab"
sed -i 's|^tty[3-6]::|#&|' "$ROOT/etc/inittab"

# --- services (minimal set) ---
svc() {
    lvl=$1; shift
    for s; do
        if [ -e "$ROOT/etc/init.d/$s" ]; then chroot "$ROOT" rc-update add "$s" "$lvl" >/dev/null
        else echo "WARNING: service $s not found, skipped"; fi
    done
}
svc sysinit devfs dmesg udev udev-trigger udev-settle
svc boot    modules sysctl hostname bootmisc hwclock binfmt networking
svc default dbus seatd iwd dhcpcd waydroid-container local
svc shutdown killprocs savecache mount-ro

# --- trim: docs, man pages, static libs, package cache ---
rm -rf "$ROOT"/usr/share/man "$ROOT"/usr/share/doc "$ROOT"/usr/share/info \
       "$ROOT"/usr/share/gtk-doc "$ROOT"/var/cache/apk/* "$ROOT"/usr/lib/*.a
echo "rootfs ready: $(du -sh "$ROOT" | cut -f1)"
