param(
  [Parameter(Mandatory = $true)][string]$Email,
  [Parameter(Mandatory = $true)][string]$Password,
  [string]$RecoveryKey = "TEST-KEY1-TEST-KEY2",
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
