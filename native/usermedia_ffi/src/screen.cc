// screen.cc — platform display capture for the usermedia_ffi shim (Phase E).
//
// Windows: DXGI Desktop Duplication. A D3D11 device duplicates an output; each
// um_screen_read acquires the next desktop frame, copies it into a CPU-readable
// staging texture, and returns BGRA bytes. Pull model, caller's thread, no
// callbacks. Other platforms: a no-op stub.

#include "usermedia_ffi.h"

#if defined(_WIN32)

#include <d3d11.h>
#include <dxgi1_2.h>
#include <windows.h>

#include <mutex>
#include <string>
#include <vector>

#pragma comment(lib, "d3d11.lib")
#pragma comment(lib, "dxgi.lib")

namespace {

template <class T>
void SafeRelease(T** pp) {
  if (*pp) {
    (*pp)->Release();
    *pp = nullptr;
  }
}

std::string WideToUtf8(const wchar_t* w) {
  if (!w) return std::string();
  int len = WideCharToMultiByte(CP_UTF8, 0, w, -1, nullptr, 0, nullptr, nullptr);
  if (len <= 0) return std::string();
  std::string out(static_cast<size_t>(len - 1), '\0');
  WideCharToMultiByte(CP_UTF8, 0, w, -1, out.data(), len, nullptr, nullptr);
  return out;
}

struct ScreenEntry {
  std::string name;
  UINT adapter = 0;
  UINT output = 0;
};

std::mutex g_screens_mu;
std::vector<ScreenEntry> g_screens;

void RefreshScreens() {
  std::vector<ScreenEntry> screens;
  IDXGIFactory1* factory = nullptr;
  if (SUCCEEDED(CreateDXGIFactory1(__uuidof(IDXGIFactory1),
                                   reinterpret_cast<void**>(&factory)))) {
    for (UINT a = 0;; a++) {
      IDXGIAdapter1* adapter = nullptr;
      if (factory->EnumAdapters1(a, &adapter) == DXGI_ERROR_NOT_FOUND) break;
      for (UINT o = 0;; o++) {
        IDXGIOutput* output = nullptr;
        if (adapter->EnumOutputs(o, &output) == DXGI_ERROR_NOT_FOUND) break;
        DXGI_OUTPUT_DESC desc{};
        if (SUCCEEDED(output->GetDesc(&desc))) {
          ScreenEntry e;
          e.name = WideToUtf8(desc.DeviceName);
          e.adapter = a;
          e.output = o;
          screens.push_back(std::move(e));
        }
        SafeRelease(&output);
      }
      SafeRelease(&adapter);
    }
    SafeRelease(&factory);
  }
  std::lock_guard<std::mutex> lk(g_screens_mu);
  g_screens = std::move(screens);
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

struct um_screen {
  ID3D11Device* device = nullptr;
  ID3D11DeviceContext* context = nullptr;
  IDXGIOutputDuplication* dupl = nullptr;
  ID3D11Texture2D* staging = nullptr;
  int32_t width = 0;
  int32_t height = 0;
  int32_t size = 0;
  bool haveFrame = false;
};

extern "C" {

int32_t um_screen_count(void) {
  RefreshScreens();
  std::lock_guard<std::mutex> lk(g_screens_mu);
  return static_cast<int32_t>(g_screens.size());
}

int32_t um_screen_name(int32_t index, char* buf, int32_t buf_len) {
  std::lock_guard<std::mutex> lk(g_screens_mu);
  if (index < 0 || index >= static_cast<int32_t>(g_screens.size())) return -1;
  return CopyUtf8(g_screens[index].name, buf, buf_len);
}

int32_t um_screen_id(int32_t index, char* buf, int32_t buf_len) {
  // Output device name doubles as a stable id.
  return um_screen_name(index, buf, buf_len);
}

um_screen* um_screen_open(int32_t index, int32_t /*width*/,
                          int32_t /*height*/) {
  RefreshScreens();
  UINT adapterIdx = 0, outputIdx = 0;
  {
    std::lock_guard<std::mutex> lk(g_screens_mu);
    if (index < 0 || index >= static_cast<int32_t>(g_screens.size())) {
      return nullptr;
    }
    adapterIdx = g_screens[index].adapter;
    outputIdx = g_screens[index].output;
  }

  IDXGIFactory1* factory = nullptr;
  if (FAILED(CreateDXGIFactory1(__uuidof(IDXGIFactory1),
                                reinterpret_cast<void**>(&factory)))) {
    return nullptr;
  }
  IDXGIAdapter1* adapter = nullptr;
  if (factory->EnumAdapters1(adapterIdx, &adapter) != S_OK) {
    SafeRelease(&factory);
    return nullptr;
  }

  ID3D11Device* device = nullptr;
  ID3D11DeviceContext* context = nullptr;
  D3D_FEATURE_LEVEL level{};
  HRESULT hr = D3D11CreateDevice(adapter, D3D_DRIVER_TYPE_UNKNOWN, nullptr, 0,
                                 nullptr, 0, D3D11_SDK_VERSION, &device, &level,
                                 &context);
  if (FAILED(hr)) {
    SafeRelease(&adapter);
    SafeRelease(&factory);
    return nullptr;
  }

  IDXGIOutput* output = nullptr;
  IDXGIOutput1* output1 = nullptr;
  IDXGIOutputDuplication* dupl = nullptr;
  if (SUCCEEDED(adapter->EnumOutputs(outputIdx, &output)) &&
      SUCCEEDED(output->QueryInterface(__uuidof(IDXGIOutput1),
                                       reinterpret_cast<void**>(&output1)))) {
    hr = output1->DuplicateOutput(device, &dupl);
  } else {
    hr = E_FAIL;
  }
  SafeRelease(&output1);
  SafeRelease(&output);
  SafeRelease(&adapter);
  SafeRelease(&factory);
  if (FAILED(hr) || !dupl) {
    SafeRelease(&context);
    SafeRelease(&device);
    return nullptr;
  }

  DXGI_OUTDUPL_DESC dd{};
  dupl->GetDesc(&dd);
  const UINT w = dd.ModeDesc.Width;
  const UINT h = dd.ModeDesc.Height;

  D3D11_TEXTURE2D_DESC td{};
  td.Width = w;
  td.Height = h;
  td.MipLevels = 1;
  td.ArraySize = 1;
  td.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
  td.SampleDesc.Count = 1;
  td.Usage = D3D11_USAGE_STAGING;
  td.BindFlags = 0;
  td.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
  td.MiscFlags = 0;

  ID3D11Texture2D* staging = nullptr;
  if (FAILED(device->CreateTexture2D(&td, nullptr, &staging))) {
    SafeRelease(&dupl);
    SafeRelease(&context);
    SafeRelease(&device);
    return nullptr;
  }

  auto* scr = new um_screen();
  scr->device = device;
  scr->context = context;
  scr->dupl = dupl;
  scr->staging = staging;
  scr->width = static_cast<int32_t>(w);
  scr->height = static_cast<int32_t>(h);
  scr->size = static_cast<int32_t>(w * h * 4);
  return scr;
}

void um_screen_format(um_screen* scr, int32_t* width, int32_t* height,
                      int32_t* size) {
  if (!scr) return;
  if (width) *width = scr->width;
  if (height) *height = scr->height;
  if (size) *size = scr->size;
}

int32_t um_screen_read(um_screen* scr, uint8_t* dst, int32_t dst_len) {
  if (!scr || !scr->dupl || !dst) return -1;

  // Acquire a fresh frame; on a static desktop AcquireNextFrame may time out,
  // in which case we reuse the last copied frame once we have one.
  bool copied = false;
  for (int attempts = 0; attempts < 60; attempts++) {
    IDXGIResource* res = nullptr;
    DXGI_OUTDUPL_FRAME_INFO info{};
    HRESULT hr = scr->dupl->AcquireNextFrame(100, &info, &res);
    if (hr == DXGI_ERROR_WAIT_TIMEOUT) {
      if (scr->haveFrame) break;  // reuse previous staging contents
      continue;
    }
    if (FAILED(hr)) return -1;

    ID3D11Texture2D* tex = nullptr;
    if (SUCCEEDED(res->QueryInterface(__uuidof(ID3D11Texture2D),
                                      reinterpret_cast<void**>(&tex)))) {
      scr->context->CopyResource(scr->staging, tex);
      scr->haveFrame = true;
      copied = true;
    }
    SafeRelease(&tex);
    SafeRelease(&res);
    scr->dupl->ReleaseFrame();
    if (copied) break;
  }

  if (!scr->haveFrame) return 0;

  D3D11_MAPPED_SUBRESOURCE map{};
  if (FAILED(scr->context->Map(scr->staging, 0, D3D11_MAP_READ, 0, &map))) {
    return -1;
  }
  const int32_t rowBytes = scr->width * 4;
  int32_t written = 0;
  for (int32_t y = 0; y < scr->height; y++) {
    if (written + rowBytes > dst_len) break;
    memcpy(dst + written,
           static_cast<const uint8_t*>(map.pData) + y * map.RowPitch,
           static_cast<size_t>(rowBytes));
    written += rowBytes;
  }
  scr->context->Unmap(scr->staging, 0);
  return written;
}

void um_screen_close(um_screen* scr) {
  if (!scr) return;
  SafeRelease(&scr->staging);
  SafeRelease(&scr->dupl);
  SafeRelease(&scr->context);
  SafeRelease(&scr->device);
  delete scr;
}

}  // extern "C"

#elif defined(__linux__)  // --- X11 capture -----------------------------------

#include <X11/Xlib.h>
#include <X11/Xutil.h>

#include <cstring>
#include <mutex>
#include <string>
#include <vector>

namespace {

struct ScreenEntry {
  std::string name;
  int number;
};

std::mutex g_screens_mu;
std::vector<ScreenEntry> g_screens;

void RefreshScreens() {
  std::vector<ScreenEntry> screens;
  Display* dpy = XOpenDisplay(nullptr);
  if (dpy) {
    const int n = ScreenCount(dpy);
    for (int i = 0; i < n; i++) {
      screens.push_back({":screen" + std::to_string(i), i});
    }
    XCloseDisplay(dpy);
  }
  std::lock_guard<std::mutex> lk(g_screens_mu);
  g_screens = std::move(screens);
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

struct um_screen {
  Display* dpy = nullptr;
  Window root = 0;
  int32_t width = 0;
  int32_t height = 0;
  int32_t size = 0;  // BGRA bytes = width*height*4
};

extern "C" {

int32_t um_screen_count(void) {
  RefreshScreens();
  std::lock_guard<std::mutex> lk(g_screens_mu);
  return static_cast<int32_t>(g_screens.size());
}

int32_t um_screen_name(int32_t index, char* buf, int32_t buf_len) {
  std::lock_guard<std::mutex> lk(g_screens_mu);
  if (index < 0 || index >= static_cast<int32_t>(g_screens.size())) return -1;
  return CopyUtf8(g_screens[index].name, buf, buf_len);
}

int32_t um_screen_id(int32_t index, char* buf, int32_t buf_len) {
  return um_screen_name(index, buf, buf_len);
}

um_screen* um_screen_open(int32_t index, int32_t /*width*/, int32_t /*height*/) {
  int number = 0;
  {
    RefreshScreens();
    std::lock_guard<std::mutex> lk(g_screens_mu);
    if (index < 0 || index >= static_cast<int32_t>(g_screens.size())) {
      return nullptr;
    }
    number = g_screens[index].number;
  }

  Display* dpy = XOpenDisplay(nullptr);
  if (!dpy) return nullptr;
  Screen* scr = ScreenOfDisplay(dpy, number);
  if (!scr) {
    XCloseDisplay(dpy);
    return nullptr;
  }

  auto* s = new um_screen();
  s->dpy = dpy;
  s->root = RootWindowOfScreen(scr);
  s->width = WidthOfScreen(scr);
  s->height = HeightOfScreen(scr);
  s->size = s->width * s->height * 4;
  return s;
}

void um_screen_format(um_screen* scr, int32_t* width, int32_t* height,
                      int32_t* size) {
  if (!scr) return;
  if (width) *width = scr->width;
  if (height) *height = scr->height;
  if (size) *size = scr->size;
}

int32_t um_screen_read(um_screen* scr, uint8_t* dst, int32_t dst_len) {
  if (!scr || !scr->dpy || !dst) return -1;
  XImage* img = XGetImage(scr->dpy, scr->root, 0, 0, scr->width, scr->height,
                          AllPlanes, ZPixmap);
  if (!img) return -1;

  int32_t out = 0;
  for (int y = 0; y < scr->height; y++) {
    for (int x = 0; x < scr->width; x++) {
      if (out + 4 > dst_len) {
        XDestroyImage(img);
        return out;
      }
      const unsigned long px = XGetPixel(img, x, y);
      dst[out + 0] = (px & img->blue_mask) >> 0;    // B (typical 24/32-bit)
      dst[out + 1] = (px & img->green_mask) >> 8;   // G
      dst[out + 2] = (px & img->red_mask) >> 16;    // R
      dst[out + 3] = 255;                            // A
      out += 4;
    }
  }
  XDestroyImage(img);
  return out;
}

void um_screen_close(um_screen* scr) {
  if (!scr) return;
  if (scr->dpy) XCloseDisplay(scr->dpy);
  delete scr;
}

}  // extern "C"

#else  // --- other platforms stub ---------------------------------------------

struct um_screen {};

extern "C" {
int32_t um_screen_count(void) { return 0; }
int32_t um_screen_name(int32_t, char*, int32_t) { return -1; }
int32_t um_screen_id(int32_t, char*, int32_t) { return -1; }
um_screen* um_screen_open(int32_t, int32_t, int32_t) { return nullptr; }
void um_screen_format(um_screen*, int32_t* w, int32_t* h, int32_t* s) {
  if (w) *w = 0;
  if (h) *h = 0;
  if (s) *s = 0;
}
int32_t um_screen_read(um_screen*, uint8_t*, int32_t) { return -1; }
void um_screen_close(um_screen*) {}
}  // extern "C"

#endif
