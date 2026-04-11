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

$stack = Invoke-AwsJson @(
  "--profile", $Profile,
  "--region", $Region,
  "cloudformation", "describe-stacks",
  "--stack-name", $StackName
)
$outputs = $stack.Stacks[0].Outputs
$apiBaseUrl = Get-StackOutputValue -Outputs $outputs -Key "ApiBaseUrl"
$lambdaAlarmName = Get-StackOutputValue -Outputs $outputs -Key "SyncApiErrorsAlarmName"
$apiAlarmName = Get-StackOutputValue -Outputs $outputs -Key "HttpApiServerErrorsAlarmName"

$health = Invoke-RestMethod -Uri "$apiBaseUrl/healthz" -Method Get
$alarms = Invoke-AwsJson @(
  "--profile", $Profile,
  "--region", $Region,
  "cloudwatch", "describe-alarms",
  "--alarm-names", $lambdaAlarmName, $apiAlarmName
)

Write-Host "Mnemosyne Test Stack Health" -ForegroundColor Cyan
Write-Host "  Stack:      $StackName"
Write-Host "  API:        $apiBaseUrl"
Write-Host "  Status:     $($health.status)"
Write-Host "  Build SHA:  $($health.buildSha)"
Write-Host "  Runtime:    $($health.awsMode)"
Write-Host ""
Write-Host "Alarm States" -ForegroundColor Cyan
foreach ($alarm in $alarms.MetricAlarms) {
  Write-Host "  $($alarm.AlarmName): $($alarm.StateValue)"
}
