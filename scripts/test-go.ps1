param(
  [string]$Package = "./...",
  [string]$ServicePath = "services/sync_api",
  [string]$ExtraArgs = ""
)

$repoRoot = Split-Path -Parent $PSScriptRoot
$windowsServicePath = Join-Path $repoRoot $ServicePath

if (-not (Test-Path $windowsServicePath)) {
  throw "Service path not found: $windowsServicePath"
}

$linuxServicePath = wsl wslpath -a $windowsServicePath
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($linuxServicePath)) {
  throw "Unable to translate Windows path for WSL."
}

$linuxServicePath = $linuxServicePath.Trim()
$commandParts = @(
  "cd '$linuxServicePath'",
  "go test $Package"
)

if (-not [string]::IsNullOrWhiteSpace($ExtraArgs)) {
  $commandParts[1] = "$($commandParts[1]) $ExtraArgs"
}

$bashCommand = $commandParts -join " && "
Write-Host "Running in WSL: $bashCommand"
wsl bash -lc $bashCommand
exit $LASTEXITCODE
