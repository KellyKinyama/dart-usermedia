# Plan: Port pion/mediadevices to Dart

Port [pion/mediadevices](https://github.com/pion/mediadevices) (a Go
implementation of the W3C [MediaDevices](https://developer.mozilla.org/en-US/docs/Web/API/MediaDevices)
API) to Dart.

> Strategy: port the **pure-Go core verbatim to pure Dart** (driver registry,
> constraint/property fitness, MediaStream/Track, the `io.Reader` frame
> pipeline). Replace pion's **cgo drivers** (camera/mic/screen) and **cgo
> codecs** with Dart FFI to the same OS capture APIs, reusing the Phase 0 FFI
> foundation (loader + event bridge + C shim) already built.

## Status (as of this pause)

- **Done:** Phases A–E (pure-Dart core; Windows camera/mic/screen capture via
  FFI), Phase F packaging + frame utilities, and the H.264 encoder
  (Media Foundation MFT). 39 tests pass; `dart analyze` clean.
- **Pending / future work:** macOS + Linux capture backends (currently no-op
  stubs), additional codecs (VP8/Opus), and a CI matrix.

## Architecture mapping (Go -> Dart)

| pion (Go) | Dart target | Native? |
| --- | --- | --- |
| `pkg/prop` (constraints, FitnessDistance) | `lib/src/prop/` | pure Dart |
| `pkg/frame` (Format) | `lib/src/frame/format.dart` | pure Dart |
| `pkg/io/video`, `pkg/io/audio` (Reader) | `lib/src/io/` | pure Dart |
| `pkg/driver` (Adapter/Driver/Manager) | `lib/src/driver/` | pure Dart |
| `mediadeviceinfo.go` | `lib/src/media_device_info.dart` | pure Dart |
| `mediastreamconstraints.go` | `lib/src/constraints.dart` | pure Dart |
| `mediastream.go`, `track.go`, `source.go` | `lib/src/media_stream.dart`, `track.dart` | pure Dart |
| `mediadevices.go` (GetUserMedia + discovery) | `lib/src/media_devices.dart` | pure Dart |
| `pkg/driver/camera` (MediaFoundation/DirectShow/AVFoundation/V4L2) | `lib/src/driver/camera/` + C shim | **FFI** |
| `pkg/driver/microphone` (malgo/miniaudio) | `lib/src/driver/microphone/` + C shim | **FFI** |
| `pkg/driver/screen` | `lib/src/driver/screen/` + C shim | **FFI** |
| `pkg/driver/videotest`, `audiotest` | `lib/src/driver/test/` | pure Dart |
| `pkg/codec/*` (x264/vpx/opus) | `lib/src/codec/` | **FFI**, later |

## Core model (extracted from source)

- `MediaConstraints { DeviceID, VideoConstraints, AudioConstraints }` — each
  field is a typed constraint (`Ideal` / `Exact` / `OneOf` / `Ranged`, plus
  `Bool`).
- `Media { DeviceID, Video, Audio }` — resolved concrete values.
- `FitnessDistance(Media) -> (double, bool)`: sum of per-field `Compare`
  distances; any infeasible field => `(0, false)`. Lower is better.
- Driver discovery (`GetUserMedia`): open all registered drivers of the kind,
  gather each driver's `Properties() -> List<Media>`, select the
  `(driver, property)` pair with the minimum feasible fitness distance, then
  `VideoRecord`/`AudioRecord` to obtain a frame `Reader`.

## Phases

### Phase A — pure-Dart core (no native) <- start here
- [ ] `frame.Format` enum.
- [ ] `prop`: `IntConstraint` / `FloatConstraint` / `StringConstraint` /
      `BoolConstraint` / `DurationConstraint` / `FrameFormatConstraint` with
      `Ideal` / `Exact` / `OneOf` / `Ranged` variants + `Compare` / `Value`.
- [ ] `Media` / `MediaConstraints` + `FitnessDistance` + `MergeConstraints`.
- [ ] `driver`: `Adapter`, `Driver`, `Info`, `Priority`, `State`, `Manager`
      (register/query/filter), `VideoRecorder` / `AudioRecorder`.
- [ ] `MediaDeviceInfo`, `MediaStreamConstraints`, `MediaTrackConstraints`.
- [ ] `io`: `video.Reader` / `audio.Reader` (frame + release callback).
- [ ] Unit tests mirroring pion's `*_test.go` (fitness distance cases).
- **Exit:** fitness/discovery tests pass with a fake in-memory driver.

### Phase B — test drivers + MediaStream/Track (no native)
- [ ] `videotest` / `audiotest` drivers (generated frames).
- [ ] `MediaStream`, `MediaStreamTrack`, `VideoTrack`, `AudioTrack`,
      `source`, `sampler`.
- **Exit:** capture a synthetic frame end-to-end via the public API, pure Dart.

### Phase C — real camera driver via FFI (reuses Phase 0 shim)
- [ ] Grow the C shim: enumerate video devices + formats, open a device, push
      frames to Dart (event bridge -> frame buffers with backpressure).
- [ ] Windows first (Media Foundation), then macOS (AVFoundation), Linux (V4L2).
- [ ] `camera` Dart driver implementing `Adapter` + `VideoRecorder`.
- **Exit:** real camera frames flow through `GetUserMedia` on 1 platform.

### Phase D — microphone driver via FFI
- [ ] Audio capture shim (miniaudio-style) -> `audio.Reader` samples.
- [ ] `microphone` Dart driver (`Adapter` + `AudioRecorder`).

### Phase E — screen capture (`GetDisplayMedia`)
- [ ] Screen/window capture shim per platform.

### Phase F — codecs (optional) + packaging
- [x] H.264 encoder via FFI (Media Foundation MFT, Windows). VP8/Opus: future.
- [x] Frame utilities (`toRgba`, BMP encoder), example, native build script,
      README/CHANGELOG/pubspec metadata.
- [ ] macOS/Linux capture backends (currently stubs).
- [ ] CI matrix.

## Reused from Phase 0 (kept)
- `lib/src/ffi/loader.dart`, `event_bridge.dart`, `bindings.dart`
- `native/usermedia_ffi/` C shim (handle API + Dart async bridge)

These become the transport for the camera/mic/screen drivers in Phases C–E.
The libwebrtc linkage path (CMake `WEBRTC_ROOT`, `webrtc_probe.cc`) is no longer
on the critical path; left in place but inert (stub mode).

## Target public API (Dart)

```dart
final stream = await getUserMedia(MediaStreamConstraints(
  video: (c) {
    c.width = const Ideal(640);
    c.height = const Ideal(480);
  },
));
final track = stream.videoTracks.first;
final reader = track.newReader();
final frame = await reader.read();
// ... use frame.image ...
track.close();
```

## Immediate next steps
1. Port `prop` + `frame` + `Media` / `FitnessDistance` (Phase A) with tests.
2. Port `driver` manager + `MediaDeviceInfo`.
3. Add the `videotest` driver to validate discovery end-to-end.
