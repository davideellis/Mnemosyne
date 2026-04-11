param(
  [string]$Version = "",
  [string]$OutputRoot = ".\dist\releases"
)

$ErrorActionPreference = "Stop"

function Get-Sha256 {
  param(
    [Parameter(Mandatory = $true)][string]$Path
  )

  return (Get-FileHash -Algorithm SHA256 -Path $Path).Hash.ToLowerInvariant()
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$clientRoot = Join-Path $repoRoot "apps\client_flutter"
$pubspecPath = Join-Path $clientRoot "pubspec.yaml"

if (-not (Test-Path $pubspecPath)) {
  throw "Missing pubspec at $pubspecPath"
}

$pubspec = Get-Content $pubspecPath
$declaredVersion = ($pubspec | Where-Object { $_ -match '^version:\s+' } | Select-Object -First 1) -replace '^version:\s+', ''
if ([string]::IsNullOrWhiteSpace($Version)) {
  $Version = $declaredVersion
}
if ([string]::IsNullOrWhiteSpace($Version)) {
  throw "Unable to determine release version."
}

$windowsSource = Join-Path $clientRoot "build\windows\x64\runner\Release"
$androidDebugApk = Join-Path $clientRoot "build\app\outputs\flutter-apk\app-debug.apk"
$androidReleaseApk = Join-Path $clientRoot "build\app\outputs\flutter-apk\app-release.apk"

foreach ($requiredPath in @($windowsSource, $androidDebugApk, $androidReleaseApk)) {
  if (-not (Test-Path $requiredPath)) {
    throw "Missing build artifact path: $requiredPath"
  }
}

$gitSha = (git -C $repoRoot rev-parse --short HEAD).Trim()
$releaseRoot = Join-Path $OutputRoot "mnemosyne-$Version-$gitSha"
$windowsReleaseRoot = Join-Path $releaseRoot "windows"
$androidReleaseRoot = Join-Path $releaseRoot "android"

if (Test-Path $releaseRoot) {
  Remove-Item -LiteralPath $releaseRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $windowsReleaseRoot | Out-Null
New-Item -ItemType Directory -Force -Path $androidReleaseRoot | Out-Null

Write-Host "Packaging Windows release" -ForegroundColor Cyan
Copy-Item -Recurse -Force -Path (Join-Path $windowsSource "*") -Destination $windowsReleaseRoot

$windowsZipPath = Join-Path $releaseRoot "mnemosyne-windows-$Version-$gitSha.zip"
if (Test-Path $windowsZipPath) {
  Remove-Item -LiteralPath $windowsZipPath -Force
}
Compress-Archive -Path (Join-Path $windowsReleaseRoot "*") -DestinationPath $windowsZipPath

Write-Host "Packaging Android APKs" -ForegroundColor Cyan
$androidDebugTarget = Join-Path $androidReleaseRoot "mnemosyne-android-debug-$Version-$gitSha.apk"
$androidReleaseTarget = Join-Path $androidReleaseRoot "mnemosyne-android-release-$Version-$gitSha.apk"
Copy-Item -Force $androidDebugApk $androidDebugTarget
Copy-Item -Force $androidReleaseApk $androidReleaseTarget

$manifest = [ordered]@{
  version = $Version
  gitSha = $gitSha
  packagedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
  artifacts = @(
    [ordered]@{
      platform = "windows"
      path = [System.IO.Path]::GetFileName($windowsZipPath)
      sha256 = Get-Sha256 -Path $windowsZipPath
    },
    [ordered]@{
      platform = "android-debug"
      path = "android/" + [System.IO.Path]::GetFileName($androidDebugTarget)
      sha256 = Get-Sha256 -Path $androidDebugTarget
    },
    [ordered]@{
      platform = "android-release"
      path = "android/" + [System.IO.Path]::GetFileName($androidReleaseTarget)
      sha256 = Get-Sha256 -Path $androidReleaseTarget
    }
  )
}
$manifest | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 (Join-Path $releaseRoot "release-manifest.json")

Write-Host ""
Write-Host "Release bundle ready:" -ForegroundColor Green
Write-Host "  $releaseRoot"
