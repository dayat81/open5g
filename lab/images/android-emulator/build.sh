#!/bin/bash
# Build the Open5G emulator image from the vendored upstream tree plus the patch.
set -euo pipefail

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
tag=${ANDROID_UE_ANDROID_IMAGE:-open5g-android-emulator:local}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

cp -a "$script_dir/upstream/." "$work/"
cp "$script_dir/open5g-preflight.sh" "$work/scripts/open5g-preflight.sh"
chmod 0755 "$work/scripts/open5g-preflight.sh" "$work/scripts/"*.sh
patch -p1 -d "$work" <"$script_dir/patches/0001-open5g-boot.patch"
docker build -t "$tag" "$work"
echo "android-emulator: built ${tag}"
