# openVana Server 1.0

A stable server operating system based on **Debian 13 "trixie"** with its own
kernel, **VanaKernel Hydra**. It runs Debian software (`.deb`) natively and
Windows programs (`.exe` / `.msi`) through Wine, with or without a screen.

**Download:** [openVana Server 1.0 release](https://github.com/crasyonyt-max/openVana/releases/tag/server-1)
(`openvana-server-1.0-amd64.iso`)

## What's inside

| Part | Details |
|---|---|
| **Base** | Debian 13 "trixie" (stable), with Debian's security updates |
| **VanaKernel Hydra** | Linux 6.12 LTS, built from Debian's own kernel configuration plus the VanaKernel changes, packaged as `.deb` |
| **Fallback kernel** | Debian's stock kernel stays installed as a second boot entry |
| **Boot** | Classic openVana Server splash screen with a scrolling bar, plus the startup sound (if the machine has a sound card) |
| **.deb** | Native: `sudo apt install ./program.deb` |
| **.exe / .msi** | Wine (64- and 32-bit): `vana-exe program.exe`, or run the `.exe` directly |
| **Google Chrome** | Google's official `.deb`, installed automatically on the first start with internet, kept up to date automatically |
| **Remote access** | OpenSSH |

### VanaKernel Hydra

VanaKernel Hydra is the same Linux 6.12 LTS line as VanaKernel (openVana Base),
but it starts from **Debian's tested kernel configuration** for the widest server
hardware support. On top of that it applies the VanaKernel changes
(`kernel/hydra.config`):

- **No KSMBD:** the in-kernel SMB server is switched off (security).
- **No staging or media drivers:** drivers that the kernel itself marks as not yet stable (staging) and the TV/webcam media stack are left out.
- **A screen on every machine:** generic graphics (simpledrm) plus the QEMU and Limbo emulator graphics drivers.
- **No debug info:** smaller and faster to build.

### Stability and security

- **Debian stable:** the most conservative mainstream Linux base.
- **Automatic security updates:** `unattended-upgrades` installs them every day, without automatic reboots.
- **Firewall on by default:** `ufw` blocks everything except SSH. Open more with e.g. `sudo ufw allow 80/tcp`.
- **fail2ban:** blocks addresses that keep guessing SSH passwords.
- **Locked-down accounts:** root can't log in, also not over SSH. Use your admin user with `sudo`.
- **Hardware watchdog:** a frozen machine restarts itself, if it has one. After a kernel panic it also reboots after 10 seconds.
- **Firmware and microcode:** CPU microcode updates for Intel and AMD, plus common network-card firmware.
- **Bounded logs:** logs are kept across reboots and limited to 500 MB.
- **Disk care:** SMART monitoring (`smartd`), SSD TRIM once a week, and a swap file.
- **Unique per machine:** every installation creates its own machine ID and SSH host keys.
- **Fallback kernel:** if VanaKernel Hydra ever fails to boot, pick "Debian GNU/Linux" in the boot menu.

## Install

1. Write the ISO to a USB stick (balenaEtcher, Rufus, `dd`) and boot it.
   **Turn off Secure Boot:** VanaKernel Hydra is not signed by Microsoft.
2. The live system logs in automatically. Run:
   ```
   sudo vana-install
   ```
3. The installer asks for the disk, hostname, admin user and password, keyboard layout and time zone. It then installs to the disk, for both UEFI and old-BIOS machines.
4. Reboot and log in, on the screen or with `ssh <user>@<ip-address>`. The IP address is shown at login.

Boot menu options in the live system:
- normal boot,
- **load into RAM** (the USB stick can be removed afterwards),
- **safe mode** (basic graphics, no boot screen),
- **Debian fallback kernel**.

## Everyday use

```sh
sudo apt update && sudo apt upgrade     # updates (security updates also install automatically)
sudo apt install ./something.deb        # install a .deb file
vana-exe setup.exe                      # run a Windows program (no screen needed)
sudo vana-get-chrome                    # install Google Chrome now (otherwise automatic)
fastfetch                               # system info
sudo ufw allow 443/tcp                  # open a port in the firewall
sudo ufw status                         # show firewall rules
```

### Google Chrome

Google's license doesn't allow shipping Chrome inside the ISO. Instead, openVana
Server downloads Google's official `chrome.deb` and installs it automatically on
the first start of an installed system with internet. If there's no connection,
it tries again at the next start. Google's package adds Google's update source,
and Chrome updates install automatically like security updates.

- **Install it now:** `sudo vana-get-chrome`. This also works in the live system.
- **Use it without a screen:** `google-chrome --headless --screenshot https://example.com`

### Static IP

Network cards get their address by DHCP. For a fixed address, edit
`/etc/systemd/network/20-wired.network`:

```ini
[Match]
Name=en* eth*

[Network]
Address=192.168.1.10/24
Gateway=192.168.1.1
DNS=192.168.1.1
```

Then run `sudo systemctl restart systemd-networkd`.

### Kernel updates

Debian's fallback kernel is updated by `apt` like any Debian package. VanaKernel
Hydra is built here, so new versions are published as `.deb` files on the
[release page](https://github.com/crasyonyt-max/openVana/releases/tag/server-1).
Install one with:

```
sudo apt install ./linux-image-*-vanakernel-hydra_*.deb
```

The matching `linux-headers` package is there too, for drivers that need to be
compiled (DKMS).

## Build

You need Docker or Podman and about 40 GB of disk space. Compiling the kernel takes 1–2 hours.

```sh
make            # -> out/openvana-server-1.0-amd64.iso
make run        # try it in QEMU
```

| Folder | What's in it |
|---|---|
| `kernel/` | VanaKernel Hydra: `hydra.config` + build script (produces `.deb` packages) |
| `rootfs/` | Package list, configuration overlay, root filesystem script, installer (`overlay/usr/sbin/vana-install`) |
| `iso/` | Boot menu + ISO script |
| `branding/src/` | Generators for the boot screen and the startup sound |

Licensed under the GNU GPL v3; the kernel stays GPL v2. Debian packages keep their own licenses (see `/usr/share/doc/*/copyright` on the system).
