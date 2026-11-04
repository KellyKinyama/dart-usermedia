# Documentation

Engineering docs for the zteams media stack — a Dart port of
[pion/mediadevices](https://github.com/pion/mediadevices) plus a shared codec
library, developed across three sibling repositories.

| Repo | Role |
| --- | --- |
| `dart-usermedia` | Capture: `getUserMedia` / `getDisplayMedia` / `enumerateDevices` + native capture backends |
| `media-codecs` | Opus / VP8 / VP9 / H.264 encode + decode via FFI |
| `media-integration` | Path-dependency integration tests wiring the two together |

## Contents

- [ARCHITECTURE.md](ARCHITECTURE.md) — layered design, the pure-Dart core, and
  the FFI foundation.
- [PLATFORMS.md](PLATFORMS.md) — per-platform capture backends (Windows, Linux,
  Android, macOS) and how to build each.
- [CODECS.md](CODECS.md) — the `media-codecs` package, library acquisition, and
  the libvpx-from-source workaround.
- [TESTING.md](TESTING.md) — test tags, fidelity tests, the integration repo,
  and Docker.

## Status at a glance

| Capability | Windows | Linux | Android | macOS |
| --- | :-: | :-: | :-: | :-: |
| Camera | ✅ MF | ✅ V4L2 | 🔨 Camera2 | — |
| Microphone | ✅ WASAPI | ✅ ALSA | 🔨 AAudio | — |
| Screen | ✅ DXGI | ✅ X11 | — | — |
| H.264 encode (capture lib) | ✅ MF MFT | — | — | — |
| Codecs (Opus/VP8/VP9/H.264) | ✅ | ✅* | — | — |

✅ verified with real data · 🔨 builds + links, not yet runtime-tested ·
— not implemented. *Codecs build on Linux via apt-installed libraries.

The pure-Dart core (constraint/fitness model, driver registry, MediaStream /
Track pipeline) and the synthetic `videotest` / `audiotest` drivers run on
every platform with no native library.
