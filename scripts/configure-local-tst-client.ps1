param(
  [string]$Profile = "Mnemosyne-tst",
  [string]$Region = "us-east-2",
  [string]$StackName = "Mnemosyne-tst"
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

$email = [Environment]::GetEnvironmentVariable("MNEMOSYNE_TST_EMAIL", "User")
$password = [Environment]::GetEnvironmentVariable("MNEMOSYNE_TST_PASSWORD", "User")
$recoveryKey = [Environment]::GetEnvironmentVariable("MNEMOSYNE_TST_RECOVERY_KEY", "User")

if ([string]::IsNullOrWhiteSpace($email)) {
  throw "Missing user environment variable MNEMOSYNE_TST_EMAIL."
}
if ([string]::IsNullOrWhiteSpace($password)) {
  throw "Missing user environment variable MNEMOSYNE_TST_PASSWORD."
}
if ([string]::IsNullOrWhiteSpace($recoveryKey)) {
  throw "Missing user environment variable MNEMOSYNE_TST_RECOVERY_KEY."
}

$stack = Invoke-AwsJson @(
  "--profile", $Profile,
  "--region", $Region,
  "cloudformation", "describe-stacks",
  "--stack-name", $StackName
)

$apiBaseUrl = Get-StackOutputValue -Outputs $stack.Stacks[0].Outputs -Key "ApiBaseUrl"
[Environment]::SetEnvironmentVariable("MNEMOSYNE_TST_API_BASE_URL", $apiBaseUrl, "User")
[Environment]::SetEnvironmentVariable("MNEMOSYNE_SYNC_API_URL", $apiBaseUrl, "User")
[Environment]::SetEnvironmentVariable("MNEMOSYNE_SYNC_EMAIL", $email, "User")
[Environment]::SetEnvironmentVariable("MNEMOSYNE_SYNC_PASSWORD", $password, "User")

$appStatePath = Join-Path $env:USERPROFILE ".mnemosyne\app_state.json"
$appStateDirectory = Split-Path -Parent $appStatePath
if (-not (Test-Path $appStateDirectory)) {
  New-Item -ItemType Directory -Path $appStateDirectory -Force | Out-Null
}

$state = @{}
if (Test-Path $appStatePath) {
  $stateObject = Get-Content -Path $appStatePath -Raw | ConvertFrom-Json
  foreach ($property in $stateObject.PSObject.Properties) {
    $state[$property.Name] = $property.Value
  }
}

$state["apiBaseUrl"] = $apiBaseUrl
$state["email"] = $email

$state | ConvertTo-Json -Depth 8 | Set-Content -Path $appStatePath -Encoding utf8

Write-Host "Configured the local client for Mnemosyne-tst." -ForegroundColor Green
Write-Host "  API:   $apiBaseUrl"
Write-Host "  Email: $email"
Write-Host ""
Write-Host "The desktop app will now prefill the live test-stack endpoint and account on this machine."
