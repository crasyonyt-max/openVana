# openVana 1.0

**Open source operating system.** A deliberately tiny desktop OS: a black
screen, a taskbar with the openVana start button, Chromium, and the ability to
run **Android apps (APK, in tablet mode)** and **Windows programs (EXE/MSI)**.

Licensed under the GNU GPL v3 (see `LICENSE`). The kernel remains GPL v2.

## What's inside

| Part | What it is |
|---|---|
| **VanaKernel** | Linux LTS with openVana's own config (`kernel/vanakernel.config`): boot drivers built in, Android binder enabled, debugging stripped. |
| **vana-shell** | openVana's desktop (`shell/vana-shell.c`, ~400 lines of C, ~30 KB binary): black background, taskbar, clock, start menu with search, *Install APK…*, *Run EXE…*, restart and shut down. |
| **Chromium** | The browser. Runs natively on Wayland. |
| **APK support** | Waydroid (Android in a container). Configured as a **tablet** (`ro.build.characteristics=tablet`, 160 dpi, so the smallest width is at least 600dp), so apps use their tablet layouts. Each app opens in its own window. |
| **EXE support** | Wine. Open an `.exe` from the start menu, from Chromium's downloads, or run it directly (binfmt). |
| **Base** | Alpine Linux (musl, OpenRC, busybox), labwc window manager, PipeWire audio, iwd Wi-Fi. |

The full package list is `rootfs/packages.txt`. Nothing else is installed:
no terminal, no file manager, no office suite.

## Build

Needs Docker or Podman and about 15 GB of free disk space. Builds run inside an Alpine container.

```sh
cp ~/Downloads/your-app.apk apks/     # APKs to ship with the OS (optional)
make                                  # -> out/openvana-1.0-x86_64.iso
make run                              # try it in QEMU
```

Optional build settings: `KVER=6.12.x` (kernel version), `ALPINE=v3.22`,
`KEYMAP=de` (keyboard layout), `USERNAME=vana`.

To skip the Android download (about 800 MB) on first boot, put Waydroid's
`system.img` and `vendor.img` in `android-images/` before you build.

## Use

* Write the ISO to a USB stick (for example with `dd` or balenaEtcher) and boot it. It boots straight into the desktop.
* **Super key** or the logo button opens the start menu.
* **Install APK…** installs an Android app, which then appears in the start menu.
* **Run EXE…** runs a Windows program. Programs it installs appear in the start menu.
* To install to disk (UEFI): press Ctrl+Alt+F2, log in as `vana`, then run `doas vana-install /dev/nvme0n1`.

## Layout

```
kernel/    VanaKernel config + build script (+ patches/)
shell/     vana-shell: background, taskbar, start menu
rootfs/    package list, system config overlay, build script
iso/       initramfs init, GRUB menu, ISO build script
apks/      APKs bundled into the image
branding/  openVana logo (start button)
```

## Requirements

Requires an x86_64 PC with a GPU that Mesa supports (Intel, AMD or virtio).
NVIDIA works only with the open-source nouveau driver, and Android apps run poorly on it.
