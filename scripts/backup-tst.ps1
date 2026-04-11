param(
  [string]$Profile = "Mnemosyne-tst",
  [string]$Region = "us-east-2",
  [string]$StackName = "Mnemosyne-tst",
  [string]$OutputRoot = ".\dist\backups"
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

function Get-SafeObjectFileName {
  param(
    [Parameter(Mandatory = $true)][string]$Key
  )

  $sha256 = [System.Security.Cryptography.SHA256]::Create()
  try {
    $hashBytes = $sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Key))
  }
  finally {
    $sha256.Dispose()
  }

  $hash = [System.BitConverter]::ToString($hashBytes).Replace("-", "").ToLowerInvariant()

  $extension = [System.IO.Path]::GetExtension($Key)
  if ([string]::IsNullOrWhiteSpace($extension)) {
    return $hash
  }
  return "$hash$extension"
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

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backupRoot = Join-Path $OutputRoot "$StackName\$timestamp"
$notesPath = Join-Path $backupRoot "notes-bucket"
$metadataPath = Join-Path $backupRoot "metadata"
$stateKeyPath = Join-Path $metadataPath "state-key.json"

New-Item -ItemType Directory -Force -Path $notesPath | Out-Null
New-Item -ItemType Directory -Force -Path $metadataPath | Out-Null

([ordered]@{
  PK = @{ S = "STATE" }
  SK = @{ S = "STATE" }
} | ConvertTo-Json -Depth 5) | ForEach-Object {
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($stateKeyPath, $_, $utf8NoBom)
}

Write-Host "Exporting DynamoDB state item from $tableName" -ForegroundColor Cyan
$stateItem = Invoke-AwsJson @(
  "--profile", $Profile,
  "--region", $Region,
  "dynamodb", "get-item",
  "--table-name", $tableName,
  "--key", "file://$stateKeyPath"
)
$stateItem | ConvertTo-Json -Depth 100 | Set-Content -Encoding UTF8 (Join-Path $metadataPath "state-item.json")

Write-Host "Exporting S3 objects from $bucketName" -ForegroundColor Cyan
$token = $null
$exportedObjects = @()
do {
  $arguments = @(
    "--profile", $Profile,
    "--region", $Region,
    "s3api", "list-objects-v2",
    "--bucket", $bucketName
  )
  if ($token) {
    $arguments += @("--continuation-token", $token)
  }

  $page = Invoke-AwsJson -Arguments $arguments
  foreach ($object in ($page.Contents | Where-Object { $_.Key })) {
    $safeName = Get-SafeObjectFileName -Key $object.Key
    $targetPath = Join-Path $notesPath $safeName
    & aws --profile $Profile --region $Region s3api get-object `
      --bucket $bucketName `
      --key $object.Key `
      $targetPath | Out-Null
    if ($LASTEXITCODE -ne 0) {
      throw "Failed to export s3://$bucketName/$($object.Key)"
    }
    $exportedObjects += [ordered]@{
      key = $object.Key
      size = $object.Size
      lastModified = $object.LastModified
      localFile = "notes-bucket/$safeName"
    }
  }

  $token = $page.NextContinuationToken
} while ($token)

$exportedObjects | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 (Join-Path $backupRoot "objects-manifest.json")

if ($exportedObjects.Count -eq 0) {
  Write-Host "  No note payload objects found." -ForegroundColor DarkYellow
}

$bucketVersioning = Invoke-AwsJson @(
  "--profile", $Profile,
  "--region", $Region,
  "s3api", "get-bucket-versioning",
  "--bucket", $bucketName
)
$continuousBackups = Invoke-AwsJson @(
  "--profile", $Profile,
  "--region", $Region,
  "dynamodb", "describe-continuous-backups",
  "--table-name", $tableName
)

$manifest = [ordered]@{
  stackName = $StackName
  profile = $Profile
  region = $Region
  exportedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
  bucketName = $bucketName
  metadataTableName = $tableName
  noteObjectCount = $exportedObjects.Count
  bucketVersioning = $bucketVersioning.Status
  pointInTimeRecovery = $continuousBackups.ContinuousBackupsDescription.PointInTimeRecoveryDescription.PointInTimeRecoveryStatus
}
$manifest | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 (Join-Path $backupRoot "backup-manifest.json")

Write-Host ""
Write-Host "Backup complete:" -ForegroundColor Green
Write-Host "  $backupRoot"
