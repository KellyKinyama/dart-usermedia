// android_probe.c — exercises the Android capture backends over the C ABI for
// running on a device/emulator via adb shell. Enumerates, then tries to open
// the first camera and read one frame (which needs CAMERA permission — a raw
// adb-shell process has none, so this documents the boundary).

#include <stdio.h>
#include <stdlib.h>

#include "usermedia_ffi.h"

int main(void) {
  char buf[256];

  const int cams = um_camera_count();
  printf("cameras: %d\n", cams);
  for (int i = 0; i < cams; i++) {
    if (um_camera_name(i, buf, sizeof buf) >= 0) printf("  cam[%d] %s\n", i, buf);
  }

  printf("microphones: %d\n", um_mic_count());
  for (int i = 0; i < um_mic_count(); i++) {
    if (um_mic_name(i, buf, sizeof buf) >= 0) printf("  mic[%d] %s\n", i, buf);
  }

  printf("screens: %d\n", um_screen_count());

  if (cams > 0) {
    printf("opening cam[0] ...\n");
    um_camera* cam = um_camera_open(0, 640, 480);
    if (!cam) {
      printf("  open failed (expected without CAMERA permission)\n");
    } else {
      int w = 0, h = 0, size = 0;
      um_camera_format(cam, &w, &h, &size);
      printf("  opened %dx%d (%d bytes/frame)\n", w, h, size);
      unsigned char* frame = (unsigned char*)malloc(size);
      int n = 0;
      for (int tries = 0; tries < 15 && n <= 0; tries++) {
        n = um_camera_read(cam, frame, size);
      }
      long nonzero = 0;
      for (int i = 0; i < n; i++) nonzero += frame[i] != 0;
      printf("  read %d bytes, nonZero=%ld\n", n, nonzero);
      free(frame);
      um_camera_close(cam);
    }
  }
  return 0;
}
