param(
  [Parameter(Mandatory = $true)][string]$BackupPath,
  [string]$Profile = "Mnemosyne-tst",
  [string]$Region = "us-east-2",
  [string]$StackName = "Mnemosyne-tst",
  [switch]$Apply
)

$ErrorActionPreference = "Stop"

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

$resolvedBackupPath = (Resolve-Path $BackupPath).Path
$manifestPath = Join-Path $resolvedBackupPath "backup-manifest.json"
$objectsManifestPath = Join-Path $resolvedBackupPath "objects-manifest.json"
$stateItemPath = Join-Path $resolvedBackupPath "metadata\state-item.json"

foreach ($requiredPath in @($manifestPath, $objectsManifestPath, $stateItemPath)) {
  if (-not (Test-Path $requiredPath)) {
    throw "Missing backup file: $requiredPath"
  }
}

$manifest = Get-Content $manifestPath | ConvertFrom-Json
if ($manifest.stackName -ne $StackName) {
  throw "Backup stack $($manifest.stackName) does not match target stack $StackName"
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

$objects = Get-Content $objectsManifestPath | ConvertFrom-Json
$stateItemJson = Get-Content $stateItemPath -Raw

Write-Host "Restore plan for $StackName" -ForegroundColor Cyan
Write-Host "  Backup:  $resolvedBackupPath"
Write-Host "  Bucket:  $bucketName"
Write-Host "  Table:   $tableName"
Write-Host "  Objects: $($objects.Count)"
Write-Host "  Mode:    $(if ($Apply) { 'APPLY' } else { 'DRY RUN' })"

if (-not $Apply) {
  Write-Host ""
  Write-Host "No changes applied. Re-run with -Apply to restore this backup into the test stack." -ForegroundColor Yellow
  return
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$tempDir = Join-Path $env:TEMP "mnemosyne_restore_$([Guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

try {
  $stateItemTarget = Join-Path $tempDir "state-item.json"
  [System.IO.File]::WriteAllText($stateItemTarget, $stateItemJson, $utf8NoBom)

  Write-Host "Restoring metadata state item" -ForegroundColor Cyan
  & aws --profile $Profile --region $Region dynamodb put-item `
    --table-name $tableName `
    --item "file://$stateItemTarget" | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to restore DynamoDB state item"
  }

  Write-Host "Restoring encrypted payload objects" -ForegroundColor Cyan
  foreach ($object in $objects) {
    $localPath = Join-Path $resolvedBackupPath $object.localFile
    if (-not (Test-Path $localPath)) {
      throw "Missing local object payload: $localPath"
    }

    & aws --profile $Profile --region $Region s3api put-object `
      --bucket $bucketName `
      --key $object.key `
      --body $localPath | Out-Null
    if ($LASTEXITCODE -ne 0) {
      throw "Failed to restore s3://$bucketName/$($object.key)"
    }
  }
}
finally {
  if (Test-Path $tempDir) {
    Remove-Item -LiteralPath $tempDir -Recurse -Force
  }
}

Write-Host ""
Write-Host "Restore complete." -ForegroundColor Green
