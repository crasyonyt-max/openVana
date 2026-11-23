#!/bin/sh
# Build openVana Base 1 end to end. Run inside the build container (see Makefile).
set -eu
cd "$(dirname "$0")"
./kernel/build-kernel.sh
./rootfs/build-rootfs.sh
./iso/build-iso.sh
