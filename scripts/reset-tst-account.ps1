param(
  [string]$Email,
  [string]$Password,
  [string]$RecoveryKey,
  [string]$Profile = "Mnemosyne-tst",
  [string]$Region = "us-east-2",
  [string]$StackName = "Mnemosyne-tst",
  [switch]$SkipBackup
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

if ([string]::IsNullOrWhiteSpace($Email)) {
  throw "Email is required. Pass -Email or set MNEMOSYNE_TST_EMAIL."
}
if ([string]::IsNullOrWhiteSpace($Password)) {
  throw "Password is required. Pass -Password or set MNEMOSYNE_TST_PASSWORD."
}
if ([string]::IsNullOrWhiteSpace($RecoveryKey)) {
  throw "Recovery key is required. Pass -RecoveryKey or set MNEMOSYNE_TST_RECOVERY_KEY."
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

Write-Host "Resetting Mnemosyne test account" -ForegroundColor Cyan
Write-Host "  Stack:   $StackName"
Write-Host "  Profile: $Profile"
Write-Host "  Region:  $Region"
Write-Host "  Email:   $Email"

if (-not $SkipBackup) {
  & (Join-Path $PSScriptRoot "backup-tst.ps1") -Profile $Profile -Region $Region -StackName $StackName
  if ($LASTEXITCODE -ne 0) {
    throw "Backup failed; aborting reset."
  }
}

$stack = Invoke-AwsJson @(
  "--profile", $Profile,
  "--region", $Region,
  "cloudformation", "describe-stacks",
  "--stack-name", $StackName
)
$outputs = $stack.Stacks[0].Outputs
$bucketName = Get-StackOutputValue -Outputs $outputs -Key "BucketName"
$tableName = Get-StackOutputValue -Outputs $outputs -Key "MetadataTableName"

$keyPath = Join-Path $repoRoot "dist\mnemosyne_tst_state_key.json"
@'
{"PK":{"S":"STATE"},"SK":{"S":"STATE"}}
'@ | Out-File -FilePath $keyPath -Encoding ascii -Force

try {
  Write-Host "Deleting DynamoDB state item" -ForegroundColor Cyan
  & aws dynamodb delete-item `
    --table-name $tableName `
    --key "file://$keyPath" `
    --profile $Profile `
    --region $Region | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to delete state item from $tableName"
  }
}
finally {
  if (Test-Path $keyPath) {
    Remove-Item -LiteralPath $keyPath -Force -ErrorAction SilentlyContinue
  }
}

Write-Host "Purging versioned payload objects from $bucketName" -ForegroundColor Cyan
$versions = Invoke-AwsJson @(
  "--profile", $Profile,
  "--region", $Region,
  "s3api", "list-object-versions",
  "--bucket", $bucketName
)
foreach ($entry in @($versions.Versions) + @($versions.DeleteMarkers)) {
  if ($null -eq $entry -or -not $entry.Key -or -not $entry.VersionId) {
    continue
  }
  & aws s3api delete-object `
    --bucket $bucketName `
    --key $entry.Key `
    --version-id $entry.VersionId `
    --profile $Profile `
    --region $Region | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to delete s3://$bucketName/$($entry.Key) version $($entry.VersionId)"
  }
}

Write-Host "Re-bootstrapping the test account" -ForegroundColor Cyan
& (Join-Path $PSScriptRoot "run-tst-smoke.ps1") `
  -Email $Email `
  -Password $Password `
  -RecoveryKey $RecoveryKey `
  -Profile $Profile `
  -Region $Region `
  -StackName $StackName `
  -Bootstrap
if ($LASTEXITCODE -ne 0) {
  throw "Smoke bootstrap failed after reset."
}

Write-Host ""
Write-Host "Test account reset complete." -ForegroundColor Green
