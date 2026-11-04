# Linux build + test image for dart_usermedia.
#
# Builds the native usermedia_ffi shared library (V4L2 + ALSA + X11 backends)
# and runs the pure-Dart test suite on Linux. The dart:stable image bundles the
# Dart SDK, whose include/ dir provides the platform-agnostic dart_api_dl.c.
#
#   docker build -t dart-usermedia .
#   docker run --rm dart-usermedia
#
# To exercise real capture on a Linux host, pass devices/display, e.g.:
#   docker run --rm --device /dev/video0 --device /dev/snd \
#     -e DISPLAY=$DISPLAY -v /tmp/.X11-unix:/tmp/.X11-unix dart-usermedia \
#     dart run example/enumerate_devices.dart

FROM dart:stable

RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential cmake libasound2-dev libx11-dev linux-libc-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY . .

RUN dart pub get

# Build the native shim using the image's own Dart SDK headers.
RUN cmake -S native/usermedia_ffi -B native/usermedia_ffi/build \
      -DCMAKE_BUILD_TYPE=Release -DDART_SDK_INCLUDE="$DART_SDK/include" \
    && cmake --build native/usermedia_ffi/build -j"$(nproc)"

# Pure-Dart core + drivers (no hardware needed).
RUN dart test -x native

# getUserMedia pipeline via the synthetic videotest driver, on Linux.
RUN dart run bin/dart_usermedia.dart

# Default: load the real .so and enumerate (headless-safe).
CMD ["dart", "run", "example/enumerate_devices.dart"]
