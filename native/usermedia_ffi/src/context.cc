// context.cc — Phase 0 backend stub.
//
// No libwebrtc yet. This exists to validate the FFI boundary (sync call) and
// the async native -> Dart event bridge before adding native capture.

#include "usermedia_ffi.h"

#include "dart_bridge.h"

struct um_context {
  int64_t event_port = 0;
};

extern "C" {

um_context* um_init(void) { return new um_context(); }

void um_dispose(um_context* ctx) { delete ctx; }

int32_t um_ping(void) { return 0x7E57; }  // "TEST"

intptr_t um_init_dart_api(void* data) { return um_dart_init_api(data); }

void um_set_event_port(um_context* ctx, int64_t port) {
  if (ctx != nullptr) {
    ctx->event_port = port;
  }
}

void um_emit_test_event(um_context* ctx, int64_t value) {
  if (ctx != nullptr && ctx->event_port != 0) {
    um_dart_post_int(ctx->event_port, value);
  }
}

}  // extern "C"
