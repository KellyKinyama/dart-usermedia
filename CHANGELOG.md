## 1.0.0

- Port of pion/mediadevices to Dart.
- Pure-Dart core: W3C constraint/fitness-distance model, driver registry and
  discovery, `MediaStream`/`VideoTrack`/`AudioTrack`, and the frame/sample
  reader pipeline.
- `getUserMedia`, `getDisplayMedia`, and `enumerateDevices`.
- Native capture via `dart:ffi` (`usermedia_ffi`) on Windows: camera
  (Media Foundation), microphone (WASAPI), and screen (DXGI Desktop
  Duplication). No-op stub on other platforms.
- Synthetic `videotest` / `audiotest` drivers for hardware-free use.
- Frame helpers: `toRgba()` (RGB32/BGRA/I420) and a BMP encoder
  (`encodeBmp` / `frameToBmp`).
- H.264 encoding (`H264Encoder`) via the Media Foundation encoder MFT on
  Windows; encodes BGRA/BGRX frames to Annex-B H.264.
