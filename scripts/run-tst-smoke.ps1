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
  [string]$RemoteMacHost,
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

function Test-UsableFlutter {
  param(
    [string]$Path
  )

  if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path $Path)) {
    return $false
  }

  try {
    & $Path --version *> $null
    return $LASTEXITCODE -eq 0
  }
  catch {
    return $false
  }
}

function Invoke-RemoteMacSmoke {
  param(
    [Parameter(Mandatory = $true)][string]$Host,
    [Parameter(Mandatory = $true)][string]$ApiBaseUrl,
    [Parameter(Mandatory = $true)][string]$Email,
    [Parameter(Mandatory = $true)][string]$Password,
    [Parameter(Mandatory = $true)][string]$RecoveryKey,
    [Parameter(Mandatory = $true)][string]$DeviceName,
    [Parameter(Mandatory = $true)][string]$DevicePlatform,
    [Parameter(Mandatory = $true)][string]$ApprovalCode,
    [Parameter(Mandatory = $false)][bool]$BootstrapEnabled,
    [Parameter(Mandatory = $false)][bool]$BootstrapOnlyEnabled
  )

  $escapedBaseUrl = $ApiBaseUrl.Replace("'", "'\''")
  $escapedEmail = $Email.Replace("'", "'\''")
  $escapedPassword = $Password.Replace("'", "'\''")
  $escapedRecoveryKey = $RecoveryKey.Replace("'", "'\''")
  $escapedDeviceName = $DeviceName.Replace("'", "'\''")
  $escapedDevicePlatform = $DevicePlatform.Replace("'", "'\''")
  $escapedApprovalCode = $ApprovalCode.Replace("'", "'\''")

  $remoteArgs = @(
    "pub run tool/smoke_sync_api.dart",
    "--base-url '$escapedBaseUrl'",
    "--email '$escapedEmail'",
    "--password '$escapedPassword'",
    "--recovery-key '$escapedRecoveryKey'",
    "--device-name '$escapedDeviceName'",
    "--device-platform '$escapedDevicePlatform'",
    "--approval-code '$escapedApprovalCode'"
  )
  if ($BootstrapEnabled) {
    $remoteArgs += "--bootstrap"
  }
  if (-not $BootstrapOnlyEnabled) {
    $remoteArgs += "--full"
  }
  $remoteSmokeCommand = "~/dev/flutter/bin/flutter $($remoteArgs -join ' ')"

  $remoteCommand = @"
export PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:`$HOME/dev/flutter/bin:`$PATH
export LANG=en_US.UTF-8
cd ~/dev/Mnemosyne/apps/client_flutter
$remoteSmokeCommand
"@

  & ssh $Host $remoteCommand
  if ($LASTEXITCODE -ne 0) {
    throw "Remote smoke command failed on $Host with exit code $LASTEXITCODE"
  }
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
$localFlutterUsable = Test-UsableFlutter -Path $flutterPath

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
if (-not $localFlutterUsable -and -not [string]::IsNullOrWhiteSpace($RemoteMacHost)) {
  Write-Host "  Runner:     remote via $RemoteMacHost" -ForegroundColor Yellow
}

if (-not $localFlutterUsable) {
  if ([string]::IsNullOrWhiteSpace($RemoteMacHost)) {
    throw "Local Flutter is unavailable or blocked. Pass -RemoteMacHost <ssh-host> to run the smoke flow on the Mac mini."
  }

  Invoke-RemoteMacSmoke `
    -Host $RemoteMacHost `
    -ApiBaseUrl $apiBaseUrl `
    -Email $Email `
    -Password $Password `
    -RecoveryKey $RecoveryKey `
    -DeviceName $DeviceName `
    -DevicePlatform $DevicePlatform `
    -ApprovalCode $ApprovalCode `
    -BootstrapEnabled $Bootstrap.IsPresent `
    -BootstrapOnlyEnabled $BootstrapOnly.IsPresent
  return
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
