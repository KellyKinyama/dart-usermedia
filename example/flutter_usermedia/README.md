# usermedia_example

A Flutter app demonstrating [`dart_usermedia`](../../) `getUserMedia` /
`getDisplayMedia` across **Windows, Linux, and Android** — live camera preview,
a microphone level meter, device enumeration, and (desktop) screen capture.

Capture runs in a background isolate (the FFI reads are blocking), posting
RGBA frames to the UI isolate which renders them via `RawImage`.

## What it shows

- **Camera** preview (Camera2 on Android, Media Foundation on Windows, V4L2 on
  Linux) — frames decoded to `ui.Image` with live FPS.
- **Videotest** — the synthetic pure-Dart source, works with no hardware.
- **Screen** (desktop only) — `getDisplayMedia`.
- **Microphone** level meter (AAudio / WASAPI / ALSA).
- **Device list** from `enumerateDevices()`.

## The native library

The app loads `usermedia_ffi` via `dart:ffi`. Build it per target and make it
discoverable:

### Android

Per-ABI `.so`s are bundled from `android/app/src/main/jniLibs/<abi>/`:

```powershell
# from the dart-usermedia repo root, then copy each
# build-android-<abi>/libusermedia_ffi.so into jniLibs/<abi>/
./native/scripts/build-android.ps1 -Ndk <ndk> -Abi arm64-v8a
./native/scripts/build-android.ps1 -Ndk <ndk> -Abi x86_64   # emulators
```

`minSdk` is 26 (AAudio); `CAMERA` / `RECORD_AUDIO` are declared in the manifest
and requested at runtime via `permission_handler`.

```bash
flutter run -d emulator-5554        # or a connected phone
```

### Windows / Linux

Build the desktop library and point the loader at it (it also checks the
directory next to the executable):

```powershell
# Windows
../../native/scripts/build_native.ps1
$env:USERMEDIA_FFI_PATH = "..\..\native\usermedia_ffi\build"
flutter run -d windows
```

```bash
# Linux
../../native/scripts/build-linux.sh
export USERMEDIA_FFI_PATH="../../native/usermedia_ffi/build"
flutter run -d linux
```

If the library isn't found, the app shows a "Native library not found" screen
(with search details) instead of crashing.

## Notes

- On a **headless Android emulator** the synthetic camera may not stream to the
  app; use **Videotest** for a guaranteed live preview, or a physical device /
  windowed emulator with a working camera for real frames.
- Prebuilt `.so`/`.dll` files are git-ignored (build output) — build them
  locally with the scripts above.
