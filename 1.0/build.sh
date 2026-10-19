#!/bin/sh
# Build openVana 1.0 end to end. Run inside the build container (see Makefile).
set -eu
cd "$(dirname "$0")"
./kernel/build-kernel.sh
./rootfs/build-rootfs.sh
./iso/build-iso.sh
