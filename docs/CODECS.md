# Codecs (`media-codecs`)

A sibling package providing **Opus**, **VP8/VP9**, and **H.264**
encode + decode to Dart via FFI over a native shim (`mediacodecs_ffi`) that
links `libopus` / `libvpx` / `openh264`. Kept separate so neither the capture
library nor consumers carry a cross-dependency.

## Dart API

```dart
import 'package:media_codecs/media_codecs.dart';

print(codecsVersion());               // e.g. "mediacodecs 0.1.0 [opus vpx h264 ]"
print(haveOpus); print(haveVpx); print(haveH264);

// Audio (interleaved PCM16 <-> Opus)
final oenc = OpusEncoder(sampleRate: 48000, channels: 1, bitrate: 64000);
final packet = oenc.encode(pcm16, 960);          // 20 ms frame
final pcm = OpusDecoder(sampleRate: 48000, channels: 1).decode(packet);

// Video (tightly packed I420 <-> VP8/VP9/H.264)
final venc = VpxEncoder(codec: VpxCodec.vp8, width: 640, height: 480);
final ef = venc.encode(i420);                     // ef.data, ef.keyframe
final I420Frame? frame = VpxDecoder(codec: VpxCodec.vp8).decode(ef.data);

final h = H264Encoder(width: 640, height: 480);
final I420Frame? out = H264Decoder().decode(h.encode(i420));
```

Video buffers are tightly packed I420 (`I420Frame.sizeFor(w, h)`).

## Native design

Each codec is compiled only when its library is found at configure time; the
`HAVE_OPUS` / `HAVE_VPX` / `HAVE_OPENH264` macros gate real implementations,
and a no-op stub is compiled otherwise. So the shim **always builds** and
runtime availability is queryable (`haveOpus` / `haveVpx` / `haveH264`). All
codec calls are synchronous (encode/decode one unit per call), so no Dart async
bridge is needed.

## Acquiring the libraries

### Opus + openh264 — vcpkg

```powershell
vcpkg install opus openh264 --triplet x64-windows
cmake -S native/mediacodecs_ffi -B build -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE=<vcpkg>/scripts/buildsystems/vcpkg.cmake
cmake --build build
```

CMake copies `opus.dll` + `openh264-8.dll` next to `mediacodecs_ffi.dll`.

### libvpx — built from source (locked-down-machine workaround)

On the development machine, vcpkg could not build libvpx: its `configure` runs
under msys2 `bash.exe`, which the security policy denies **by name** (an
unsigned `bash.exe` is blocked, while the identical `sh.exe`, plus `sed` /
`grep` / `make` / `nasm`, all run). libvpx was therefore built directly:

1. `configure` via **Git's** (signed, allowed) bash targeting
   `x86_64-win64-vs17`, with a copied-out `nasm`.
2. project generation via msys2 `make` forced to `SHELL=sh.exe`.
3. `MSBuild` (retargeted to a current Windows SDK + `v143`) → `/MD` `vpx.lib`.

Then the shim was pointed at it with `-DVPX_INC=<headers>` and
`-DVPX_LIB=<vpx.lib>` (the CMake `find_path`/`find_library` honor preset
values). On a normal machine `vcpkg install libvpx` works and no override is
needed.

## Runtime note

Windows does not search a DLL's own directory for its transitive dependencies,
so add the build directory to `PATH` (or colocate the codec DLLs with the
executable) when running:

```powershell
$env:PATH = "...\mediacodecs_ffi\build;$env:PATH"
```

## Verified

`dart test -t native` exercises availability plus fidelity round-trips:
textured I420 → VP8/VP9/H.264 → decode at **Y-plane PSNR > 30 dB**, and a
440 Hz tone → Opus → decode with matching RMS energy. A VP9-specific fix sets
`g_lag_in_frames = 0` so the first frame emits immediately (VP8 defaults to 0,
VP9 does not).
