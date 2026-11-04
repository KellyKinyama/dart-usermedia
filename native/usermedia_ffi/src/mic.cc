// mic.cc — platform audio capture for the usermedia_ffi shim (Phase D).
//
// Windows: WASAPI shared-mode capture. We request interleaved 16-bit PCM at the
// caller's sample rate/channels and let WASAPI's AUTOCONVERTPCM path resample
// from the endpoint mix format. um_mic_read polls IAudioCaptureClient on the
// caller's thread (no callbacks / background threads). Other platforms: stub.

#include "usermedia_ffi.h"

#if defined(_WIN32)

#include <audioclient.h>
#include <mmdeviceapi.h>
#include <propkeydef.h>
#include <windows.h>

#include <mutex>
#include <string>
#include <vector>

#pragma comment(lib, "ole32.lib")

namespace {

// Endpoint friendly-name property key (from functiondiscoverykeys_devpkey.h),
// defined locally to avoid the INITGUID/DEFINE_PROPERTYKEY redefinition clash.
const PROPERTYKEY kDeviceFriendlyName = {
    {0xa45c254e, 0xdf1c, 0x4efd,
     {0x80, 0x20, 0x67, 0xd1, 0x46, 0xa8, 0x50, 0xe0}},
    14};

template <class T>
void SafeRelease(T** pp) {
  if (*pp) {
    (*pp)->Release();
    *pp = nullptr;
  }
}

std::once_flag g_com_once;

void EnsureCom() {
  std::call_once(g_com_once, [] {
    HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    (void)hr;  // tolerate already-initialized in another mode
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

struct MicEntry {
  std::string name;
  std::string id;
};

std::mutex g_mics_mu;
std::vector<MicEntry> g_mics;

IMMDeviceEnumerator* CreateEnumerator() {
  IMMDeviceEnumerator* e = nullptr;
  HRESULT hr = CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr,
                                CLSCTX_ALL, __uuidof(IMMDeviceEnumerator),
                                reinterpret_cast<void**>(&e));
  return SUCCEEDED(hr) ? e : nullptr;
}

std::string FriendlyName(IMMDevice* dev) {
  std::string name;
  IPropertyStore* props = nullptr;
  if (SUCCEEDED(dev->OpenPropertyStore(STGM_READ, &props)) && props) {
    PROPVARIANT pv;
    PropVariantInit(&pv);
    if (SUCCEEDED(props->GetValue(kDeviceFriendlyName, &pv)) &&
        pv.vt == VT_LPWSTR) {
      name = WideToUtf8(pv.pwszVal);
    }
    PropVariantClear(&pv);
    SafeRelease(&props);
  }
  return name;
}

void RefreshDevices() {
  std::vector<MicEntry> mics;
  IMMDeviceEnumerator* en = CreateEnumerator();
  if (en) {
    IMMDeviceCollection* coll = nullptr;
    if (SUCCEEDED(en->EnumAudioEndpoints(eCapture, DEVICE_STATE_ACTIVE,
                                         &coll)) &&
        coll) {
      UINT count = 0;
      coll->GetCount(&count);
      for (UINT i = 0; i < count; i++) {
        IMMDevice* dev = nullptr;
        if (SUCCEEDED(coll->Item(i, &dev)) && dev) {
          MicEntry e;
          e.name = FriendlyName(dev);
          LPWSTR id = nullptr;
          if (SUCCEEDED(dev->GetId(&id)) && id) {
            e.id = WideToUtf8(id);
            CoTaskMemFree(id);
          }
          mics.push_back(std::move(e));
          SafeRelease(&dev);
        }
      }
      SafeRelease(&coll);
    }
    SafeRelease(&en);
  }
  std::lock_guard<std::mutex> lk(g_mics_mu);
  g_mics = std::move(mics);
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

struct um_mic {
  IAudioClient* client = nullptr;
  IAudioCaptureClient* capture = nullptr;
  int32_t sampleRate = 0;
  int32_t channels = 0;
  int32_t bits = 16;
};

extern "C" {

int32_t um_mic_count(void) {
  EnsureCom();
  RefreshDevices();
  std::lock_guard<std::mutex> lk(g_mics_mu);
  return static_cast<int32_t>(g_mics.size());
}

int32_t um_mic_name(int32_t index, char* buf, int32_t buf_len) {
  std::lock_guard<std::mutex> lk(g_mics_mu);
  if (index < 0 || index >= static_cast<int32_t>(g_mics.size())) return -1;
  return CopyUtf8(g_mics[index].name, buf, buf_len);
}

int32_t um_mic_id(int32_t index, char* buf, int32_t buf_len) {
  std::lock_guard<std::mutex> lk(g_mics_mu);
  if (index < 0 || index >= static_cast<int32_t>(g_mics.size())) return -1;
  return CopyUtf8(g_mics[index].id, buf, buf_len);
}

um_mic* um_mic_open(int32_t index, int32_t sample_rate, int32_t channels) {
  EnsureCom();
  if (sample_rate <= 0) sample_rate = 48000;
  if (channels <= 0) channels = 1;

  IMMDeviceEnumerator* en = CreateEnumerator();
  if (!en) return nullptr;

  IMMDevice* device = nullptr;
  IMMDeviceCollection* coll = nullptr;
  if (SUCCEEDED(en->EnumAudioEndpoints(eCapture, DEVICE_STATE_ACTIVE, &coll)) &&
      coll) {
    UINT count = 0;
    coll->GetCount(&count);
    if (index >= 0 && static_cast<UINT>(index) < count) {
      coll->Item(static_cast<UINT>(index), &device);
    }
    SafeRelease(&coll);
  }
  if (!device) {
    // Fall back to the default capture endpoint.
    en->GetDefaultAudioEndpoint(eCapture, eConsole, &device);
  }
  SafeRelease(&en);
  if (!device) return nullptr;

  IAudioClient* client = nullptr;
  HRESULT hr = device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr,
                                reinterpret_cast<void**>(&client));
  SafeRelease(&device);
  if (FAILED(hr) || !client) return nullptr;

  WAVEFORMATEX wfx{};
  wfx.wFormatTag = WAVE_FORMAT_PCM;
  wfx.nChannels = static_cast<WORD>(channels);
  wfx.nSamplesPerSec = static_cast<DWORD>(sample_rate);
  wfx.wBitsPerSample = 16;
  wfx.nBlockAlign = static_cast<WORD>(channels * 2);
  wfx.nAvgBytesPerSec = static_cast<DWORD>(sample_rate) * wfx.nBlockAlign;
  wfx.cbSize = 0;

  const REFERENCE_TIME bufferDuration = 2000000;  // 200 ms in 100-ns units
  const DWORD flags = AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM |
                      AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY;
  hr = client->Initialize(AUDCLNT_SHAREMODE_SHARED, flags, bufferDuration, 0,
                          &wfx, nullptr);
  if (FAILED(hr)) {
    SafeRelease(&client);
    return nullptr;
  }

  IAudioCaptureClient* capture = nullptr;
  hr = client->GetService(__uuidof(IAudioCaptureClient),
                          reinterpret_cast<void**>(&capture));
  if (FAILED(hr) || !capture) {
    SafeRelease(&client);
    return nullptr;
  }
  if (FAILED(client->Start())) {
    SafeRelease(&capture);
    SafeRelease(&client);
    return nullptr;
  }

  auto* mic = new um_mic();
  mic->client = client;
  mic->capture = capture;
  mic->sampleRate = sample_rate;
  mic->channels = channels;
  mic->bits = 16;
  return mic;
}

void um_mic_format(um_mic* mic, int32_t* sample_rate, int32_t* channels,
                   int32_t* bits_per_sample) {
  if (!mic) return;
  if (sample_rate) *sample_rate = mic->sampleRate;
  if (channels) *channels = mic->channels;
  if (bits_per_sample) *bits_per_sample = mic->bits;
}

int32_t um_mic_read(um_mic* mic, uint8_t* dst, int32_t dst_len) {
  if (!mic || !mic->capture || !dst) return -1;
  const int32_t frameBytes = mic->channels * (mic->bits / 8);

  for (int attempts = 0; attempts < 2000; attempts++) {
    UINT32 packetFrames = 0;
    if (FAILED(mic->capture->GetNextPacketSize(&packetFrames))) return -1;
    if (packetFrames == 0) {
      Sleep(2);
      continue;
    }

    BYTE* data = nullptr;
    UINT32 framesAvailable = 0;
    DWORD flags = 0;
    HRESULT hr =
        mic->capture->GetBuffer(&data, &framesAvailable, &flags, nullptr, nullptr);
    if (FAILED(hr)) return -1;

    int32_t avail = static_cast<int32_t>(framesAvailable) * frameBytes;
    int32_t n = avail < dst_len ? avail : dst_len;
    if (flags & AUDCLNT_BUFFERFLAGS_SILENT) {
      memset(dst, 0, static_cast<size_t>(n));
    } else {
      memcpy(dst, data, static_cast<size_t>(n));
    }
    mic->capture->ReleaseBuffer(framesAvailable);
    return n;
  }
  return 0;
}

void um_mic_close(um_mic* mic) {
  if (!mic) return;
  if (mic->client) mic->client->Stop();
  SafeRelease(&mic->capture);
  SafeRelease(&mic->client);
  delete mic;
}

}  // extern "C"

#elif defined(__ANDROID__)  // --- AAudio capture ----------------------------
// NB: Android also defines __linux__, so this branch must precede the ALSA one.
// Requires the host app to hold the RECORD_AUDIO runtime permission.
// AAudio has no NDK device enumeration, so only a single "Default" input is
// exposed (device selection is a Java AudioManager concern).

#include <aaudio/AAudio.h>

#include <string>

struct um_mic {
  AAudioStream* stream = nullptr;
  int32_t sampleRate = 0;
  int32_t channels = 0;
  int32_t bits = 16;
};

extern "C" {

int32_t um_mic_count(void) { return 1; }

int32_t um_mic_name(int32_t index, char* buf, int32_t buf_len) {
  if (index != 0 || !buf || buf_len <= 0) return -1;
  const char* name = "Default";
  int32_t n = static_cast<int32_t>(strlen(name));
  if (n > buf_len - 1) n = buf_len - 1;
  memcpy(buf, name, static_cast<size_t>(n));
  buf[n] = '\0';
  return n;
}

int32_t um_mic_id(int32_t index, char* buf, int32_t buf_len) {
  return um_mic_name(index, buf, buf_len);
}

um_mic* um_mic_open(int32_t index, int32_t sample_rate, int32_t channels) {
  if (index != 0) return nullptr;
  if (sample_rate <= 0) sample_rate = 48000;
  if (channels <= 0) channels = 1;

  AAudioStreamBuilder* builder = nullptr;
  if (AAudio_createStreamBuilder(&builder) != AAUDIO_OK || !builder) {
    return nullptr;
  }
  AAudioStreamBuilder_setDirection(builder, AAUDIO_DIRECTION_INPUT);
  AAudioStreamBuilder_setFormat(builder, AAUDIO_FORMAT_PCM_I16);
  AAudioStreamBuilder_setChannelCount(builder, channels);
  AAudioStreamBuilder_setSampleRate(builder, sample_rate);
  AAudioStreamBuilder_setPerformanceMode(builder,
                                         AAUDIO_PERFORMANCE_MODE_LOW_LATENCY);

  AAudioStream* stream = nullptr;
  const aaudio_result_t rc = AAudioStreamBuilder_openStream(builder, &stream);
  AAudioStreamBuilder_delete(builder);
  if (rc != AAUDIO_OK || !stream) return nullptr;

  if (AAudioStream_requestStart(stream) != AAUDIO_OK) {
    AAudioStream_close(stream);
    return nullptr;
  }

  auto* mic = new um_mic();
  mic->stream = stream;
  mic->sampleRate = AAudioStream_getSampleRate(stream);
  mic->channels = AAudioStream_getChannelCount(stream);
  mic->bits = 16;
  return mic;
}

void um_mic_format(um_mic* mic, int32_t* sample_rate, int32_t* channels,
                   int32_t* bits_per_sample) {
  if (!mic) return;
  if (sample_rate) *sample_rate = mic->sampleRate;
  if (channels) *channels = mic->channels;
  if (bits_per_sample) *bits_per_sample = mic->bits;
}

int32_t um_mic_read(um_mic* mic, uint8_t* dst, int32_t dst_len) {
  if (!mic || !mic->stream || !dst) return -1;
  const int frameBytes = mic->channels * (mic->bits / 8);
  const int32_t frames = dst_len / frameBytes;
  if (frames == 0) return 0;

  // Block up to 200 ms for a buffer of samples.
  const int32_t n =
      AAudioStream_read(mic->stream, dst, frames, 200LL * 1000 * 1000);
  if (n < 0) return -1;
  return n * frameBytes;
}

void um_mic_close(um_mic* mic) {
  if (!mic) return;
  if (mic->stream) {
    AAudioStream_requestStop(mic->stream);
    AAudioStream_close(mic->stream);
  }
  delete mic;
}

}  // extern "C"

#elif defined(__linux__)  // --- ALSA capture ----------------------------------

#include <alsa/asoundlib.h>

#include <mutex>
#include <string>
#include <vector>

namespace {

struct MicEntry {
  std::string name;
  std::string id;
};

std::mutex g_mics_mu;
std::vector<MicEntry> g_mics;

// ALSA capture PCM devices via the control interface. Always includes
// "default" so a system with a configured default mic is usable.
void RefreshDevices() {
  std::vector<MicEntry> mics;
  mics.push_back({"Default", "default"});

  int card = -1;
  while (snd_card_next(&card) == 0 && card >= 0) {
    char* cardName = nullptr;
    if (snd_card_get_name(card, &cardName) == 0 && cardName) {
      std::string hw = "hw:" + std::to_string(card);
      mics.push_back({cardName, hw});
      free(cardName);
    }
  }

  std::lock_guard<std::mutex> lk(g_mics_mu);
  g_mics = std::move(mics);
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

struct um_mic {
  snd_pcm_t* pcm = nullptr;
  int32_t sampleRate = 0;
  int32_t channels = 0;
  int32_t bits = 16;
};

extern "C" {

int32_t um_mic_count(void) {
  RefreshDevices();
  std::lock_guard<std::mutex> lk(g_mics_mu);
  return static_cast<int32_t>(g_mics.size());
}

int32_t um_mic_name(int32_t index, char* buf, int32_t buf_len) {
  std::lock_guard<std::mutex> lk(g_mics_mu);
  if (index < 0 || index >= static_cast<int32_t>(g_mics.size())) return -1;
  return CopyUtf8(g_mics[index].name, buf, buf_len);
}

int32_t um_mic_id(int32_t index, char* buf, int32_t buf_len) {
  std::lock_guard<std::mutex> lk(g_mics_mu);
  if (index < 0 || index >= static_cast<int32_t>(g_mics.size())) return -1;
  return CopyUtf8(g_mics[index].id, buf, buf_len);
}

um_mic* um_mic_open(int32_t index, int32_t sample_rate, int32_t channels) {
  if (sample_rate <= 0) sample_rate = 48000;
  if (channels <= 0) channels = 1;

  std::string id;
  {
    RefreshDevices();
    std::lock_guard<std::mutex> lk(g_mics_mu);
    if (index < 0 || index >= static_cast<int32_t>(g_mics.size())) {
      return nullptr;
    }
    id = g_mics[index].id;
  }

  snd_pcm_t* pcm = nullptr;
  if (snd_pcm_open(&pcm, id.c_str(), SND_PCM_STREAM_CAPTURE, 0) < 0) {
    return nullptr;
  }
  unsigned rate = static_cast<unsigned>(sample_rate);
  if (snd_pcm_set_params(pcm, SND_PCM_FORMAT_S16_LE,
                         SND_PCM_ACCESS_RW_INTERLEAVED,
                         static_cast<unsigned>(channels), rate, 1,
                         200000) < 0) {  // 200 ms latency
    snd_pcm_close(pcm);
    return nullptr;
  }

  auto* mic = new um_mic();
  mic->pcm = pcm;
  mic->sampleRate = static_cast<int32_t>(rate);
  mic->channels = channels;
  mic->bits = 16;
  return mic;
}

void um_mic_format(um_mic* mic, int32_t* sample_rate, int32_t* channels,
                   int32_t* bits_per_sample) {
  if (!mic) return;
  if (sample_rate) *sample_rate = mic->sampleRate;
  if (channels) *channels = mic->channels;
  if (bits_per_sample) *bits_per_sample = mic->bits;
}

int32_t um_mic_read(um_mic* mic, uint8_t* dst, int32_t dst_len) {
  if (!mic || !mic->pcm || !dst) return -1;
  const int frameBytes = mic->channels * (mic->bits / 8);
  snd_pcm_uframes_t frames = dst_len / frameBytes;
  if (frames == 0) return 0;

  snd_pcm_sframes_t n = snd_pcm_readi(mic->pcm, dst, frames);
  if (n == -EPIPE) {
    snd_pcm_prepare(mic->pcm);  // recover from overrun
    return 0;
  }
  if (n < 0) {
    n = snd_pcm_recover(mic->pcm, static_cast<int>(n), 1);
    if (n < 0) return -1;
    return 0;
  }
  return static_cast<int32_t>(n) * frameBytes;
}

void um_mic_close(um_mic* mic) {
  if (!mic) return;
  if (mic->pcm) {
    snd_pcm_drop(mic->pcm);
    snd_pcm_close(mic->pcm);
  }
  delete mic;
}

}  // extern "C"

#else  // --- other platforms stub ---------------------------------------------

struct um_mic {};

extern "C" {
int32_t um_mic_count(void) { return 0; }
int32_t um_mic_name(int32_t, char*, int32_t) { return -1; }
int32_t um_mic_id(int32_t, char*, int32_t) { return -1; }
um_mic* um_mic_open(int32_t, int32_t, int32_t) { return nullptr; }
void um_mic_format(um_mic*, int32_t* sr, int32_t* ch, int32_t* bits) {
  if (sr) *sr = 0;
  if (ch) *ch = 0;
  if (bits) *bits = 0;
}
int32_t um_mic_read(um_mic*, uint8_t*, int32_t) { return -1; }
void um_mic_close(um_mic*) {}
}  // extern "C"

#endif
