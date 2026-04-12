param(
  [string]$Email,
  [string]$Password,
  [string]$RecoveryKey,
  [string]$Profile = "Mnemosyne-tst",
  [string]$Region = "us-east-2",
  [string]$StackName = "Mnemosyne-tst",
  [string]$DeviceName = "Smoke Runner",
  [string]$DevicePlatform = "windows",
  [string]$ApprovalCode = "ABCD-EFGH-IJKL",
  [switch]$BootstrapOnly,
  [switch]$Bootstrap
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Email)) {
  $Email = if ($env:MNEMOSYNE_TST_EMAIL) {
    $env:MNEMOSYNE_TST_EMAIL
  } else {
    [Environment]::GetEnvironmentVariable("MNEMOSYNE_TST_EMAIL", "User")
  }
}
if ([string]::IsNullOrWhiteSpace($Password)) {
  $Password = if ($env:MNEMOSYNE_TST_PASSWORD) {
    $env:MNEMOSYNE_TST_PASSWORD
  } else {
    [Environment]::GetEnvironmentVariable("MNEMOSYNE_TST_PASSWORD", "User")
  }
}
if ([string]::IsNullOrWhiteSpace($RecoveryKey)) {
  $RecoveryKey = if ($env:MNEMOSYNE_TST_RECOVERY_KEY) {
    $env:MNEMOSYNE_TST_RECOVERY_KEY
  } else {
    [Environment]::GetEnvironmentVariable("MNEMOSYNE_TST_RECOVERY_KEY", "User")
  }
}
if ([string]::IsNullOrWhiteSpace($RecoveryKey)) {
  $RecoveryKey = "TEST-KEY1-TEST-KEY2"
}

if ([string]::IsNullOrWhiteSpace($Email)) {
  throw "Email is required. Pass -Email or set MNEMOSYNE_TST_EMAIL."
}
if ([string]::IsNullOrWhiteSpace($Password)) {
  throw "Password is required. Pass -Password or set MNEMOSYNE_TST_PASSWORD."
}

function Invoke-AwsJson {
  param(
    [Parameter(Mandatory = $true)][string[]]$Arguments
  )

  $raw = & aws @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "AWS command failed: aws $($Arguments -join ' ')"
  }
  return $raw | ConvertFrom-Json
}

function Get-StackOutputValue {
  param(
    [Parameter(Mandatory = $true)][object[]]$Outputs,
    [Parameter(Mandatory = $true)][string]$Key
  )

  $match = $Outputs | Where-Object { $_.OutputKey -eq $Key } | Select-Object -First 1
  if (-not $match) {
    throw "Missing stack output: $Key"
  }
  return $match.OutputValue
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$clientRoot = Join-Path $repoRoot "apps/client_flutter"
$flutterPath = (Get-Command flutter -ErrorAction SilentlyContinue).Source
if (-not $flutterPath) {
  $candidateFlutter = "C:\dev\flutter\bin\flutter.bat"
  if (Test-Path $candidateFlutter) {
    $flutterPath = $candidateFlutter
  }
}
if (-not $flutterPath) {
  throw "Unable to locate Flutter. Install Flutter or update scripts/run-tst-smoke.ps1 with the local path."
}

$stack = Invoke-AwsJson @(
  "--profile", $Profile,
  "--region", $Region,
  "cloudformation", "describe-stacks",
  "--stack-name", $StackName
)
$apiBaseUrl = Get-StackOutputValue -Outputs $stack.Stacks[0].Outputs -Key "ApiBaseUrl"

$args = @(
  "pub", "run", "tool/smoke_sync_api.dart",
  "--base-url", $apiBaseUrl,
  "--email", $Email,
  "--password", $Password,
  "--recovery-key", $RecoveryKey,
  "--device-name", $DeviceName,
  "--device-platform", $DevicePlatform,
  "--approval-code", $ApprovalCode
)

if ($Bootstrap -or $BootstrapOnly) {
  $args += "--bootstrap"
}
if (-not $BootstrapOnly) {
  $args += "--full"
}

Write-Host "Running Mnemosyne test smoke flow" -ForegroundColor Cyan
Write-Host "  Stack:      $StackName"
Write-Host "  API:        $apiBaseUrl"
Write-Host "  Device:     $DeviceName ($DevicePlatform)"
if ($Bootstrap -or $BootstrapOnly) {
  Write-Host "  Bootstrap:  enabled"
}

Push-Location $clientRoot
try {
  & $flutterPath @args
  if ($LASTEXITCODE -ne 0) {
    throw "Smoke command failed with exit code $LASTEXITCODE"
  }
}
finally {
  Pop-Location
}
