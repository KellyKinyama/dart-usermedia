# build_webrtc_source.ps1 — build libwebrtc from source via depot_tools.
#
# WARNING: heavyweight. Expect a large checkout (tens of GB) and a long build.
# Run from a Developer PowerShell (MSVC on PATH). Requires Windows 10 SDK with
# the Debugging Tools component.
#
# Steps automated:
#   1. Clone depot_tools and add to PATH.
#   2. `fetch webrtc` into a src checkout at -SrcRoot.
#   3. Sync to a pinned branch/revision (-Revision).
#   4. `gn gen` a Release config and `ninja` the combined target.
#
# Usage:
#   ./build_webrtc_source.ps1 -SrcRoot C:\webrtc -Revision branch-heads/6478
#
# After it completes, configure the shim with:
#   -DWEBRTC_ROOT=<SrcRoot>\src
#   -DWEBRTC_LIB=<SrcRoot>\src\out\Release\obj\webrtc.lib

[CmdletBinding()]
param(
  [string] $SrcRoot = 'C:\webrtc',
  [string] $Revision = '',           # e.g. branch-heads/6478 or a commit hash
  [string] $Args = 'is_debug=false rtc_include_tests=false use_custom_libcxx=false is_component_build=false rtc_build_examples=false target_cpu="x64"'
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $SrcRoot | Out-Null
Set-Location $SrcRoot

if (-not (Test-Path (Join-Path $SrcRoot 'depot_tools'))) {
  Write-Host "Cloning depot_tools..."
  git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git
}
$env:PATH = (Join-Path $SrcRoot 'depot_tools') + ';' + $env:PATH
$env:DEPOT_TOOLS_WIN_TOOLCHAIN = '0'   # use the local MSVC install

if (-not (Test-Path (Join-Path $SrcRoot 'src'))) {
  Write-Host "Fetching webrtc (this is large and slow)..."
  cmd /c 'fetch --nohooks webrtc'
}

Set-Location (Join-Path $SrcRoot 'src')
if ($Revision) {
  Write-Host "Checking out $Revision"
  git checkout $Revision
}
cmd /c 'gclient sync -D'

Write-Host "Generating Release build..."
cmd /c "gn gen out\Release --args=`"$Args`""

Write-Host "Building combined static lib (ninja webrtc)..."
cmd /c 'ninja -C out\Release webrtc'

$lib = Join-Path $SrcRoot 'src\out\Release\obj\webrtc.lib'
Write-Host "`nDone." -ForegroundColor Green
Write-Host "  -DWEBRTC_ROOT=$(Join-Path $SrcRoot 'src')"
Write-Host "  -DWEBRTC_LIB=$lib  (exists: $(Test-Path $lib))"
