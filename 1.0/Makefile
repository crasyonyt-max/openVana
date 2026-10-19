# openVana 1.0 — `make` builds out/openvana-1.0-x86_64.iso inside a container.
ENGINE ?= $(shell command -v podman 2>/dev/null || echo docker)
IMAGE  ?= openvana-build

iso: builder
	$(ENGINE) run --rm -v "$(CURDIR)":/src $(IMAGE) ./build.sh

builder:
	$(ENGINE) build -t $(IMAGE) -f Containerfile .

shell:
	$(MAKE) -C shell

run: ## boot the ISO in QEMU (UEFI if OVMF is installed)
	qemu-system-x86_64 -enable-kvm -m 4G -smp 4 -cpu host \
	    -device virtio-vga-gl -display gtk,gl=on \
	    -cdrom out/openvana-1.0-x86_64.iso

clean:
	rm -rf out
	$(MAKE) -C shell clean

.PHONY: iso builder shell run clean
