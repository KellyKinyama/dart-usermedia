# build-android.ps1 — cross-compile the usermedia_ffi .so for Android via NDK.
#
# Camera2 NDK (camera) + AAudio (mic); screen is a stub (MediaProjection is
# Java-only). The host app must grant CAMERA / RECORD_AUDIO at runtime.
#
#   ./native/scripts/build-android.ps1 -Ndk C:\path\to\android-ndk -Abi arm64-v8a
#
# Produces build-android-<abi>/libusermedia_ffi.so for bundling per ABI.

[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)] [string] $Ndk,
  [ValidateSet('arm64-v8a', 'armeabi-v7a', 'x86_64', 'x86')]
  [string] $Abi = 'arm64-v8a',
  [int] $ApiLevel = 26,  # AAudio requires API 26+
  [string] $DartSdkInclude = 'C:/flutter/flutter/bin/cache/dart-sdk/include'
)

$ErrorActionPreference = 'Stop'
$shim = Split-Path $PSScriptRoot      # native/
$shim = Join-Path $shim 'usermedia_ffi'

$toolchain = Join-Path $Ndk 'build/cmake/android.toolchain.cmake'
if (-not (Test-Path $toolchain)) { throw "NDK toolchain not found: $toolchain" }

$cmake = (Get-Command cmake -ErrorAction SilentlyContinue).Source
if (-not $cmake) { throw 'cmake not found on PATH' }

# Prefer a bundled ninja (NDK/SDK), else the VS-shipped one.
$ninja = @(
  (Get-ChildItem (Join-Path $Ndk 'prebuilt') -Recurse -Filter ninja.exe -EA SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName),
  (Get-ChildItem "$env:LOCALAPPDATA\Android\Sdk\cmake" -Recurse -Filter ninja.exe -EA SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName),
  (Get-ChildItem 'C:\Program Files (x86)\Microsoft Visual Studio' -Recurse -Filter ninja.exe -EA SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName)
) | Where-Object { $_ } | Select-Object -First 1
if (-not $ninja) { throw 'ninja.exe not found (install via Android SDK CMake or VS)' }

$build = Join-Path $shim "build-android-$Abi"
& $cmake -S $shim -B $build -G Ninja -DCMAKE_MAKE_PROGRAM="$ninja" `
  -DCMAKE_TOOLCHAIN_FILE="$toolchain" -DANDROID_ABI=$Abi `
  -DANDROID_PLATFORM="android-$ApiLevel" -DDART_SDK_INCLUDE=$DartSdkInclude
& $cmake --build $build

$so = Join-Path $build 'libusermedia_ffi.so'
Write-Host "`nBuilt: $so (exists: $(Test-Path $so))" -ForegroundColor Green
