// usermedia_ffi.h — flat C ABI over the native media-capture backend.
//
// Phase 0: only lifecycle + a sync ping + an async event-port handshake.
// Later phases grow this surface (enumerate, getUserMedia, tracks, events)
// without introducing any C++ types across the boundary.

#ifndef USERMEDIA_FFI_H
#define USERMEDIA_FFI_H

#include <stdint.h>

#if defined(_WIN32)
#define UM_EXPORT __declspec(dllexport)
#else
#define UM_EXPORT __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

// Opaque backend context. One per MediaDevices instance.
typedef struct um_context um_context;

// Lifecycle.
UM_EXPORT um_context* um_init(void);
UM_EXPORT void um_dispose(um_context* ctx);

// Sync smoke test: returns a known constant to prove the FFI call path.
UM_EXPORT int32_t um_ping(void);

// Wire up the async native -> Dart bridge.
//
// `um_init_dart_api` must be called once with the pointer obtained from
// `NativeApi.initializeApiDLData`. `um_set_event_port` registers the Dart
// SendPort.nativePort that async events are posted to.
UM_EXPORT intptr_t um_init_dart_api(void* data);
UM_EXPORT void um_set_event_port(um_context* ctx, int64_t port);

// Phase 0 async proof: posts `value` to the registered Dart port.
UM_EXPORT void um_emit_test_event(um_context* ctx, int64_t value);

// Reports whether this build is linked against libwebrtc.
//   0 = stub build (no libwebrtc)
//   1 = libwebrtc linked, video-capture DeviceInfo constructed
//   2 = libwebrtc linked, but DeviceInfo factory returned null
UM_EXPORT int32_t um_webrtc_available(void);

// --- Camera capture (Phase C) -----------------------------------------------
//
// Platform-backed video capture. On Windows this uses Media Foundation's
// IMFSourceReader in synchronous mode, so um_camera_read pulls one frame per
// call on the caller's thread (no background threads / callbacks). Non-Windows
// builds expose the same symbols as a no-op stub (um_camera_count == 0).
//
// Pixel format delivered by um_camera_read is 32-bit RGB (MFVideoFormat_RGB32:
// B,G,R,X byte order), i.e. width*height*4 bytes, top-down.

typedef struct um_camera um_camera;

// Number of video capture devices currently present. Also refreshes the
// internal device snapshot used by um_camera_name / um_camera_id / open.
UM_EXPORT int32_t um_camera_count(void);

// Copies the UTF-8 friendly name of device[index] into `buf`. Returns the
// number of bytes written (excluding the NUL), or -1 on error.
UM_EXPORT int32_t um_camera_name(int32_t index, char* buf, int32_t buf_len);

// Copies the UTF-8 symbolic-link id of device[index] into `buf`. Returns the
// number of bytes written (excluding the NUL), or -1 on error.
UM_EXPORT int32_t um_camera_id(int32_t index, char* buf, int32_t buf_len);

// Opens device[index], requesting a frame size close to width x height and
// RGB32 output. Returns NULL on failure.
UM_EXPORT um_camera* um_camera_open(int32_t index, int32_t width,
                                    int32_t height);

// Reports the negotiated frame geometry. `size` is the byte length of one
// frame expected by um_camera_read.
UM_EXPORT void um_camera_format(um_camera* cam, int32_t* width, int32_t* height,
                                int32_t* size);

// Blocking read of one frame into `dst` (at least um_camera_format's size).
// Returns the number of bytes written, or -1 on error.
UM_EXPORT int32_t um_camera_read(um_camera* cam, uint8_t* dst, int32_t dst_len);

// Closes a camera opened by um_camera_open.
UM_EXPORT void um_camera_close(um_camera* cam);

// --- Microphone capture (Phase D) -------------------------------------------
//
// Platform-backed audio capture. On Windows this uses WASAPI shared-mode
// capture with automatic format conversion to interleaved 16-bit PCM, polled
// synchronously (um_mic_read pulls one packet per call, no callbacks).
// Non-Windows builds expose the same symbols as a no-op stub.

typedef struct um_mic um_mic;

// Number of audio capture endpoints currently present. Refreshes the snapshot
// used by um_mic_name / um_mic_id / open.
UM_EXPORT int32_t um_mic_count(void);

// Copies the UTF-8 friendly name of endpoint[index] into `buf`. Returns bytes
// written (excluding NUL), or -1 on error.
UM_EXPORT int32_t um_mic_name(int32_t index, char* buf, int32_t buf_len);

// Copies the UTF-8 endpoint id of endpoint[index] into `buf`. Returns bytes
// written (excluding NUL), or -1 on error.
UM_EXPORT int32_t um_mic_id(int32_t index, char* buf, int32_t buf_len);

// Opens endpoint[index], requesting interleaved PCM16 at sample_rate/channels.
// Returns NULL on failure.
UM_EXPORT um_mic* um_mic_open(int32_t index, int32_t sample_rate,
                              int32_t channels);

// Reports the negotiated capture format.
UM_EXPORT void um_mic_format(um_mic* mic, int32_t* sample_rate,
                             int32_t* channels, int32_t* bits_per_sample);

// Blocking read of one capture packet into `dst`. Returns bytes written
// (a whole number of interleaved frames), or -1 on error.
UM_EXPORT int32_t um_mic_read(um_mic* mic, uint8_t* dst, int32_t dst_len);

// Closes a microphone opened by um_mic_open.
UM_EXPORT void um_mic_close(um_mic* mic);

// --- Screen capture (Phase E) -----------------------------------------------
//
// Platform-backed display capture. On Windows this uses DXGI Desktop
// Duplication, delivering full-desktop BGRA frames (width*height*4 bytes).
// um_screen_read pulls one frame per call on the caller's thread. Non-Windows
// builds expose the same symbols as a no-op stub (um_screen_count == 0).

typedef struct um_screen um_screen;

// Number of display outputs. Refreshes the snapshot used by name/id/open.
UM_EXPORT int32_t um_screen_count(void);

// Copies the UTF-8 device name of output[index] (e.g. "\\\\.\\DISPLAY1").
// Returns bytes written (excluding NUL), or -1 on error.
UM_EXPORT int32_t um_screen_name(int32_t index, char* buf, int32_t buf_len);

// Copies a UTF-8 id for output[index]. Returns bytes written, or -1.
UM_EXPORT int32_t um_screen_id(int32_t index, char* buf, int32_t buf_len);

// Opens output[index] for duplication. width/height are accepted for symmetry
// but capture is always full-desktop. Returns NULL on failure.
UM_EXPORT um_screen* um_screen_open(int32_t index, int32_t width,
                                    int32_t height);

// Reports the desktop frame geometry. `size` is the byte length of one frame.
UM_EXPORT void um_screen_format(um_screen* scr, int32_t* width, int32_t* height,
                                int32_t* size);

// Blocking read of one desktop frame (BGRA) into `dst`. Returns bytes written,
// or -1 on error.
UM_EXPORT int32_t um_screen_read(um_screen* scr, uint8_t* dst, int32_t dst_len);

// Closes a screen opened by um_screen_open.
UM_EXPORT void um_screen_close(um_screen* scr);

// --- H.264 encoder (Phase F+) -----------------------------------------------
//
// Encodes BGRA/BGRX frames to H.264 (Annex B). On Windows this uses the Media
// Foundation H.264 encoder MFT; input is converted to NV12 internally. Other
// platforms expose the same symbols as a no-op stub (um_h264_create == NULL).

typedef struct um_h264 um_h264;

// Creates an encoder for width x height at `fps`, targeting `bitrate` bits/s.
// width/height should be even. Returns NULL on failure.
UM_EXPORT um_h264* um_h264_create(int32_t width, int32_t height, int32_t fps,
                                  int32_t bitrate);

// Encodes one frame given as BGRA/BGRX (width*height*4 bytes). Writes Annex-B
// H.264 for any output the encoder emits into `dst`. Returns bytes written
// (0 when the encoder is still buffering), or -1 on error.
UM_EXPORT int32_t um_h264_encode(um_h264* enc, const uint8_t* bgra,
                                 int32_t bgra_len, uint8_t* dst,
                                 int32_t dst_len);

// Flushes buffered frames. Call repeatedly until it returns 0. Returns bytes
// written, or -1 on error.
UM_EXPORT int32_t um_h264_flush(um_h264* enc, uint8_t* dst, int32_t dst_len);

// Closes an encoder created by um_h264_create.
UM_EXPORT void um_h264_close(um_h264* enc);

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // USERMEDIA_FFI_H
