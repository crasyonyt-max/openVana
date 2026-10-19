# Build environment for openVana (Alpine, so packages match the target).
FROM alpine:3.22
RUN apk add --no-cache \
    build-base bc bison flex perl elfutils-dev openssl-dev linux-headers \
    ncurses-dev diffutils findutils xz zstd cpio curl patch kmod \
    squashfs-tools xorriso mtools grub grub-bios grub-efi busybox-static \
    gtk+3.0-dev gtk-layer-shell-dev pkgconf
WORKDIR /src
