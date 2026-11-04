#!/usr/bin/env bash
# One-shot: ensure deps, then build the Linux usermedia_ffi .so. For WSL.
set -euo pipefail

need_install=0
for t in gcc g++ cmake make; do
  command -v "$t" >/dev/null 2>&1 || need_install=1
done
for h in /usr/include/linux/videodev2.h /usr/include/alsa/asoundlib.h \
         /usr/include/X11/Xlib.h; do
  [ -f "$h" ] || need_install=1
done

if [ "$need_install" = 1 ]; then
  echo "== installing deps =="
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    build-essential cmake libasound2-dev libx11-dev linux-libc-dev
fi

echo "== toolchain =="
gcc --version | head -1
cmake --version | head -1
echo "videodev2: $([ -f /usr/include/linux/videodev2.h ] && echo yes || echo no)"
echo "alsa:      $([ -f /usr/include/alsa/asoundlib.h ] && echo yes || echo no)"
echo "x11:       $([ -f /usr/include/X11/Xlib.h ] && echo yes || echo no)"

shim=/mnt/c/projects/zteams/dart-usermedia/native/usermedia_ffi
dart_inc=/mnt/c/flutter/flutter/bin/cache/dart-sdk/include
build=/tmp/usermedia_ffi-build

echo "== configure + build =="
cmake -S "$shim" -B "$build" -DCMAKE_BUILD_TYPE=Release \
  -DDART_SDK_INCLUDE="$dart_inc"
cmake --build "$build" -j"$(nproc)"

echo "== result =="
ls -la "$build"/libusermedia_ffi.so
