# Speedll Connect — Windows Desktop Build & Packaging Script (PowerShell)
# Builds SpeedllConnect.exe (Flutter Windows Release) and bundles sing-box.exe (v1.14.4 windows-amd64)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir
$AppDir = Join-Path $RepoRoot "app"
$ReleaseDir = Join-Path $AppDir "build\windows\x64\runner\Release"
$OutputBundleDir = Join-Path $RepoRoot "Speedll-Connect-Windows-v1.1.0"

Write-Host "==> [1/4] Checking Flutter Windows toolchain..." -ForegroundColor Cyan
Set-Location $AppDir
flutter config --enable-windows-desktop
flutter pub get

Write-Host "==> [2/4] Building Speedll Connect Windows Release (.exe)..." -ForegroundColor Cyan
flutter build windows --release

Write-Host "==> [3/4] Preparing standalone Windows bundle..." -ForegroundColor Cyan
if (Test-Path $OutputBundleDir) {
    Remove-Item -Recurse -Force $OutputBundleDir
}
New-Item -ItemType Directory -Path $OutputBundleDir | Out-Null
Copy-Item -Path "$ReleaseDir\*" -Destination $OutputBundleDir -Recurse -Force

$BinDir = Join-Path $OutputBundleDir "bin"
New-Item -ItemType Directory -Path $BinDir -Force | Out-Null

$SingboxExe = Join-Path $BinDir "sing-box.exe"
if (-not (Test-Path $SingboxExe)) {
    Write-Host "==> [4/4] Downloading sing-box v1.14.4 (windows-amd64)..." -ForegroundColor Cyan
    $ZipUrl = "https://github.com/SagerNet/sing-box/releases/download/v1.14.4/sing-box-1.14.4-windows-amd64.zip"
    $TempZip = Join-Path $env:TEMP "sing-box-win-amd64.zip"
    $TempExtract = Join-Path $env:TEMP "sing-box-extracted"
    Invoke-WebRequest -Uri $ZipUrl -OutFile $TempZip
    if (Test-Path $TempExtract) { Remove-Item -Recurse -Force $TempExtract }
    Expand-Archive -Path $TempZip -DestinationPath $TempExtract -Force
    $FoundExe = Get-ChildItem -Path $TempExtract -Filter "sing-box.exe" -Recurse | Select-Object -First 1
    if ($FoundExe) {
        Copy-Item -Path $FoundExe.FullName -Destination $SingboxExe -Force
    }
}

Write-Host "==> Done! Windows bundle ready at: $OutputBundleDir\SpeedllConnect.exe" -ForegroundColor Green
