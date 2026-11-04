# Platforms

Each capability is a native backend behind the same C ABI. The pull model
(`*_read` blocks for one frame/packet on the caller's thread) is identical
across platforms; only the OS API differs.

| Capability | Windows | Linux | Android | Output format |
| --- | --- | --- | --- | --- |
| Camera | Media Foundation `IMFSourceReader` | V4L2 mmap | Camera2 NDK | RGB32 (B,G,R,X) |
| Microphone | WASAPI shared-mode | ALSA `snd_pcm` | AAudio | interleaved PCM16 |
| Screen | DXGI Desktop Duplication | X11 `XGetImage` | — (Java only) | BGRA |
| H.264 encode | Media Foundation MFT | — | — | Annex-B |

✅ Windows + Linux backends are verified; 🔨 Android is cross-compiled and
links against the NDK but is not yet runtime-tested; macOS is unimplemented.

## Windows

- **Camera** — `IMFSourceReader` in sync mode with
  `MF_SOURCE_READER_ENABLE_VIDEO_PROCESSING`, converting the native format to
  RGB32.
- **Microphone** — WASAPI shared mode with `AUTOCONVERTPCM` → PCM16 at the
  requested rate/channels, polled.
- **Screen** — DXGI Desktop Duplication: a D3D11 device duplicates an output;
  each read copies into a CPU-readable staging texture. DXGI only delivers a
  frame when the desktop changes, so reads retry and consumers warm up a few
  frames.
- **H.264** — Media Foundation H.264 encoder MFT.
- Build: `./native/scripts/build_native.ps1` (Visual Studio Build Tools +
  CMake). Produces `native/usermedia_ffi/build/usermedia_ffi.dll`.

## Linux

- **Camera** — V4L2: enumerate `/dev/video*`, `S_FMT` YUYV, mmap streaming,
  convert YUYV → RGB32.
- **Microphone** — ALSA `snd_pcm` capture as PCM16 with xrun recovery.
- **Screen** — X11 `XGetImage` of the root window → BGRA.
- Build: `./native/scripts/build-linux.sh`
  (`build-essential cmake libasound2-dev libx11-dev`). The Dart native API
  headers (`dart_api_dl.c`) are platform-agnostic C and can come from any Dart
  SDK.

### Docker

The [Dockerfile](../Dockerfile) builds the Linux `.so` and runs the Dart suite
on Linux (`dart:stable` provides the SDK):

```bash
docker build -t dart-usermedia .
docker run --rm dart-usermedia                 # enumerate (headless-safe)
```

For real capture on a Linux host, pass devices/display:

```bash
docker run --rm --device /dev/video0 --device /dev/snd \
  -e DISPLAY=$DISPLAY -v /tmp/.X11-unix:/tmp/.X11-unix dart-usermedia \
  dart run example/enumerate_devices.dart
```

Verified in the container: native `.so` builds, all pure-Dart tests pass on
Linux, the `videotest` `getUserMedia` demo runs, and the real `.so` loads and
enumerates (0 cameras / 1 ALSA "Default" / 0 screens) without crashing.

## Android

- **Camera** — NDK Camera2 (`libcamera2ndk` + `libmediandk`): `AImageReader`
  (YUV_420_888) + a repeating preview request; `AImageReader_acquireLatestImage`
  → convert YUV_420_888 → RGB32 honoring plane strides.
- **Microphone** — AAudio (`libaaudio`) low-latency PCM16 input stream.
- **Screen** — unimplemented: Android screen capture uses Java
  **MediaProjection** (requires an Activity + permission intent); there is no
  NDK equivalent, so a JNI bridge in the host app would be required.
- Build: `./native/scripts/build-android.ps1 -Ndk <ndk> -Abi arm64-v8a`
  (needs the Android NDK). Cross-compiles per ABI.

**Runtime requirements (important):** Android use is not a CLI Dart program. A
**Flutter / Android host** must bundle the per-ABI `.so`, declare `CAMERA` /
`RECORD_AUDIO` in the manifest, and **request those permissions at runtime**
before `um_camera_open` / `um_mic_open` succeed — C/C++ cannot show the
permission dialog.

Verified: `libusermedia_ffi.so` cross-compiles to a valid **ELF64 AArch64**
linking `libcamera2ndk` / `libmediandk` / `libaaudio` / `libandroid` / `liblog`.

## macOS

Unimplemented. The natural backends are AVFoundation (camera + microphone) and
ScreenCaptureKit / CGDisplayStream (screen); the shim compiles as a no-op stub
there today, so the pure-Dart core and test drivers still work.
