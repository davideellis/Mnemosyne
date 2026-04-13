param(
  [string]$StackName = "Mnemosyne-tst",
  [string]$Profile = "Mnemosyne-tst",
  [string]$Region = "us-east-2",
  [string]$BootstrapEmail = "admin@mnemosyne.local",
  [string]$SmokeRemoteMacHost,
  [switch]$SkipSmoke
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$templatePath = Join-Path $repoRoot "infra/aws/cfn/mnemosyne-single-user.yaml"
$artifactPath = Join-Path $repoRoot "dist/sync_api_lambda/sync_api_lambda_arm64.zip"
$runSmokeScript = Join-Path $PSScriptRoot "run-tst-smoke.ps1"

$callerIdentity = aws sts get-caller-identity --profile $Profile --region $Region | ConvertFrom-Json
if ($callerIdentity.Account -ne "163649805194") {
  throw "Refusing to deploy test script outside account 163649805194. Current account: $($callerIdentity.Account)"
}

$artifactBucket = "mnemosyne-tst-artifacts-$($callerIdentity.Account)-$Region"
$timestamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddHHmmss")
$gitSha = (git rev-parse --short HEAD).Trim()
$artifactKey = "lambda/sync_api_lambda_${timestamp}_${gitSha}.zip"

& (Join-Path $PSScriptRoot "build-sync-api-lambda.ps1")

aws s3api head-bucket --bucket $artifactBucket --profile $Profile --region $Region 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
  Write-Host "Creating artifact bucket $artifactBucket"
  aws s3api create-bucket --bucket $artifactBucket --create-bucket-configuration LocationConstraint=$Region --profile $Profile --region $Region | Out-Null
}

Write-Host "Uploading Lambda artifact to s3://$artifactBucket/$artifactKey"
aws s3api put-object --bucket $artifactBucket --key $artifactKey --body $artifactPath --profile $Profile --region $Region | Out-Null

Write-Host "Deploying CloudFormation stack $StackName"
aws cloudformation deploy `
  --template-file $templatePath `
  --stack-name $StackName `
  --capabilities CAPABILITY_IAM `
  --parameter-overrides `
    ServiceName=mnemosyne-tst `
    BootstrapEmail=$BootstrapEmail `
    EnableHostedBootstrap=false `
    BuildSha=$gitSha `
    LambdaArtifactBucket=$artifactBucket `
    LambdaArtifactKey=$artifactKey `
  --profile $Profile `
  --region $Region `
  --no-fail-on-empty-changeset

$stack = aws cloudformation describe-stacks --stack-name $StackName --profile $Profile --region $Region | ConvertFrom-Json
$outputs = @{}
foreach ($output in $stack.Stacks[0].Outputs) {
  $outputs[$output.OutputKey] = $output.OutputValue
}

Write-Host "Stack outputs:"
$outputs.GetEnumerator() | Sort-Object Name | ForEach-Object {
  Write-Host "  $($_.Name): $($_.Value)"
}

if ($outputs.ContainsKey("ApiBaseUrl")) {
  $health = Invoke-RestMethod -Uri ($outputs["ApiBaseUrl"].TrimEnd("/") + "/healthz") -Method Get
  Write-Host "Health check: $($health.status)"
  if ($health.buildSha) {
    Write-Host "Deployed build SHA: $($health.buildSha)"
    if ($health.buildSha -ne $gitSha) {
      throw "Deployed build SHA $($health.buildSha) did not match expected $gitSha"
    }
  }
  if ($health.awsMode) {
    Write-Host "Runtime mode: $($health.awsMode)"
  }
}

if (-not $SkipSmoke) {
  $smokeEmail = if ($env:MNEMOSYNE_TST_EMAIL) {
    $env:MNEMOSYNE_TST_EMAIL
  } else {
    [Environment]::GetEnvironmentVariable("MNEMOSYNE_TST_EMAIL", "User")
  }
  $smokePassword = if ($env:MNEMOSYNE_TST_PASSWORD) {
    $env:MNEMOSYNE_TST_PASSWORD
  } else {
    [Environment]::GetEnvironmentVariable("MNEMOSYNE_TST_PASSWORD", "User")
  }

  if ([string]::IsNullOrWhiteSpace($smokeEmail) -or [string]::IsNullOrWhiteSpace($smokePassword)) {
    Write-Host "Skipping live smoke: MNEMOSYNE_TST_EMAIL / MNEMOSYNE_TST_PASSWORD are not configured." -ForegroundColor DarkYellow
  } else {
    Write-Host "Running live smoke verification" -ForegroundColor Cyan
    $smokeArgs = @(
      "-Profile", $Profile,
      "-Region", $Region,
      "-StackName", $StackName,
      "-Email", $smokeEmail,
      "-Password", $smokePassword
    )
    if (-not [string]::IsNullOrWhiteSpace($SmokeRemoteMacHost)) {
      $smokeArgs += @("-RemoteMacHost", $SmokeRemoteMacHost)
    }
    & $runSmokeScript @smokeArgs
    if ($LASTEXITCODE -ne 0) {
      throw "Live smoke verification failed after deploy."
    }
  }
}
