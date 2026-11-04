# Architecture

`dart-usermedia` is a Dart port of pion/mediadevices. The **pure-Go core is
ported verbatim to pure Dart**; pion's cgo capture drivers are replaced with
Dart FFI over a small per-platform native shim (`usermedia_ffi`).

```
getUserMedia / getDisplayMedia / enumerateDevices        (pure Dart)
        │  driver discovery — W3C SelectSettings / fitness distance
        ▼
Driver registry — Adapter / VideoRecorder / AudioRecorder (pure Dart)
        │
        ├── videotest / audiotest            (pure Dart, synthetic)
        └── camera / microphone / screen ──▶ usermedia_ffi  (C/C++ via dart:ffi)
                                                 MF · WASAPI · DXGI   (Windows)
                                                 V4L2 · ALSA · X11    (Linux)
                                                 Camera2 · AAudio     (Android)
```

## Pure-Dart core (`lib/src`)

Ported faithfully from pion, so behavior matches the W3C spec:

- **Constraints / fitness** (`prop/`): typed constraints
  (`IntIdeal`/`IntExact`/`IntRanged`/`IntOneOf`, plus Float/String/Bool/
  Duration/FrameFormat) and `MediaConstraints.fitnessDistance(Media)`
  implementing W3C fitness distance. `Media.mergeConstraints` + `merge`
  resolve the selected property set.
- **Driver registry** (`driver/`): `Adapter` (open/close/properties),
  `Driver` (id/info/status), `VideoRecorder` / `AudioRecorder`, and a
  `Manager` singleton with filters. Wrapper variants make
  `is VideoRecorder` / `is AudioRecorder` behave like Go's type assertions.
- **Discovery** (`media_devices.dart`): `getUserMedia` / `getDisplayMedia`
  open each registered driver, score every advertised property against the
  constraints (adjusted by driver priority), pick the minimum feasible
  distance, then `videoRecord` / `audioRecord` to obtain a frame reader.
- **Stream / track** (`media_stream.dart`, `track.dart`, `source.dart`,
  `io/broadcaster.dart`): `MediaStream`, `VideoTrack` / `AudioTrack`, and a
  reader broadcaster.
- **Frames** (`io/reader.dart`, `frame/`): `VideoFrame` (width/height/format/
  data) and `AudioChunk`; `FrameFormat` (I420, RGB32/BGRX, BGRA, …);
  `FrameConvert.toRgba()` and a BMP encoder.

## FFI foundation (`lib/src/ffi`)

- **loader.dart** — locates and opens the shared library (`USERMEDIA_FFI_PATH`
  override, package-root `native/.../build`, then the OS search path); caches
  the handle.
- **bindings.dart** — typed `lookupFunction` views over the C ABI.
- **event_bridge.dart** — async native→Dart via `dart_api_dl` +
  `Dart_PostCObject` and a `ReceivePort` (proven in the Phase 0 spike).

## Native shim (`native/usermedia_ffi`)

A flat, handle-based **C ABI** (no C++ types cross the boundary) declared in
`include/usermedia_ffi.h`. Each capability has a tiny lifecycle:
`*_count` / `*_name` / `*_id` / `*_open` / `*_format` / `*_read` / `*_close`.

The **pull model** is the key design choice: `*_read` blocks and returns one
frame/packet on the caller's thread — no background threads or callbacks. This
keeps the FFI boundary simple and maps cleanly onto Media Foundation's
synchronous `IMFSourceReader`, V4L2 `DQBUF`, WASAPI/ALSA polling, DXGI
`AcquireNextFrame`, and Android's `AImageReader` / `AAudioStream_read`.

Platform selection is by preprocessor branch. Because Android also defines
`__linux__`, the `#elif defined(__ANDROID__)` branch always precedes
`#elif defined(__linux__)` (and `elseif(ANDROID)` precedes `elseif(UNIX)` in
CMake).

See [PLATFORMS.md](PLATFORMS.md) for the per-platform backends.
