# openVana Server 1.0 — `make` builds out/openvana-server-1.0-amd64.iso in a container.
ENGINE ?= $(shell command -v podman 2>/dev/null || echo docker)
IMAGE  ?= openvana-server-build

iso: builder
	$(ENGINE) run --rm --privileged -v "$(CURDIR)":/src $(IMAGE) ./build.sh

builder:
	$(ENGINE) build -t $(IMAGE) -f Containerfile .

run: ## try the ISO in QEMU
	qemu-system-x86_64 -enable-kvm -m 4G -smp 4 -cdrom out/openvana-server-1.0-amd64.iso

clean:
	rm -rf out

.PHONY: iso builder run clean
