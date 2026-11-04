// camera.cc — platform video capture for the usermedia_ffi shim (Phase C).
//
// Windows: Media Foundation IMFSourceReader in synchronous mode. Video
// processing is enabled so the reader converts the camera's native format
// (YUY2/NV12/MJPG/...) to RGB32 for us. Other platforms: a no-op stub.

#include "usermedia_ffi.h"

#if defined(_WIN32)

#include <mfapi.h>
#include <mferror.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <shlwapi.h>
#include <windows.h>

#include <mutex>
#include <string>
#include <vector>

#pragma comment(lib, "mfplat.lib")
#pragma comment(lib, "mf.lib")
#pragma comment(lib, "mfreadwrite.lib")
#pragma comment(lib, "mfuuid.lib")
#pragma comment(lib, "shlwapi.lib")
#pragma comment(lib, "ole32.lib")

namespace {

template <class T>
void SafeRelease(T** pp) {
  if (*pp) {
    (*pp)->Release();
    *pp = nullptr;
  }
}

std::once_flag g_mf_once;
bool g_mf_ok = false;

void EnsureMediaFoundation() {
  std::call_once(g_mf_once, [] {
    // Dart's thread may already have COM initialized in a different mode;
    // tolerate that.
    HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    if (hr == RPC_E_CHANGED_MODE) {
      hr = S_OK;
    }
    g_mf_ok = SUCCEEDED(MFStartup(MF_VERSION, MFSTARTUP_LITE));
  });
}

std::string WideToUtf8(const wchar_t* w) {
  if (!w) return std::string();
  int len = WideCharToMultiByte(CP_UTF8, 0, w, -1, nullptr, 0, nullptr, nullptr);
  if (len <= 0) return std::string();
  std::string out(static_cast<size_t>(len - 1), '\0');
  WideCharToMultiByte(CP_UTF8, 0, w, -1, out.data(), len, nullptr, nullptr);
  return out;
}

struct DeviceEntry {
  std::string name;
  std::string symlink;
};

std::mutex g_devices_mu;
std::vector<DeviceEntry> g_devices;

// Enumerates video capture devices into `out`. Returns the IMFActivate array
// via `activates`/`count` when the caller needs to activate one (open);
// otherwise pass nullptr to just collect names/ids.
HRESULT EnumDevices(std::vector<DeviceEntry>* out, IMFActivate*** activates,
                    UINT32* count) {
  IMFAttributes* attrs = nullptr;
  HRESULT hr = MFCreateAttributes(&attrs, 1);
  if (FAILED(hr)) return hr;
  hr = attrs->SetGUID(MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE,
                      MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_GUID);
  if (FAILED(hr)) {
    SafeRelease(&attrs);
    return hr;
  }

  IMFActivate** devs = nullptr;
  UINT32 n = 0;
  hr = MFEnumDeviceSources(attrs, &devs, &n);
  SafeRelease(&attrs);
  if (FAILED(hr)) return hr;

  if (out) {
    out->clear();
    out->reserve(n);
    for (UINT32 i = 0; i < n; i++) {
      DeviceEntry e;
      wchar_t* str = nullptr;
      UINT32 strLen = 0;
      if (SUCCEEDED(devs[i]->GetAllocatedString(
              MF_DEVSOURCE_ATTRIBUTE_FRIENDLY_NAME, &str, &strLen))) {
        e.name = WideToUtf8(str);
        CoTaskMemFree(str);
      }
      str = nullptr;
      if (SUCCEEDED(devs[i]->GetAllocatedString(
              MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_SYMBOLIC_LINK, &str,
              &strLen))) {
        e.symlink = WideToUtf8(str);
        CoTaskMemFree(str);
      }
      out->push_back(std::move(e));
    }
  }

  if (activates && count) {
    *activates = devs;  // caller owns; must release each + CoTaskMemFree(devs)
    *count = n;
  } else {
    for (UINT32 i = 0; i < n; i++) SafeRelease(&devs[i]);
    CoTaskMemFree(devs);
  }
  return S_OK;
}

int32_t CopyUtf8(const std::string& s, char* buf, int32_t buf_len) {
  if (!buf || buf_len <= 0) return -1;
  int32_t n = static_cast<int32_t>(s.size());
  if (n > buf_len - 1) n = buf_len - 1;
  memcpy(buf, s.data(), static_cast<size_t>(n));
  buf[n] = '\0';
  return n;
}

}  // namespace

struct um_camera {
  IMFSourceReader* reader = nullptr;
  int32_t width = 0;
  int32_t height = 0;
  int32_t size = 0;
};

extern "C" {

int32_t um_camera_count(void) {
  EnsureMediaFoundation();
  if (!g_mf_ok) return 0;
  std::vector<DeviceEntry> devs;
  if (FAILED(EnumDevices(&devs, nullptr, nullptr))) return 0;
  std::lock_guard<std::mutex> lk(g_devices_mu);
  g_devices = std::move(devs);
  return static_cast<int32_t>(g_devices.size());
}

int32_t um_camera_name(int32_t index, char* buf, int32_t buf_len) {
  std::lock_guard<std::mutex> lk(g_devices_mu);
  if (index < 0 || index >= static_cast<int32_t>(g_devices.size())) return -1;
  return CopyUtf8(g_devices[index].name, buf, buf_len);
}

int32_t um_camera_id(int32_t index, char* buf, int32_t buf_len) {
  std::lock_guard<std::mutex> lk(g_devices_mu);
  if (index < 0 || index >= static_cast<int32_t>(g_devices.size())) return -1;
  return CopyUtf8(g_devices[index].symlink, buf, buf_len);
}

um_camera* um_camera_open(int32_t index, int32_t width, int32_t height) {
  EnsureMediaFoundation();
  if (!g_mf_ok) return nullptr;

  IMFActivate** devs = nullptr;
  UINT32 n = 0;
  if (FAILED(EnumDevices(nullptr, &devs, &n)) || index < 0 ||
      static_cast<UINT32>(index) >= n) {
    if (devs) {
      for (UINT32 i = 0; i < n; i++) SafeRelease(&devs[i]);
      CoTaskMemFree(devs);
    }
    return nullptr;
  }

  IMFMediaSource* source = nullptr;
  HRESULT hr = devs[index]->ActivateObject(IID_PPV_ARGS(&source));
  for (UINT32 i = 0; i < n; i++) SafeRelease(&devs[i]);
  CoTaskMemFree(devs);
  if (FAILED(hr)) return nullptr;

  // Enable the reader's video processor so it converts to RGB32 for us.
  IMFAttributes* ra = nullptr;
  MFCreateAttributes(&ra, 1);
  if (ra) ra->SetUINT32(MF_SOURCE_READER_ENABLE_VIDEO_PROCESSING, TRUE);

  IMFSourceReader* reader = nullptr;
  hr = MFCreateSourceReaderFromMediaSource(source, ra, &reader);
  SafeRelease(&ra);
  SafeRelease(&source);
  if (FAILED(hr)) return nullptr;

  IMFMediaType* want = nullptr;
  MFCreateMediaType(&want);
  want->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
  want->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_RGB32);
  if (width > 0 && height > 0) {
    MFSetAttributeSize(want, MF_MT_FRAME_SIZE, static_cast<UINT32>(width),
                       static_cast<UINT32>(height));
  }
  hr = reader->SetCurrentMediaType(
      static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM), nullptr, want);
  SafeRelease(&want);
  if (FAILED(hr)) {
    // Retry without a forced frame size.
    IMFMediaType* basic = nullptr;
    MFCreateMediaType(&basic);
    basic->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
    basic->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_RGB32);
    hr = reader->SetCurrentMediaType(
        static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM), nullptr,
        basic);
    SafeRelease(&basic);
    if (FAILED(hr)) {
      SafeRelease(&reader);
      return nullptr;
    }
  }

  IMFMediaType* actual = nullptr;
  UINT32 w = 0, h = 0;
  if (SUCCEEDED(reader->GetCurrentMediaType(
          static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM), &actual))) {
    MFGetAttributeSize(actual, MF_MT_FRAME_SIZE, &w, &h);
    SafeRelease(&actual);
  }
  if (w == 0 || h == 0) {
    SafeRelease(&reader);
    return nullptr;
  }

  auto* cam = new um_camera();
  cam->reader = reader;
  cam->width = static_cast<int32_t>(w);
  cam->height = static_cast<int32_t>(h);
  cam->size = static_cast<int32_t>(w * h * 4);
  return cam;
}

void um_camera_format(um_camera* cam, int32_t* width, int32_t* height,
                      int32_t* size) {
  if (!cam) return;
  if (width) *width = cam->width;
  if (height) *height = cam->height;
  if (size) *size = cam->size;
}

int32_t um_camera_read(um_camera* cam, uint8_t* dst, int32_t dst_len) {
  if (!cam || !cam->reader || !dst) return -1;

  // ReadSample can return without a sample (format change / stream tick);
  // loop until we get frame data or hit a terminal condition.
  for (int attempts = 0; attempts < 1000; attempts++) {
    DWORD streamFlags = 0;
    IMFSample* sample = nullptr;
    HRESULT hr = cam->reader->ReadSample(
        static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM), 0, nullptr,
        &streamFlags, nullptr, &sample);
    if (FAILED(hr)) {
      SafeRelease(&sample);
      return -1;
    }
    if (streamFlags & MF_SOURCE_READERF_ENDOFSTREAM) {
      SafeRelease(&sample);
      return 0;
    }
    if (!sample) continue;  // no data yet

    IMFMediaBuffer* buf = nullptr;
    hr = sample->ConvertToContiguousBuffer(&buf);
    if (FAILED(hr)) {
      SafeRelease(&sample);
      return -1;
    }
    BYTE* data = nullptr;
    DWORD maxLen = 0, curLen = 0;
    hr = buf->Lock(&data, &maxLen, &curLen);
    if (FAILED(hr)) {
      SafeRelease(&buf);
      SafeRelease(&sample);
      return -1;
    }
    int32_t n = static_cast<int32_t>(curLen);
    if (n > dst_len) n = dst_len;
    memcpy(dst, data, static_cast<size_t>(n));
    buf->Unlock();
    SafeRelease(&buf);
    SafeRelease(&sample);
    return n;
  }
  return -1;
}

void um_camera_close(um_camera* cam) {
  if (!cam) return;
  SafeRelease(&cam->reader);
  delete cam;
}

}  // extern "C"

#elif defined(__ANDROID__)  // --- Camera2 NDK -------------------------------
// NB: Android also defines __linux__, so this branch must precede the V4L2 one.
// Requires the host app to hold the CAMERA runtime permission before open.

#include <camera/NdkCameraDevice.h>
#include <camera/NdkCameraManager.h>
#include <camera/NdkCameraMetadata.h>
#include <media/NdkImage.h>
#include <media/NdkImageReader.h>
#include <unistd.h>

#include <mutex>
#include <string>
#include <vector>

namespace {

int clamp8(int v) { return v < 0 ? 0 : (v > 255 ? 255 : v); }

struct DeviceEntry {
  std::string id;
};

std::mutex g_devices_mu;
std::vector<DeviceEntry> g_devices;

void RefreshDevices() {
  std::vector<DeviceEntry> devs;
  ACameraManager* mgr = ACameraManager_create();
  if (mgr) {
    ACameraIdList* list = nullptr;
    if (ACameraManager_getCameraIdList(mgr, &list) == ACAMERA_OK && list) {
      for (int i = 0; i < list->numCameras; i++) {
        devs.push_back({list->cameraIds[i]});
      }
      ACameraManager_deleteCameraIdList(list);
    }
    ACameraManager_delete(mgr);
  }
  std::lock_guard<std::mutex> lk(g_devices_mu);
  g_devices = std::move(devs);
}

int32_t CopyUtf8(const std::string& s, char* buf, int32_t buf_len) {
  if (!buf || buf_len <= 0) return -1;
  int32_t n = static_cast<int32_t>(s.size());
  if (n > buf_len - 1) n = buf_len - 1;
  memcpy(buf, s.data(), static_cast<size_t>(n));
  buf[n] = '\0';
  return n;
}

void onDisconnected(void*, ACameraDevice*) {}
void onError(void*, ACameraDevice*, int) {}
void onSessionReady(void*, ACameraCaptureSession*) {}
void onSessionActive(void*, ACameraCaptureSession*) {}
void onSessionClosed(void*, ACameraCaptureSession*) {}

}  // namespace

struct um_camera {
  ACameraManager* mgr = nullptr;
  ACameraDevice* device = nullptr;
  AImageReader* reader = nullptr;
  ANativeWindow* window = nullptr;
  ACaptureSessionOutputContainer* outputs = nullptr;
  ACaptureSessionOutput* output = nullptr;
  ACameraOutputTarget* target = nullptr;
  ACaptureRequest* request = nullptr;
  ACameraCaptureSession* session = nullptr;
  int32_t width = 0;
  int32_t height = 0;
  int32_t size = 0;  // RGB32 output bytes
};

extern "C" {

int32_t um_camera_count(void) {
  RefreshDevices();
  std::lock_guard<std::mutex> lk(g_devices_mu);
  return static_cast<int32_t>(g_devices.size());
}

int32_t um_camera_name(int32_t index, char* buf, int32_t buf_len) {
  std::lock_guard<std::mutex> lk(g_devices_mu);
  if (index < 0 || index >= static_cast<int32_t>(g_devices.size())) return -1;
  return CopyUtf8(g_devices[index].id, buf, buf_len);
}

int32_t um_camera_id(int32_t index, char* buf, int32_t buf_len) {
  return um_camera_name(index, buf, buf_len);
}

um_camera* um_camera_open(int32_t index, int32_t width, int32_t height) {
  std::string id;
  {
    RefreshDevices();
    std::lock_guard<std::mutex> lk(g_devices_mu);
    if (index < 0 || index >= static_cast<int32_t>(g_devices.size())) {
      return nullptr;
    }
    id = g_devices[index].id;
  }
  const int w = width > 0 ? width : 640;
  const int h = height > 0 ? height : 480;

  auto* cam = new um_camera();
  cam->width = w;
  cam->height = h;
  cam->size = w * h * 4;
  cam->mgr = ACameraManager_create();
  if (!cam->mgr) {
    um_camera_close(cam);
    return nullptr;
  }

  if (AImageReader_new(w, h, AIMAGE_FORMAT_YUV_420_888, 2, &cam->reader) !=
          AMEDIA_OK ||
      AImageReader_getWindow(cam->reader, &cam->window) != AMEDIA_OK) {
    um_camera_close(cam);
    return nullptr;
  }
  ANativeWindow_acquire(cam->window);

  ACameraDevice_StateCallbacks devCb{nullptr, onDisconnected, onError};
  if (ACameraManager_openCamera(cam->mgr, id.c_str(), &devCb, &cam->device) !=
      ACAMERA_OK) {
    um_camera_close(cam);
    return nullptr;
  }

  if (ACaptureSessionOutputContainer_create(&cam->outputs) != ACAMERA_OK ||
      ACaptureSessionOutput_create(cam->window, &cam->output) != ACAMERA_OK ||
      ACaptureSessionOutputContainer_add(cam->outputs, cam->output) !=
          ACAMERA_OK ||
      ACameraDevice_createCaptureRequest(cam->device, TEMPLATE_PREVIEW,
                                         &cam->request) != ACAMERA_OK ||
      ACameraOutputTarget_create(cam->window, &cam->target) != ACAMERA_OK ||
      ACaptureRequest_addTarget(cam->request, cam->target) != ACAMERA_OK) {
    um_camera_close(cam);
    return nullptr;
  }

  ACameraCaptureSession_stateCallbacks sesCb{nullptr, onSessionClosed,
                                             onSessionReady, onSessionActive};
  if (ACameraDevice_createCaptureSession(cam->device, cam->outputs, &sesCb,
                                         &cam->session) != ACAMERA_OK ||
      ACameraCaptureSession_setRepeatingRequest(cam->session, nullptr, 1,
                                                &cam->request, nullptr) !=
          ACAMERA_OK) {
    um_camera_close(cam);
    return nullptr;
  }
  return cam;
}

void um_camera_format(um_camera* cam, int32_t* width, int32_t* height,
                      int32_t* size) {
  if (!cam) return;
  if (width) *width = cam->width;
  if (height) *height = cam->height;
  if (size) *size = cam->size;
}

int32_t um_camera_read(um_camera* cam, uint8_t* dst, int32_t dst_len) {
  if (!cam || !cam->reader || !dst) return -1;

  AImage* image = nullptr;
  for (int attempts = 0; attempts < 1000; attempts++) {
    media_status_t st = AImageReader_acquireLatestImage(cam->reader, &image);
    if (st == AMEDIA_OK && image) break;
    if (st == AMEDIA_IMGREADER_NO_BUFFER_AVAILABLE) {
      usleep(2000);
      continue;
    }
    return -1;
  }
  if (!image) return 0;

  int32_t yStride = 0, uvStride = 0, uvPixStride = 0, yLen = 0, uLen = 0,
          vLen = 0;
  uint8_t *yP = nullptr, *uP = nullptr, *vP = nullptr;
  AImage_getPlaneRowStride(image, 0, &yStride);
  AImage_getPlaneRowStride(image, 1, &uvStride);
  AImage_getPlanePixelStride(image, 1, &uvPixStride);
  AImage_getPlaneData(image, 0, &yP, &yLen);
  AImage_getPlaneData(image, 1, &uP, &uLen);
  AImage_getPlaneData(image, 2, &vP, &vLen);

  int32_t out = 0;
  for (int y = 0; y < cam->height; y++) {
    const uint8_t* yr = yP + y * yStride;
    const uint8_t* ur = uP + (y / 2) * uvStride;
    const uint8_t* vr = vP + (y / 2) * uvStride;
    for (int x = 0; x < cam->width; x++) {
      if (out + 4 > dst_len) break;
      const int Y = yr[x];
      const int U = ur[(x / 2) * uvPixStride] - 128;
      const int V = vr[(x / 2) * uvPixStride] - 128;
      dst[out + 0] = clamp8(Y + ((443 * U) >> 8));                 // B
      dst[out + 1] = clamp8(Y - ((179 * V + 86 * U) >> 8));        // G
      dst[out + 2] = clamp8(Y + ((351 * V) >> 8));                 // R
      dst[out + 3] = 255;                                          // X
      out += 4;
    }
  }
  AImage_delete(image);
  return out;
}

void um_camera_close(um_camera* cam) {
  if (!cam) return;
  if (cam->session) {
    ACameraCaptureSession_stopRepeating(cam->session);
    ACameraCaptureSession_close(cam->session);
  }
  if (cam->request) ACaptureRequest_free(cam->request);
  if (cam->target) ACameraOutputTarget_free(cam->target);
  if (cam->output) ACaptureSessionOutput_free(cam->output);
  if (cam->outputs) ACaptureSessionOutputContainer_free(cam->outputs);
  if (cam->device) ACameraDevice_close(cam->device);
  if (cam->window) ANativeWindow_release(cam->window);
  if (cam->reader) AImageReader_delete(cam->reader);
  if (cam->mgr) ACameraManager_delete(cam->mgr);
  delete cam;
}

}  // extern "C"

#elif defined(__linux__)  // --- V4L2 capture ---------------------------------

#include <fcntl.h>
#include <linux/videodev2.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>

#include <cerrno>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

namespace {

int xioctl(int fd, unsigned long req, void* arg) {
  int r;
  do {
    r = ioctl(fd, req, arg);
  } while (r == -1 && errno == EINTR);
  return r;
}

int clamp8(int v) { return v < 0 ? 0 : (v > 255 ? 255 : v); }

struct DeviceEntry {
  std::string name;
  std::string path;
};

std::mutex g_devices_mu;
std::vector<DeviceEntry> g_devices;

void RefreshDevices() {
  std::vector<DeviceEntry> devs;
  for (int i = 0; i < 64; i++) {
    std::string path = "/dev/video" + std::to_string(i);
    int fd = open(path.c_str(), O_RDWR | O_NONBLOCK);
    if (fd < 0) continue;
    v4l2_capability cap{};
    if (xioctl(fd, VIDIOC_QUERYCAP, &cap) == 0 &&
        (cap.capabilities & V4L2_CAP_VIDEO_CAPTURE)) {
      DeviceEntry e;
      e.name = reinterpret_cast<const char*>(cap.card);
      e.path = path;
      devs.push_back(std::move(e));
    }
    close(fd);
  }
  std::lock_guard<std::mutex> lk(g_devices_mu);
  g_devices = std::move(devs);
}

int32_t CopyUtf8(const std::string& s, char* buf, int32_t buf_len) {
  if (!buf || buf_len <= 0) return -1;
  int32_t n = static_cast<int32_t>(s.size());
  if (n > buf_len - 1) n = buf_len - 1;
  memcpy(buf, s.data(), static_cast<size_t>(n));
  buf[n] = '\0';
  return n;
}

}  // namespace

struct um_camera {
  int fd = -1;
  struct Buf {
    void* start = nullptr;
    size_t length = 0;
  };
  std::vector<Buf> buffers;
  int32_t width = 0;
  int32_t height = 0;
  int32_t size = 0;  // RGB32 output bytes = width*height*4
};

extern "C" {

int32_t um_camera_count(void) {
  RefreshDevices();
  std::lock_guard<std::mutex> lk(g_devices_mu);
  return static_cast<int32_t>(g_devices.size());
}

int32_t um_camera_name(int32_t index, char* buf, int32_t buf_len) {
  std::lock_guard<std::mutex> lk(g_devices_mu);
  if (index < 0 || index >= static_cast<int32_t>(g_devices.size())) return -1;
  return CopyUtf8(g_devices[index].name, buf, buf_len);
}

int32_t um_camera_id(int32_t index, char* buf, int32_t buf_len) {
  std::lock_guard<std::mutex> lk(g_devices_mu);
  if (index < 0 || index >= static_cast<int32_t>(g_devices.size())) return -1;
  return CopyUtf8(g_devices[index].path, buf, buf_len);
}

um_camera* um_camera_open(int32_t index, int32_t width, int32_t height) {
  std::string path;
  {
    RefreshDevices();
    std::lock_guard<std::mutex> lk(g_devices_mu);
    if (index < 0 || index >= static_cast<int32_t>(g_devices.size())) {
      return nullptr;
    }
    path = g_devices[index].path;
  }

  int fd = open(path.c_str(), O_RDWR);
  if (fd < 0) return nullptr;

  v4l2_format fmt{};
  fmt.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
  fmt.fmt.pix.width = width > 0 ? width : 640;
  fmt.fmt.pix.height = height > 0 ? height : 480;
  fmt.fmt.pix.pixelformat = V4L2_PIX_FMT_YUYV;
  fmt.fmt.pix.field = V4L2_FIELD_ANY;
  if (xioctl(fd, VIDIOC_S_FMT, &fmt) == -1 ||
      fmt.fmt.pix.pixelformat != V4L2_PIX_FMT_YUYV) {
    close(fd);
    return nullptr;
  }

  v4l2_requestbuffers req{};
  req.count = 4;
  req.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
  req.memory = V4L2_MEMORY_MMAP;
  if (xioctl(fd, VIDIOC_REQBUFS, &req) == -1 || req.count < 2) {
    close(fd);
    return nullptr;
  }

  auto* cam = new um_camera();
  cam->fd = fd;
  cam->width = static_cast<int32_t>(fmt.fmt.pix.width);
  cam->height = static_cast<int32_t>(fmt.fmt.pix.height);
  cam->size = cam->width * cam->height * 4;

  for (unsigned i = 0; i < req.count; i++) {
    v4l2_buffer b{};
    b.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    b.memory = V4L2_MEMORY_MMAP;
    b.index = i;
    if (xioctl(fd, VIDIOC_QUERYBUF, &b) == -1) {
      um_camera_close(cam);
      return nullptr;
    }
    void* p = mmap(nullptr, b.length, PROT_READ | PROT_WRITE, MAP_SHARED, fd,
                   b.m.offset);
    if (p == MAP_FAILED) {
      um_camera_close(cam);
      return nullptr;
    }
    cam->buffers.push_back({p, b.length});
    if (xioctl(fd, VIDIOC_QBUF, &b) == -1) {
      um_camera_close(cam);
      return nullptr;
    }
  }

  v4l2_buf_type type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
  if (xioctl(fd, VIDIOC_STREAMON, &type) == -1) {
    um_camera_close(cam);
    return nullptr;
  }
  return cam;
}

void um_camera_format(um_camera* cam, int32_t* width, int32_t* height,
                      int32_t* size) {
  if (!cam) return;
  if (width) *width = cam->width;
  if (height) *height = cam->height;
  if (size) *size = cam->size;
}

int32_t um_camera_read(um_camera* cam, uint8_t* dst, int32_t dst_len) {
  if (!cam || cam->fd < 0 || !dst) return -1;

  v4l2_buffer b{};
  b.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
  b.memory = V4L2_MEMORY_MMAP;
  // Block until a frame is dequeued.
  for (int attempts = 0; attempts < 1000; attempts++) {
    if (xioctl(cam->fd, VIDIOC_DQBUF, &b) == 0) break;
    if (errno == EAGAIN) {
      usleep(2000);
      continue;
    }
    return -1;
  }
  if (b.index >= cam->buffers.size()) return -1;

  // Convert YUYV (Y0 U Y1 V) to RGB32 / BGRX (B,G,R,X), matching Windows.
  const uint8_t* yuyv = static_cast<const uint8_t*>(cam->buffers[b.index].start);
  const int pixels = cam->width * cam->height;
  int32_t out = 0;
  for (int i = 0; i < pixels; i += 2) {
    const int y0 = yuyv[0], u = yuyv[1], y1 = yuyv[2], v = yuyv[3];
    yuyv += 4;
    const int cu = u - 128, cv = v - 128;
    for (const int yv : {y0, y1}) {
      if (out + 4 > dst_len) break;
      dst[out + 0] = clamp8(yv + ((443 * cu) >> 8));                 // B
      dst[out + 1] = clamp8(yv - ((179 * cv + 86 * cu) >> 8));       // G
      dst[out + 2] = clamp8(yv + ((351 * cv) >> 8));                 // R
      dst[out + 3] = 255;                                            // X
      out += 4;
    }
  }

  xioctl(cam->fd, VIDIOC_QBUF, &b);  // requeue
  return out;
}

void um_camera_close(um_camera* cam) {
  if (!cam) return;
  if (cam->fd >= 0) {
    v4l2_buf_type type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    xioctl(cam->fd, VIDIOC_STREAMOFF, &type);
  }
  for (auto& b : cam->buffers) {
    if (b.start) munmap(b.start, b.length);
  }
  if (cam->fd >= 0) close(cam->fd);
  delete cam;
}

}  // extern "C"

#else  // --- other platforms stub ---------------------------------------------

struct um_camera {};

extern "C" {
int32_t um_camera_count(void) { return 0; }
int32_t um_camera_name(int32_t, char*, int32_t) { return -1; }
int32_t um_camera_id(int32_t, char*, int32_t) { return -1; }
um_camera* um_camera_open(int32_t, int32_t, int32_t) { return nullptr; }
void um_camera_format(um_camera*, int32_t* w, int32_t* h, int32_t* s) {
  if (w) *w = 0;
  if (h) *h = 0;
  if (s) *s = 0;
}
int32_t um_camera_read(um_camera*, uint8_t*, int32_t) { return -1; }
void um_camera_close(um_camera*) {}
}  // extern "C"

#endif
