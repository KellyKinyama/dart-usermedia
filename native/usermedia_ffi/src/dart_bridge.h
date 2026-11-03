// dart_bridge.h — minimal wrapper over the Dart native API (dart_api_dl.h)
// for posting async messages from native threads to a Dart isolate.

#ifndef USERMEDIA_DART_BRIDGE_H
#define USERMEDIA_DART_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Initialize the Dart DL API. Pass NativeApi.initializeApiDLData.
// Returns 0 on success (matches Dart_InitializeApiDL convention).
intptr_t um_dart_init_api(void* data);

// Post a single int64 to the given Dart port. Thread-safe once initialized.
void um_dart_post_int(int64_t port, int64_t value);

#ifdef __cplusplus
}
#endif

#endif  // USERMEDIA_DART_BRIDGE_H
