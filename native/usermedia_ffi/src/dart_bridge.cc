// dart_bridge.cc — implementation of the native -> Dart async bridge.

#include "dart_bridge.h"

#include "dart_api_dl.h"

extern "C" {

intptr_t um_dart_init_api(void* data) { return Dart_InitializeApiDL(data); }

void um_dart_post_int(int64_t port, int64_t value) {
  Dart_CObject obj;
  obj.type = Dart_CObject_kInt64;
  obj.value.as_int64 = value;
  Dart_PostCObject_DL(port, &obj);
}

}  // extern "C"
