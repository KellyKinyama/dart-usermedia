# dart_usermedia

A Dart port of [pion/mediadevices](https://github.com/pion/mediadevices): a
[`getUserMedia`](https://developer.mozilla.org/en-US/docs/Web/API/MediaDevices/getUserMedia)
/ [`getDisplayMedia`](https://developer.mozilla.org/en-US/docs/Web/API/MediaDevices/getDisplayMedia)
style API for capturing **camera**, **microphone**, and **screen** media.

The constraint/driver-discovery core and the stream/track pipeline are pure
Dart. Real device capture is provided by a small native shim (`usermedia_ffi`)
reached through `dart:ffi`.

## Status

| Capability | Backend | Windows | macOS | Linux |
| --- | --- | :-: | :-: | :-: |
| Camera (`getUserMedia`) | Media Foundation | ✅ | — | — |
| Microphone (`getUserMedia`) | WASAPI | ✅ | — | — |
| Screen (`getDisplayMedia`) | DXGI Desktop Duplication | ✅ | — | — |
| H.264 encoding | Media Foundation MFT | ✅ | — | — |
| Synthetic test drivers | pure Dart | ✅ | ✅ | ✅ |

Non-Windows platforms compile the native shim as a no-op stub today (the pure
Dart core and the test drivers still work); macOS/Linux capture backends are
future work.

## Usage

```dart
import 'package:dart_usermedia/dart_usermedia.dart';

void main() {
  registerCameras(); // or registerVideotest() for a synthetic source

  final stream = getUserMedia(MediaStreamConstraints(
    video: (c) {
      c.video.width = const IntIdeal(640);
      c.video.height = const IntIdeal(480);
    },
  ));

  final track = stream.videoTracks.single;
  final (frame, release) = track.newReader().read();
  print('${frame.width}x${frame.height} ${frame.format}');
  release();
  track.close();
}
```

Constraints mirror the W3C fitness-distance model: `IntIdeal`/`IntExact`/
`IntRanged`/`IntOneOf` (and `Float`/`String`/`Bool`/`Duration`/`FrameFormat`
equivalents). `getUserMedia` opens each registered driver, scores every
advertised property set against the constraints, and binds the best match.

### Enumerate devices

```dart
registerCameras();
registerMicrophones();
for (final d in enumerateDevices()) {
  print('${d.label} (${d.kind.name})');
}
```

### Screen capture

```dart
registerScreens();
final stream = getDisplayMedia(MediaStreamConstraints(video: (c) {}));
final (frame, release) = stream.videoTracks.single.newReader().read();
// frame.format == FrameFormat.bgra
release();
```

### Save a frame

```dart
import 'dart:io';
File('frame.bmp').writeAsBytesSync(frameToBmp(frame));
```

### Encode frames to H.264

Encodes BGRA/BGRX frames (camera, screen) to Annex-B H.264 via the Media
Foundation encoder MFT. `encode()` may return empty bytes while the encoder
buffers; call `flush()` at the end to drain.

```dart
final encoder = H264Encoder(width: 640, height: 480, fps: 30, bitrate: 2000000);
final sink = File('out.h264').openSync(mode: FileMode.write);
for (var i = 0; i < 60; i++) {
  final (frame, release) = reader.read();
  sink.writeFromSync(encoder.encode(frame));
  release();
}
sink.writeFromSync(encoder.flush());
encoder.close();
sink.closeSync();
```

See [example/capture_frame.dart](example/capture_frame.dart) for a runnable
example (camera with a videotest fallback).

## Building the native library

The native shim is required for real camera/microphone/screen capture. On
Windows (with Visual Studio Build Tools + CMake):

```powershell
./native/scripts/build_native.ps1
```

This builds `native/usermedia_ffi/build/usermedia_ffi.dll`, which the loader
discovers automatically. You can also point the loader at a prebuilt library
with the `USERMEDIA_FFI_PATH` environment variable.

## Testing

```powershell
dart test            # all tests (hardware tests self-skip if no device)
dart test -x native  # pure-Dart only (no native library needed)
dart test -t camera  # only the camera hardware test
```

Hardware-dependent tests are tagged `native`, `camera`, `microphone`,
`screen`, and `h264`, and skip themselves when the device or native library is
absent.

## Architecture

```
getUserMedia / getDisplayMedia / enumerateDevices   (pure Dart)
        |  driver discovery (W3C fitness distance)
        v
Driver registry -- Adapter / VideoRecorder / AudioRecorder   (pure Dart)
        |
        +-- videotest / audiotest            (pure Dart)
        +-- camera / microphone / screen --> usermedia_ffi (C/C++ via dart:ffi)
                                                 MF / WASAPI / DXGI

H264Encoder --------------------------------> usermedia_ffi (Media Foundation MFT)
```

See [PLAN.md](PLAN.md) for the full porting plan and phase breakdown.
