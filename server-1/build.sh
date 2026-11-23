#!/bin/bash
# Build openVana Server 1.0 end to end (inside the build container, see Makefile).
set -euo pipefail
cd "$(dirname "$0")"
./kernel/build-kernel.sh
./rootfs/build-rootfs.sh
./iso/build-iso.sh
