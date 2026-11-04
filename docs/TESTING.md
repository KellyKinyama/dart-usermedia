# Testing

## dart-usermedia

Tests are tagged so hardware-dependent ones self-skip when a device or the
native library is absent.

```powershell
dart test                 # everything (hardware tests self-skip)
dart test -x native       # pure-Dart only — no native library needed
dart test -t camera       # only the camera hardware test
```

| Tag | Needs |
| --- | --- |
| `native` | the built `usermedia_ffi` shared library |
| `camera` | a connected camera |
| `microphone` | a capture device |
| `screen` | a display |
| `h264` | the Media Foundation H.264 encoder |

The pure-Dart suite (constraints/fitness, driver registry, discovery, stream/
track, frame conversion, BMP) runs everywhere, including inside the Linux
Docker image (verified: all pure-Dart tests pass on Linux, and the `videotest`
`getUserMedia` demo produces a 640×480 I420 frame + 48 kHz audio).

## media-codecs

```powershell
$env:PATH = "...\mediacodecs_ffi\build;$env:PATH"   # resolve codec DLLs
dart test -t native
```

- `mediacodecs_test.dart` — availability + basic encode/decode (self-skips per
  codec when not linked).
- `roundtrip_test.dart` — **fidelity**: textured I420 → VP8/VP9/H.264 → decode
  with Y-plane PSNR > 30 dB; 440 Hz tone → Opus → decode with matching RMS
  energy.

> openh264 prints an informational warning to stderr, which can make the shell
> report a non-zero exit code; the test runner's `All tests passed!` is
> authoritative.

## media-integration

A dedicated repo holds the `path:` dependencies on both packages, so neither
`dart-usermedia` nor `media-codecs` depends on the other.

```
dart-usermedia ─┐
                 ├── path deps ──▶ media-integration (tests only)
media-codecs   ─┘
```

`pipeline_test.dart` runs end-to-end capture → codec:

- videotest I420 → VP8 / VP9 → decode (PSNR > 30 dB)
- audiotest PCM16 → Opus → decode (length preserved)
- **real camera** RGB32 → I420 → H.264 → decode (PSNR > 28 dB)

Run with **both** native build dirs on `PATH` so each shim and its dependency
DLLs resolve:

```powershell
$env:PATH = "..\media-codecs\native\mediacodecs_ffi\build;" +
            "..\dart-usermedia\native\usermedia_ffi\build;$env:PATH"
dart test -t native
```

## Terminal note (Windows)

Git and openh264 write progress/warnings to stderr; PowerShell surfaces that as
a non-zero exit code even on success. Trust the tool's own summary line
(`All tests passed!`, `main -> main`) over the shell exit code.
