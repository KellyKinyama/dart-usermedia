# third_party/

libwebrtc is **not** vendored in this repository. It is acquired locally and
referenced by the CMake build via `WEBRTC_ROOT` + `WEBRTC_LIB` (see
[native/usermedia_ffi/CMakeLists.txt](../native/usermedia_ffi/CMakeLists.txt)).

## Two acquisition paths

| Path | Script | Trade-off |
| --- | --- | --- |
| Prebuilt | [fetch_webrtc_prebuilt.ps1](../native/scripts/fetch_webrtc_prebuilt.ps1) | Fast; must trust a third-party build + match ABI |
| From source | [build_webrtc_source.ps1](../native/scripts/build_webrtc_source.ps1) | Full control + pinned revision; tens of GB, long build |

## Pinned revision

Record the exact libwebrtc branch/revision used here once chosen:

- Revision: _TBD_
- Source: _TBD_
- Acquired: _TBD_

## Configure the shim against it

```powershell
cmake -S native/usermedia_ffi -B native/usermedia_ffi/build -G Ninja `
  -DCMAKE_BUILD_TYPE=Release `
  -DDART_SDK_INCLUDE=C:/flutter/flutter/bin/cache/dart-sdk/include `
  -DWEBRTC_ROOT=<dir containing api/ modules/ rtc_base/> `
  -DWEBRTC_LIB=<path to webrtc.lib>
cmake --build native/usermedia_ffi/build
```

Verify linkage with `dart test -t native` — the `reports libwebrtc link status`
test should then return `1` instead of `0`.
