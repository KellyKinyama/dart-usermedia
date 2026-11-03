// encoder.cc — H.264 encoding for the usermedia_ffi shim.
//
// Windows: the Media Foundation H.264 encoder MFT. Input BGRA/BGRX frames are
// converted to NV12, fed to the transform, and the emitted Annex-B H.264 is
// returned. Synchronous, caller's thread. Other platforms: a no-op stub.

#include "usermedia_ffi.h"

#if defined(_WIN32)

#include <codecapi.h>
#include <mfapi.h>
#include <mferror.h>
#include <mfidl.h>
#include <mftransform.h>
#include <windows.h>
#include <wmcodecdsp.h>

#include <mutex>
#include <vector>

#pragma comment(lib, "mfplat.lib")
#pragma comment(lib, "mfuuid.lib")
#pragma comment(lib, "wmcodecdspuuid.lib")
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
    HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    if (hr == RPC_E_CHANGED_MODE) hr = S_OK;
    g_mf_ok = SUCCEEDED(MFStartup(MF_VERSION, MFSTARTUP_LITE));
  });
}

inline uint8_t Clamp8(int v) {
  return static_cast<uint8_t>(v < 0 ? 0 : (v > 255 ? 255 : v));
}

// Converts a BGRA/BGRX frame to NV12 (BT.601 studio swing).
void BgraToNv12(const uint8_t* src, int w, int h, uint8_t* nv12) {
  uint8_t* y = nv12;
  uint8_t* uv = nv12 + w * h;
  for (int j = 0; j < h; j++) {
    for (int i = 0; i < w; i++) {
      const uint8_t* p = src + (j * w + i) * 4;
      int b = p[0], g = p[1], r = p[2];
      y[j * w + i] = Clamp8(((66 * r + 129 * g + 25 * b + 128) >> 8) + 16);
    }
  }
  for (int j = 0; j < h; j += 2) {
    for (int i = 0; i < w; i += 2) {
      const uint8_t* p = src + (j * w + i) * 4;
      int b = p[0], g = p[1], r = p[2];
      int u = ((-38 * r - 74 * g + 112 * b + 128) >> 8) + 128;
      int v = ((112 * r - 94 * g - 18 * b + 128) >> 8) + 128;
      uint8_t* dst = uv + (j / 2) * w + (i / 2) * 2;
      dst[0] = Clamp8(u);
      dst[1] = Clamp8(v);
    }
  }
}

}  // namespace

struct um_h264 {
  IMFTransform* mft = nullptr;
  int width = 0;
  int height = 0;
  int fps = 30;
  DWORD outSize = 0;
  bool providesSamples = false;
  int64_t frameIndex = 0;
  std::vector<uint8_t> nv12;
};

namespace {

// Drains all currently-available encoded output into `dst` (bounded by
// dst_len). Returns bytes written, or -1 on error.
int32_t DrainOutput(um_h264* enc, uint8_t* dst, int32_t dst_len) {
  int32_t written = 0;
  for (;;) {
    IMFSample* outSample = nullptr;
    IMFMediaBuffer* outBuffer = nullptr;
    if (!enc->providesSamples) {
      if (FAILED(MFCreateSample(&outSample))) return -1;
      if (FAILED(MFCreateMemoryBuffer(enc->outSize, &outBuffer))) {
        SafeRelease(&outSample);
        return -1;
      }
      outSample->AddBuffer(outBuffer);
    }

    MFT_OUTPUT_DATA_BUFFER out{};
    out.dwStreamID = 0;
    out.pSample = outSample;
    DWORD status = 0;
    HRESULT hr = enc->mft->ProcessOutput(0, 1, &out, &status);

    if (hr == MF_E_TRANSFORM_NEED_MORE_INPUT) {
      SafeRelease(&outBuffer);
      SafeRelease(&outSample);
      break;
    }
    if (FAILED(hr)) {
      SafeRelease(&outBuffer);
      SafeRelease(&outSample);
      return -1;
    }

    IMFSample* produced = out.pSample;  // same as outSample unless MFT-provided
    IMFMediaBuffer* contig = nullptr;
    if (produced && SUCCEEDED(produced->ConvertToContiguousBuffer(&contig))) {
      BYTE* data = nullptr;
      DWORD len = 0;
      if (SUCCEEDED(contig->Lock(&data, nullptr, &len))) {
        int32_t n = static_cast<int32_t>(len);
        if (written + n > dst_len) n = dst_len - written;
        if (n > 0) {
          memcpy(dst + written, data, static_cast<size_t>(n));
          written += n;
        }
        contig->Unlock();
      }
      SafeRelease(&contig);
    }
    if (enc->providesSamples) SafeRelease(&produced);
    SafeRelease(&outBuffer);
    SafeRelease(&outSample);
    if (written >= dst_len) break;
  }
  return written;
}

}  // namespace

extern "C" {

um_h264* um_h264_create(int32_t width, int32_t height, int32_t fps,
                        int32_t bitrate) {
  EnsureMediaFoundation();
  if (!g_mf_ok || width <= 0 || height <= 0) return nullptr;
  if (fps <= 0) fps = 30;
  if (bitrate <= 0) bitrate = 2000000;

  IMFTransform* mft = nullptr;
  HRESULT hr = CoCreateInstance(CLSID_CMSH264EncoderMFT, nullptr, CLSCTX_INPROC_SERVER,
                                IID_PPV_ARGS(&mft));
  if (FAILED(hr) || !mft) return nullptr;

  // Output type (H.264) must be set before the input type.
  IMFMediaType* outType = nullptr;
  MFCreateMediaType(&outType);
  outType->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
  outType->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_H264);
  outType->SetUINT32(MF_MT_AVG_BITRATE, static_cast<UINT32>(bitrate));
  MFSetAttributeSize(outType, MF_MT_FRAME_SIZE, static_cast<UINT32>(width),
                     static_cast<UINT32>(height));
  MFSetAttributeRatio(outType, MF_MT_FRAME_RATE, static_cast<UINT32>(fps), 1);
  MFSetAttributeRatio(outType, MF_MT_PIXEL_ASPECT_RATIO, 1, 1);
  outType->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive);
  outType->SetUINT32(MF_MT_MPEG2_PROFILE, eAVEncH264VProfile_Base);
  hr = mft->SetOutputType(0, outType, 0);
  SafeRelease(&outType);
  if (FAILED(hr)) {
    SafeRelease(&mft);
    return nullptr;
  }

  IMFMediaType* inType = nullptr;
  MFCreateMediaType(&inType);
  inType->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
  inType->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_NV12);
  MFSetAttributeSize(inType, MF_MT_FRAME_SIZE, static_cast<UINT32>(width),
                     static_cast<UINT32>(height));
  MFSetAttributeRatio(inType, MF_MT_FRAME_RATE, static_cast<UINT32>(fps), 1);
  MFSetAttributeRatio(inType, MF_MT_PIXEL_ASPECT_RATIO, 1, 1);
  inType->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive);
  hr = mft->SetInputType(0, inType, 0);
  SafeRelease(&inType);
  if (FAILED(hr)) {
    SafeRelease(&mft);
    return nullptr;
  }

  MFT_OUTPUT_STREAM_INFO si{};
  mft->GetOutputStreamInfo(0, &si);

  mft->ProcessMessage(MFT_MESSAGE_NOTIFY_BEGIN_STREAMING, 0);
  mft->ProcessMessage(MFT_MESSAGE_NOTIFY_START_OF_STREAM, 0);

  auto* enc = new um_h264();
  enc->mft = mft;
  enc->width = width;
  enc->height = height;
  enc->fps = fps;
  enc->outSize = si.cbSize ? si.cbSize : static_cast<DWORD>(width * height * 4);
  enc->providesSamples =
      (si.dwFlags & MFT_OUTPUT_STREAM_PROVIDES_SAMPLES) != 0;
  enc->nv12.resize(static_cast<size_t>(width) * height * 3 / 2);
  return enc;
}

int32_t um_h264_encode(um_h264* enc, const uint8_t* bgra, int32_t bgra_len,
                       uint8_t* dst, int32_t dst_len) {
  if (!enc || !enc->mft || !bgra || !dst) return -1;
  if (bgra_len < enc->width * enc->height * 4) return -1;

  BgraToNv12(bgra, enc->width, enc->height, enc->nv12.data());

  IMFSample* sample = nullptr;
  IMFMediaBuffer* buffer = nullptr;
  if (FAILED(MFCreateSample(&sample)) ||
      FAILED(MFCreateMemoryBuffer(static_cast<DWORD>(enc->nv12.size()),
                                  &buffer))) {
    SafeRelease(&buffer);
    SafeRelease(&sample);
    return -1;
  }
  BYTE* dstBuf = nullptr;
  buffer->Lock(&dstBuf, nullptr, nullptr);
  memcpy(dstBuf, enc->nv12.data(), enc->nv12.size());
  buffer->Unlock();
  buffer->SetCurrentLength(static_cast<DWORD>(enc->nv12.size()));
  sample->AddBuffer(buffer);

  const LONGLONG dur = 10000000LL / enc->fps;
  sample->SetSampleTime(enc->frameIndex * dur);
  sample->SetSampleDuration(dur);
  enc->frameIndex++;

  HRESULT hr = enc->mft->ProcessInput(0, sample, 0);
  SafeRelease(&buffer);
  SafeRelease(&sample);
  if (FAILED(hr)) return -1;

  return DrainOutput(enc, dst, dst_len);
}

int32_t um_h264_flush(um_h264* enc, uint8_t* dst, int32_t dst_len) {
  if (!enc || !enc->mft || !dst) return -1;
  // Signal drain once; subsequent calls just drain remaining output.
  enc->mft->ProcessMessage(MFT_MESSAGE_COMMAND_DRAIN, 0);
  return DrainOutput(enc, dst, dst_len);
}

void um_h264_close(um_h264* enc) {
  if (!enc) return;
  if (enc->mft) {
    enc->mft->ProcessMessage(MFT_MESSAGE_NOTIFY_END_OF_STREAM, 0);
    enc->mft->ProcessMessage(MFT_MESSAGE_NOTIFY_END_STREAMING, 0);
  }
  SafeRelease(&enc->mft);
  delete enc;
}

}  // extern "C"

#else  // --- non-Windows stub -------------------------------------------------

struct um_h264 {};

extern "C" {
um_h264* um_h264_create(int32_t, int32_t, int32_t, int32_t) { return nullptr; }
int32_t um_h264_encode(um_h264*, const uint8_t*, int32_t, uint8_t*, int32_t) {
  return -1;
}
int32_t um_h264_flush(um_h264*, uint8_t*, int32_t) { return -1; }
void um_h264_close(um_h264*) {}
}  // extern "C"

#endif
