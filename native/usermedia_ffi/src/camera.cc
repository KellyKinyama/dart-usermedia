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

#else  // --- non-Windows stub -------------------------------------------------

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
