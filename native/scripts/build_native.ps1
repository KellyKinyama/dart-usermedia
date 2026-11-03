# build_native.ps1 — build the usermedia_ffi shared library (Windows).
#
# Locates the Flutter-bundled Dart SDK includes and the MSVC Build Tools, then
# configures + builds the shim with Ninja into native/usermedia_ffi/build.
#
#   ./native/scripts/build_native.ps1 [-Config Release|Debug]

[CmdletBinding()]
param(
  [ValidateSet('Release', 'Debug')] [string] $Config = 'Release'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot)   # repo root
$shim = Join-Path $root 'native\usermedia_ffi'

# Dart SDK include dir (contains dart_api_dl.c).
$dart = (Get-Command dart -ErrorAction SilentlyContinue).Source
if (-not $dart) { throw 'dart not found on PATH' }
$candidates = @(
  'C:/flutter/flutter/bin/cache/dart-sdk/include',
  (Join-Path (Split-Path (Split-Path $dart)) 'cache/dart-sdk/include'),
  (Join-Path (Split-Path (Split-Path $dart)) 'include')
)
$dartInclude = $candidates | Where-Object { Test-Path (Join-Path $_ 'dart_api_dl.c') } | Select-Object -First 1
if (-not $dartInclude) { throw "Could not locate the Dart SDK include dir (dart_api_dl.c). Tried: $($candidates -join ', ')" }

# MSVC environment.
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vs) { throw 'Visual Studio with VC Tools not found' }
$vcvars = Join-Path $vs 'VC\Auxiliary\Build\vcvars64.bat'

$cmake = (Get-Command cmake -ErrorAction SilentlyContinue).Source
if (-not $cmake) { throw 'cmake not found on PATH' }

Write-Host "Dart include: $dartInclude"
Write-Host "Config:       $Config"

Push-Location $shim
try {
  cmd /c "`"$vcvars`" >nul && `"$cmake`" -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=$Config -DDART_SDK_INCLUDE=$dartInclude && `"$cmake`" --build build"
  if ($LASTEXITCODE -ne 0) { throw "build failed ($LASTEXITCODE)" }
} finally {
  Pop-Location
}

$dll = Join-Path $shim 'build\usermedia_ffi.dll'
Write-Host "`nBuilt: $dll (exists: $(Test-Path $dll))" -ForegroundColor Green
