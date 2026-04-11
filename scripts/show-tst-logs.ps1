param(
  [string]$Profile = "Mnemosyne-tst",
  [string]$Region = "us-east-2",
  [string]$ServiceName = "mnemosyne-tst",
  [int]$Minutes = 30,
  [int]$Limit = 100
)

$ErrorActionPreference = "Stop"

$logGroupName = "/aws/lambda/$ServiceName-sync-api"
$startTime = [DateTimeOffset]::UtcNow.AddMinutes(-1 * $Minutes).ToUnixTimeMilliseconds()

Write-Host "Fetching recent logs from $logGroupName" -ForegroundColor Cyan

$response = & aws `
  --profile $Profile `
  --region $Region `
  logs filter-log-events `
  --log-group-name $logGroupName `
  --start-time $startTime `
  --limit $Limit

if ($LASTEXITCODE -ne 0) {
  throw "Failed to fetch logs from $logGroupName"
}

$parsed = $response | ConvertFrom-Json
foreach ($event in ($parsed.events | Select-Object -Last $Limit)) {
  $timestamp = [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$event.timestamp).ToLocalTime().ToString("yyyy-MM-dd HH:mm:ss")
  Write-Host "[$timestamp] $($event.message)"
}
