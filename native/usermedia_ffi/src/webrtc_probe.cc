// webrtc_probe.cc — proves libwebrtc is linked (Phase 1 exit criteria).
//
// In stub mode (no UM_HAVE_WEBRTC) this returns 0. When built against
// libwebrtc it references a real symbol — the video-capture DeviceInfo factory
// used by Phase 2 — so a successful link proves the whole toolchain resolves
// libwebrtc symbols.

#include "usermedia_ffi.h"

#ifdef UM_HAVE_WEBRTC
#include <memory>

#include "modules/video_capture/video_capture_factory.h"
#endif

extern "C" {

int32_t um_webrtc_available(void) {
#ifdef UM_HAVE_WEBRTC
  std::unique_ptr<webrtc::VideoCaptureModule::DeviceInfo> info(
      webrtc::VideoCaptureFactory::CreateDeviceInfo());
  // 1 = linked and DeviceInfo constructed; 2 = linked but factory returned null.
  return info ? 1 : 2;
#else
  return 0;
#endif
}

}  // extern "C"
