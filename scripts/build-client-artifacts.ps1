param(
  [switch]$IncludeApple,
  [string]$FlutterPath = "C:\dev\flutter\bin\flutter.bat",
  [string]$JavaHome = "C:\Program Files\Android\Android Studio\jbr",
  [string]$MacHost = "mnemosyne-mac"
)

$ErrorActionPreference = "Stop"

function Invoke-Step {
  param(
    [Parameter(Mandatory = $true)][string]$Label,
    [Parameter(Mandatory = $true)][scriptblock]$Action
  )

  Write-Host "==> $Label" -ForegroundColor Cyan
  & $Action
}

if (-not (Test-Path $FlutterPath)) {
  throw "Flutter not found at $FlutterPath"
}

$env:JAVA_HOME = $JavaHome
if (-not (($env:Path -split ';') -contains "$JavaHome\bin")) {
  $env:Path = "$JavaHome\bin;$env:Path"
}

Push-Location (Join-Path $PSScriptRoot "..\apps\client_flutter")
try {
  Invoke-Step "Flutter analyze" {
    & $FlutterPath analyze
  }

  Invoke-Step "Flutter test" {
    & $FlutterPath test
  }

  Invoke-Step "Build Windows desktop" {
    & $FlutterPath build windows
  }

  Invoke-Step "Build Android debug APK" {
    & $FlutterPath build apk --debug
  }

  if ($IncludeApple) {
    $remoteCommand = @"
export PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:`$HOME/dev/flutter/bin:`$PATH
export LANG=en_US.UTF-8
cd ~/dev/Mnemosyne/apps/client_flutter
~/dev/flutter/bin/flutter test
~/dev/flutter/bin/flutter build macos
~/dev/flutter/bin/flutter build ios --simulator
"@
    Invoke-Step "Build Apple artifacts on $MacHost" {
      ssh $MacHost $remoteCommand
    }
  }
}
finally {
  Pop-Location
}

Write-Host ""
Write-Host "Artifacts:" -ForegroundColor Green
Write-Host "  Windows: apps/client_flutter/build/windows/x64/runner/Release/mnemosyne.exe"
Write-Host "  Android: apps/client_flutter/build/app/outputs/flutter-apk/app-debug.apk"
if ($IncludeApple) {
  Write-Host "  macOS:   ~/dev/Mnemosyne/apps/client_flutter/build/macos/Build/Products/Release/mnemosyne.app"
  Write-Host "  iOS sim: ~/dev/Mnemosyne/apps/client_flutter/build/ios/iphonesimulator/Runner.app"
}
