# fetch_webrtc_prebuilt.ps1 — download & unpack a prebuilt libwebrtc.
#
# Avoids the multi-hour depot_tools/gn/ninja source build. Point it at a
# release archive that contains libwebrtc headers + a combined static lib.
#
# Known community prebuilts (verify the version/ABI yourself before trusting):
#   - https://github.com/crow-misia/libwebrtc-bin/releases
#   - https://github.com/shiguredo-webrtc-build/webrtc-build/releases
#
# Usage:
#   ./fetch_webrtc_prebuilt.ps1 -Url <archive-url> [-Dest ../../third_party/webrtc]
#
# After extraction, note the two paths CMake needs and pass them to the build:
#   -DWEBRTC_ROOT=<dir containing api/ modules/ rtc_base/>
#   -DWEBRTC_LIB=<path to webrtc.lib>

[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)] [string] $Url,
  [string] $Dest = (Join-Path $PSScriptRoot '..\..\third_party\webrtc'),
  [string] $Sha256
)

$ErrorActionPreference = 'Stop'
$Dest = [System.IO.Path]::GetFullPath($Dest)
New-Item -ItemType Directory -Force -Path $Dest | Out-Null

$archive = Join-Path $env:TEMP ("webrtc_" + [System.IO.Path]::GetFileName($Url))
Write-Host "Downloading $Url"
Invoke-WebRequest -Uri $Url -OutFile $archive

if ($Sha256) {
  $actual = (Get-FileHash -Algorithm SHA256 -Path $archive).Hash
  if ($actual -ne $Sha256.ToUpper()) {
    throw "SHA256 mismatch. Expected $Sha256 got $actual"
  }
  Write-Host "SHA256 verified."
} else {
  Write-Warning "No -Sha256 supplied; integrity not verified."
}

Write-Host "Extracting to $Dest"
switch ([System.IO.Path]::GetExtension($archive).ToLower()) {
  '.zip'  { Expand-Archive -Path $archive -DestinationPath $Dest -Force }
  default { tar -xf $archive -C $Dest }   # tar handles .tar.gz / .tar.xz
}

Write-Host "`nDone. Locate api/ and webrtc.lib, then configure with:" -ForegroundColor Green
Write-Host "  -DWEBRTC_ROOT=<...>  -DWEBRTC_LIB=<...>"
Get-ChildItem -Path $Dest -Recurse -Filter 'webrtc.lib' -ErrorAction SilentlyContinue |
  ForEach-Object { Write-Host "  found lib: $($_.FullName)" }
