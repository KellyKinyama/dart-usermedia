# CMakeLists.txt — builds the usermedia_ffi shared library.
#
# The Dart native API headers (dart_api_dl.h / dart_api_dl.c) ship with the
# Dart SDK under <sdk>/include and are always required:
#   cmake -S . -B build -G Ninja \
#     -DDART_SDK_INCLUDE="C:/.../dart-sdk/include"
#
# libwebrtc is optional. Without it the shim builds in "stub" mode (Phase 0
# handshake only). To link libwebrtc (Phase 1+), point the build at a checkout
# and its combined static lib:
#   -DWEBRTC_ROOT="C:/webrtc/src"
#   -DWEBRTC_LIB="C:/webrtc/src/out/Release/obj/webrtc.lib"
# When present, the macro UM_HAVE_WEBRTC is defined for the C++ sources.

cmake_minimum_required(VERSION 3.15)
project(usermedia_ffi LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_C_STANDARD 11)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# Hide symbols by default; the UM_EXPORT macro opts specific ones back in.
set(CMAKE_C_VISIBILITY_PRESET hidden)
set(CMAKE_CXX_VISIBILITY_PRESET hidden)

# --- Dart SDK include (required) ---------------------------------------------
if(NOT DEFINED DART_SDK_INCLUDE AND DEFINED ENV{DART_SDK_INCLUDE})
  set(DART_SDK_INCLUDE "$ENV{DART_SDK_INCLUDE}")
endif()

if(NOT DART_SDK_INCLUDE)
  message(FATAL_ERROR
    "DART_SDK_INCLUDE is not set. Point it at your Dart SDK 'include' "
    "directory (contains dart_api_dl.h and dart_api_dl.c).")
endif()

if(NOT EXISTS "${DART_SDK_INCLUDE}/dart_api_dl.c")
  message(FATAL_ERROR
    "dart_api_dl.c not found under '${DART_SDK_INCLUDE}'. "
    "Check DART_SDK_INCLUDE.")
endif()

# --- libwebrtc (optional) ----------------------------------------------------
if(NOT DEFINED WEBRTC_ROOT AND DEFINED ENV{WEBRTC_ROOT})
  set(WEBRTC_ROOT "$ENV{WEBRTC_ROOT}")
endif()
if(NOT DEFINED WEBRTC_LIB AND DEFINED ENV{WEBRTC_LIB})
  set(WEBRTC_LIB "$ENV{WEBRTC_LIB}")
endif()

set(HAVE_WEBRTC OFF)
if(WEBRTC_ROOT)
  if(NOT EXISTS "${WEBRTC_ROOT}/api")
    message(FATAL_ERROR
      "WEBRTC_ROOT='${WEBRTC_ROOT}' does not look like a libwebrtc src root "
      "(expected an 'api/' subdirectory).")
  endif()
  if(NOT WEBRTC_LIB OR NOT EXISTS "${WEBRTC_LIB}")
    message(FATAL_ERROR
      "WEBRTC_ROOT is set but WEBRTC_LIB='${WEBRTC_LIB}' is missing. Point "
      "WEBRTC_LIB at the combined static library "
      "(e.g. out/Release/obj/webrtc.lib).")
  endif()
  set(HAVE_WEBRTC ON)
  message(STATUS "usermedia_ffi: libwebrtc ENABLED (${WEBRTC_LIB})")
else()
  message(STATUS "usermedia_ffi: libwebrtc DISABLED (stub mode). "
                 "Set WEBRTC_ROOT + WEBRTC_LIB to enable.")
endif()

# --- target ------------------------------------------------------------------
add_library(usermedia_ffi SHARED
  src/context.cc
  src/dart_bridge.cc
  src/webrtc_probe.cc
  src/camera.cc
  src/mic.cc
  src/screen.cc
  src/encoder.cc
  "${DART_SDK_INCLUDE}/dart_api_dl.c"
)

target_include_directories(usermedia_ffi PRIVATE
  include
  "${DART_SDK_INCLUDE}"
)

# Keep the output name stable across platforms (libusermedia_ffi.* /
# usermedia_ffi.dll) so the Dart loader can find it predictably.
set_target_properties(usermedia_ffi PROPERTIES
  OUTPUT_NAME "usermedia_ffi"
  C_VISIBILITY_PRESET hidden
  CXX_VISIBILITY_PRESET hidden
)

if(WIN32)
  # Media Foundation video capture (camera.cc) + WASAPI audio (mic.cc) +
  # DXGI Desktop Duplication (screen.cc) + H.264 encoder MFT (encoder.cc).
  target_link_libraries(usermedia_ffi PRIVATE
    mfplat mf mfreadwrite mfuuid wmcodecdspuuid shlwapi ole32 d3d11 dxgi)
endif()

if(HAVE_WEBRTC)
  target_compile_definitions(usermedia_ffi PRIVATE UM_HAVE_WEBRTC=1)

  # libwebrtc headers reference its vendored third_party includes.
  target_include_directories(usermedia_ffi PRIVATE
    "${WEBRTC_ROOT}"
    "${WEBRTC_ROOT}/third_party/abseil-cpp"
    "${WEBRTC_ROOT}/third_party/libyuv/include"
  )

  if(WIN32)
    # Match libwebrtc's release build settings (static CRT, no iterator debug).
    set_property(TARGET usermedia_ffi PROPERTY
      MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
    target_compile_definitions(usermedia_ffi PRIVATE
      WEBRTC_WIN=1 NOMINMAX WIN32_LEAN_AND_MEAN
      _HAS_ITERATOR_DEBUGGING=0 _ITERATOR_DEBUG_LEVEL=0)
    target_link_libraries(usermedia_ffi PRIVATE
      "${WEBRTC_LIB}"
      winmm ws2_32 secur32 msdmo dmoguids wmcodecdspuuid strmiids
      iphlpapi ole32 oleaut32 user32 gdi32 advapi32 shell32 dxgi d3d11)
  elseif(APPLE)
    target_compile_definitions(usermedia_ffi PRIVATE
      WEBRTC_MAC=1 WEBRTC_POSIX=1)
    target_link_libraries(usermedia_ffi PRIVATE "${WEBRTC_LIB}"
      "-framework Foundation" "-framework AVFoundation" "-framework CoreMedia"
      "-framework CoreVideo" "-framework CoreAudio" "-framework AudioToolbox")
  else()
    target_compile_definitions(usermedia_ffi PRIVATE
      WEBRTC_LINUX=1 WEBRTC_POSIX=1)
    target_link_libraries(usermedia_ffi PRIVATE "${WEBRTC_LIB}" pthread dl)
  endif()
endif()
