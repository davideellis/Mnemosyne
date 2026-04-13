# Mnemosyne Release Runbook

This runbook is for maintainers preparing a test deployment or a release candidate.

## Test Stack Workflow

Use the AWS test account only:

- Account: `163649805194`
- Profile: `Mnemosyne-tst`
- Region: `us-east-2`
- Stack: `Mnemosyne-tst`

Recommended order:

1. Deploy the backend and infrastructure update.
2. Check stack health and alarms.
3. Run encrypted smoke coverage against the live API.
4. Export a backup after meaningful state changes.
5. Build and package client artifacts.

## Deploy

From the repo root:

```powershell
.\scripts\deploy-tst.ps1
```

What it does:

- builds the Lambda artifact
- uploads it to the test artifact bucket
- deploys the CloudFormation stack
- verifies `/healthz`
- runs the full live smoke pass automatically when local `MNEMOSYNE_TST_*` credentials are available

To skip the smoke step intentionally:

```powershell
.\scripts\deploy-tst.ps1 -SkipSmoke
```

## Health Check

From the repo root:

```powershell
.\scripts\check-tst-health.ps1
```

This verifies:

- API base URL reachability
- reported build SHA
- runtime mode
- CloudWatch alarm state for Lambda errors and HTTP 5xx

If more detail is needed:

```powershell
.\scripts\show-tst-logs.ps1
```

## Live Smoke

Quick smoke directly from the Flutter client workspace:

```powershell
cd apps\client_flutter
flutter pub run tool/smoke_sync_api.dart --base-url <api> --email <email> --password <password>
```

Broader test-stack smoke from the repo root:

```powershell
.\scripts\run-tst-smoke.ps1 -Email <email> -Password <password>
```

On this workstation, the wrapper can also use user-scoped environment variables:

- `MNEMOSYNE_TST_EMAIL`
- `MNEMOSYNE_TST_PASSWORD`
- `MNEMOSYNE_TST_RECOVERY_KEY`

Useful smoke runner modes:

- `--full` for note sync, settings sync, trash restore, approval, and revoke
- `--trash-restore` for synced trash recovery only
- `--approval-roundtrip` for device approval and revocation only
- `--list-devices` to inspect registered devices

To intentionally reset the single-user test account and immediately re-bootstrap it:

```powershell
.\scripts\reset-tst-account.ps1
```

That script:

- takes a backup first by default
- deletes the single DynamoDB state record
- purges versioned payload objects from the `tst` bucket
- re-bootstraps the account using the local `MNEMOSYNE_TST_*` credentials
- runs the full smoke flow after reset

Current local setup:

- the single-user `tst` account has been reset and re-bootstrapped successfully
- live full smoke passes when the local `MNEMOSYNE_TST_*` environment variables are present
- the credentials are intentionally machine-local and are not stored in the public repository

## Backup And Restore

Export a backup:

```powershell
.\scripts\backup-tst.ps1
```

Preview a restore plan:

```powershell
.\scripts\restore-tst-backup.ps1 -BackupPath <path>
```

What is protected today:

- encrypted note payload objects in S3
- sync metadata in DynamoDB
- S3 versioning
- DynamoDB point-in-time recovery

## Client Packaging

Build client artifacts:

```powershell
.\scripts\build-client-artifacts.ps1
```

Package the release bundle:

```powershell
.\scripts\package-release-artifacts.ps1
```

Current platform reality:

- Windows builds work, but signed distribution is blocked on code-signing certificates
- Android debug and release APK builds work
- macOS release builds work on the Mac mini
- iOS simulator and unsigned release builds work on the Mac mini
- signed Apple distribution is blocked on developer signing and provisioning

## Release Gate

Before calling a build release-ready, confirm:

- `flutter analyze`
- `flutter test`
- `go test ./...`
- test stack deploy succeeds
- `/healthz` matches the expected build SHA
- live smoke passes with valid test credentials
- backup export succeeds
- release bundle generation succeeds

## Do Not Use Production Yet

`Mnemosyne-prd` must remain untouched until:

- the `tst` smoke path is stable and repeatable
- known-good smoke credentials are documented
- release signing blockers are resolved or explicitly waived
