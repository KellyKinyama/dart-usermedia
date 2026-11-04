#!/usr/bin/env bash
# Build the usermedia_ffi shared library on Linux (V4L2 + ALSA + X11 backends).
#
# Deps (Debian/Ubuntu):
#   sudo apt-get install -y build-essential cmake libasound2-dev libx11-dev
# The Dart native API headers are platform-agnostic; point DART_SDK_INCLUDE at
# any Dart SDK's include dir (the Windows Flutter one works from WSL).
#
#   DART_SDK_INCLUDE=/path/to/dart-sdk/include ./native/scripts/build-linux.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
shim="$(cd "$here/.." && pwd)/usermedia_ffi"
dart_inc="${DART_SDK_INCLUDE:-/mnt/c/flutter/flutter/bin/cache/dart-sdk/include}"
build="${BUILD_DIR:-/tmp/usermedia_ffi-build}"

cmake -S "$shim" -B "$build" -DCMAKE_BUILD_TYPE=Release \
  -DDART_SDK_INCLUDE="$dart_inc"
cmake --build "$build" -j"$(nproc)"

echo "Built: $build/libusermedia_ffi.so"
