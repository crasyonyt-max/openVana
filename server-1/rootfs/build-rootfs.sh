#!/bin/bash
# Assemble the openVana Server root filesystem: Debian 13 (trixie) via mmdebstrap,
# VanaKernel Hydra .deb, openVana configuration overlay, live-session user.
# Run as root (inside the Containerfile build environment, --privileged).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:-$HERE/../out}
ROOT=$OUT/rootfs
SUITE=trixie
MIRROR=${MIRROR:-http://deb.debian.org/debian}
SECURITY=${SECURITY:-http://security.debian.org/debian-security}
COMPONENTS="main contrib non-free-firmware"

in_root() { chroot "$ROOT" env DEBIAN_FRONTEND=noninteractive LC_ALL=C.UTF-8 "$@"; }
unmount_all() {
    for d in sys proc dev/pts dev; do
        mountpoint -q "$ROOT/$d" && umount -l "$ROOT/$d"
    done
    return 0
}
trap unmount_all EXIT

rm -rf "$ROOT"
PKGS=$(grep -v '^\s*#' "$HERE/packages.txt" | grep . | paste -sd, -)

echo "==> Debian $SUITE base system"
extra=()                                   # KEYRING=file: Debian keys when not building on Debian
[ -n "${KEYRING:-}" ] && extra+=(--keyring="$KEYRING")
mmdebstrap "${extra[@]}" --mode=root --variant=important --architectures=amd64,i386 \
    --components="$COMPONENTS" --include="$PKGS" \
    --dpkgopt='path-exclude=/usr/share/doc/*' --dpkgopt='path-include=/usr/share/doc/*/copyright' \
    "$SUITE" "$ROOT" \
    "deb $MIRROR $SUITE $COMPONENTS" \
    "deb $MIRROR $SUITE-updates $COMPONENTS" \
    "deb $SECURITY $SUITE-security $COMPONENTS"

for d in dev dev/pts proc sys; do mount --bind "/$d" "$ROOT/$d"; done
printf '#!/bin/sh\nexit 101\n' > "$ROOT/usr/sbin/policy-rc.d"   # no services start during the build
chmod +x "$ROOT/usr/sbin/policy-rc.d"
rm -f "$ROOT/etc/resolv.conf"; cp /etc/resolv.conf "$ROOT/etc/resolv.conf"   # network for the build steps

echo "==> VanaKernel Hydra"
if ls "$OUT"/kernel/linux-image-*-vanakernel-hydra_*.deb >/dev/null 2>&1; then
    cp "$OUT"/kernel/linux-image-*-vanakernel-hydra_*.deb "$ROOT/tmp/"
    in_root sh -c 'dpkg -i /tmp/linux-image-*.deb && rm -f /tmp/linux-image-*.deb'
elif [ "${ALLOW_NO_HYDRA:-0}" = 1 ]; then
    echo "WARNING: no VanaKernel Hydra package found, test build with the Debian kernel only"
else
    echo "VanaKernel Hydra package missing: run kernel/build-kernel.sh first"; exit 1
fi

echo "==> openVana configuration"
cp -rT --preserve=mode,timestamps "$HERE/overlay" "$ROOT"     # files become root-owned
chmod 0440 "$ROOT"/etc/sudoers.d/* 2>/dev/null || true
chmod -x "$ROOT/etc/update-motd.d/10-uname"                    # replaced by 05-openvana

# openVana logos (login screen) and a plain black boot menu instead of Debian's artwork.
# Registered as higher-priority alternatives (Debian's are 50), so they survive updates of
# Debian's desktop-base package, which GNOME brings in.
mkdir -p "$ROOT/usr/share/images/desktop-base"
in_root update-alternatives --install /usr/share/images/vendor-logos vendor-logos \
    /usr/share/openvana/vendor-logos 100
in_root update-alternatives --install /usr/share/images/desktop-base/desktop-grub.png desktop-grub \
    /usr/share/openvana/grub-background.png 100

# branding that survives Debian updates (diverted, so base-files never overwrites it)
for f in /usr/lib/os-release /etc/issue /etc/issue.net; do
    in_root dpkg-divert --quiet --local --no-rename --add "$f"
done
cat > "$ROOT/usr/lib/os-release" <<EOF
PRETTY_NAME="openVana Server 1.0"
NAME="openVana Server"
VERSION_ID="1.0"
VERSION="1.0"
VERSION_CODENAME=$SUITE
ID=openvana-server
ID_LIKE=debian
HOME_URL="https://github.com/crasyonyt-max/openVana"
SUPPORT_URL="https://github.com/crasyonyt-max/openVana"
BUG_REPORT_URL="https://github.com/crasyonyt-max/openVana/issues"
EOF
printf 'openVana Server 1.0 \\n \\l\n\n' > "$ROOT/etc/issue"
printf 'openVana Server 1.0\n' > "$ROOT/etc/issue.net"

echo openvana-server > "$ROOT/etc/hostname"
cat > "$ROOT/etc/hosts" <<'EOF'
127.0.0.1	localhost
127.0.1.1	openvana-server
::1		localhost ip6-localhost ip6-loopback
ff02::1		ip6-allnodes
ff02::2		ip6-allrouters
EOF
echo 'LANG=C.UTF-8' > "$ROOT/etc/default/locale"

echo "==> boot screen"
in_root plymouth-set-default-theme openvana-server

echo "==> live user (renamed and given a password by the installer)"
in_root useradd -m -s /bin/bash -c "openVana" -G sudo,adm,systemd-journal vana
in_root passwd -d vana >/dev/null
in_root passwd -l root >/dev/null
mkdir -p "$ROOT/etc/systemd/system/getty@tty1.service.d"
cat > "$ROOT/etc/systemd/system/getty@tty1.service.d/autologin.conf" <<'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -f -- \\u' --noclear --autologin vana %I $TERM
EOF
echo 'vana ALL=(ALL) NOPASSWD: ALL' > "$ROOT/etc/sudoers.d/openvana-live"
chmod 0440 "$ROOT/etc/sudoers.d/openvana-live"

# systemd's VM-socket SSH helper is not needed (openssh-server is) and logs an error at every boot
mkdir -p "$ROOT/etc/systemd/system-generators"
ln -sf /dev/null "$ROOT/etc/systemd/system-generators/systemd-ssh-generator"

# a server never goes to sleep by itself (also blocks GNOME's automatic suspend)
in_root systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target \
    suspend-then-hibernate.target

echo "==> services"
in_root systemctl enable systemd-networkd systemd-resolved ssh ufw fail2ban chrony \
    fstrim.timer openvana-startup-sound.service openvana-chrome-firstboot.timer
in_root ufw allow OpenSSH >/dev/null
sed -i 's/^ENABLED=.*/ENABLED=yes/' "$ROOT/etc/ufw/ufw.conf"     # firewall on: only SSH is open

echo "==> boot loader packages for the installer (offline)"
in_root apt-get update -q
for pair in grub-pc:grub-pc grub-efi-amd64:grub-efi; do       # package:folder
    in_root apt-get install --download-only -y -q "${pair%%:*}"
    mkdir -p "$ROOT/usr/share/openvana/debs/${pair##*:}"
    mv "$ROOT"/var/cache/apt/archives/*.deb "$ROOT/usr/share/openvana/debs/${pair##*:}/"
done

echo "==> GNOME desktop packages for the installer (offline, stored on the ISO, not in the live system)"
rm -rf "$OUT/pool"; mkdir -p "$OUT/pool/gnome"
in_root apt-get install --download-only -y -q gnome-core network-manager
mv "$ROOT"/var/cache/apt/archives/*.deb "$OUT/pool/gnome/"
echo "GNOME: $(ls "$OUT/pool/gnome" | wc -l) packages, $(du -sh "$OUT/pool/gnome" | cut -f1)"

echo "==> initramfs (boot screen + live boot)"
in_root update-initramfs -u -k all

echo "==> cleanup"
rm -f "$ROOT/usr/sbin/policy-rc.d"
ln -sf ../run/systemd/resolve/stub-resolv.conf "$ROOT/etc/resolv.conf"
: > "$ROOT/etc/machine-id"                      # every installation gets its own id
rm -f "$ROOT"/etc/ssh/ssh_host_*                # and its own SSH host keys (made at first start)
in_root apt-get clean
rm -rf "$ROOT"/var/lib/apt/lists/* "$ROOT"/var/log/*.log "$ROOT"/var/log/apt/* "$ROOT"/tmp/* "$ROOT"/root/.bash_history
unmount_all
echo "rootfs ready: $(du -sh "$ROOT" | cut -f1)"
