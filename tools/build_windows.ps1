# Builds the Dramix Windows release, and optionally the Inno Setup installer.
#
#   pwsh -File tools\build_windows.ps1
#   pwsh -File tools\build_windows.ps1 -Installer
#
# Why this script exists: the `flutter_inappwebview_windows` plugin downloads
# WebView2 / WIL / nlohmann.json with `nuget` at build time, and NuGet writes
# its HTTP cache to %LOCALAPPDATA%\NuGet. On machines where that path is not
# writable (locked-down corporate images, restricted sandboxes) the build dies
# with a bare MSB3073. The script points NuGet at in-project directories and
# puts a local nuget.exe on PATH, which makes the build self-contained.

param(
  [switch]$Installer,
  [switch]$Debug
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$flutter = 'C:\flutter_sdk\flutter\bin\flutter.bat'
if (-not (Test-Path $flutter)) { $flutter = 'flutter' }

# --- NuGet in-project -------------------------------------------------------
$nugetExe = Join-Path $PSScriptRoot 'nuget.exe'
if (-not (Test-Path $nugetExe)) {
  Write-Host "Downloading nuget.exe ..."
  Invoke-WebRequest -Uri 'https://dist.nuget.org/win-x86-commandline/latest/nuget.exe' `
    -OutFile $nugetExe
}

$dirs = @("$root\.buildtmp", "$root\.nuget\packages",
          "$root\.nuget\http-cache", "$root\.nuget\plugins-cache")
foreach ($d in $dirs) { New-Item -ItemType Directory -Force -Path $d | Out-Null }

$env:PATH = "$PSScriptRoot;$env:PATH"
$env:TEMP = "$root\.buildtmp"
$env:TMP = "$root\.buildtmp"
$env:NUGET_PACKAGES = "$root\.nuget\packages"
$env:NUGET_HTTP_CACHE_PATH = "$root\.nuget\http-cache"
$env:NUGET_PLUGINS_CACHE_PATH = "$root\.nuget\plugins-cache"

Write-Host "nuget    : $nugetExe"
Write-Host "packages : $env:NUGET_PACKAGES"

# --- build ------------------------------------------------------------------
# A running instance locks dramix.exe and makes the link step fail (LNK1104).
Get-Process dramix -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 1

$mode = if ($Debug) { '--debug' } else { '--release' }
Write-Host "`nflutter build windows $mode"
& $flutter build windows $mode
if ($LASTEXITCODE -ne 0) { throw "flutter build windows failed ($LASTEXITCODE)" }

$exe = "$root\build\windows\x64\runner\Release\dramix.exe"
Write-Host "`nbuilt: $exe ($([math]::Round((Get-Item $exe).Length/1MB,2)) MB)"

if (-not $Installer) {
  Write-Host "`nPass -Installer to also build dist_windows\Dramix-setup-*.exe"
  exit 0
}

# --- installer --------------------------------------------------------------
$iscc = @(
  "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
  "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
  # winget installs Inno Setup per-user by default
  "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $iscc) {
  $cmd = Get-Command ISCC.exe -ErrorAction SilentlyContinue
  if ($cmd) { $iscc = $cmd.Source }
}

if (-not $iscc) {
  throw @"
Inno Setup not found. Install it, then re-run with -Installer:
  winget install --id JRSoftware.InnoSetup -e
or download from https://jrsoftware.org/isdl.php
"@
}

Write-Host "`nISCC: $iscc"
& $iscc "$root\dramix.iss"
if ($LASTEXITCODE -ne 0) { throw "ISCC failed ($LASTEXITCODE)" }

Get-ChildItem "$root\dist_windows" -File | ForEach-Object {
  Write-Host "artifact: $($_.Name) ($([math]::Round($_.Length/1MB,2)) MB)"
}
