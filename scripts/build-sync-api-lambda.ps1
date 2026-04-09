param(
  [string]$OutputDir = "dist/sync_api_lambda"
)

$repoRoot = Split-Path -Parent $PSScriptRoot
$servicePath = Join-Path $repoRoot "services/sync_api"
$outputPath = Join-Path $repoRoot $OutputDir
$bootstrapPath = Join-Path $outputPath "bootstrap"
$zipPath = Join-Path $outputPath "sync_api_lambda_arm64.zip"

New-Item -ItemType Directory -Force -Path $outputPath | Out-Null
if (Test-Path $bootstrapPath) { Remove-Item $bootstrapPath -Force }
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }

$linuxServicePath = (wsl wslpath -a $servicePath).Trim()
$linuxBootstrapPath = (wsl wslpath -a $bootstrapPath).Trim()

$buildCommand = "cd '$linuxServicePath' && GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -o '$linuxBootstrapPath' ./cmd/lambda"
Write-Host "Running in WSL: $buildCommand"
wsl bash -lc $buildCommand
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Compress-Archive -Path $bootstrapPath -DestinationPath $zipPath -Force
Write-Host "Built Lambda artifact: $zipPath"
