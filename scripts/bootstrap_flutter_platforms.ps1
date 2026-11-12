$ErrorActionPreference = 'Stop'

# Run once from PowerShell. Generates Flutter host folders for all five OSs
# and restores the hand-written app files, including when flutter create fails.
$AppDir = (Resolve-Path (Join-Path $PSScriptRoot '..\app')).Path
$TempDir = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $TempDir | Out-Null
$Files = @('pubspec.yaml', 'analysis_options.yaml', 'lib/main.dart', 'test/widget_test.dart')

try {
    foreach ($File in $Files) {
        $Source = Join-Path $AppDir $File
        $Backup = Join-Path $TempDir $File
        New-Item -ItemType Directory -Force -Path (Split-Path $Backup) | Out-Null
        Copy-Item $Source $Backup
    }

    Push-Location $AppDir
    try {
        flutter create --org app.speedll --project-name speedll_connect_app --platforms=android,ios,windows,macos,linux .
        if ($LASTEXITCODE -ne 0) { throw "flutter create failed with exit code $LASTEXITCODE" }
    }
    finally {
        Pop-Location
    }

    Write-Host 'Flutter host folders generated.'
}
finally {
    foreach ($File in $Files) {
        $Backup = Join-Path $TempDir $File
        if (Test-Path $Backup) {
            $Destination = Join-Path $AppDir $File
            New-Item -ItemType Directory -Force -Path (Split-Path $Destination) | Out-Null
            Copy-Item $Backup $Destination -Force
        }
    }
    Remove-Item $TempDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'Hand-written app files restored. Review git diff before continuing.'
