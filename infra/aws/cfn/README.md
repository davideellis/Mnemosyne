# AWS Deployment Notes

This folder contains the first-pass CloudFormation template for the Mnemosyne MVP.

## Template

- `mnemosyne-single-user.yaml`

## Deployment Intent

The template is designed for one person running their own encrypted sync service on AWS with minimal operational surface area.

Created resources:

- S3 bucket for encrypted blobs
- DynamoDB table for metadata
- Lambda function for the sync API
- API Gateway HTTP API
- IAM role and invoke permissions

Operational defaults now included:

- S3 bucket versioning enabled for encrypted payload objects
- S3 lifecycle rule to abort incomplete multipart uploads after 7 days
- DynamoDB point-in-time recovery enabled for metadata state

## Current Status

The stack now deploys a packaged Go Lambda, API Gateway, DynamoDB, and S3 for the test environment.

What is validated today:

1. Lambda packaging from the repository
2. Repeatable deployment to `Mnemosyne-tst`
3. Health checks against the deployed API
4. Single-account bootstrap, login, encrypted push, and encrypted pull smoke-tested against the test stack
5. Encrypted payload bodies can be written to the notes S3 bucket while sync state remains in DynamoDB
6. The stack can be exported locally with `.\scripts\backup-tst.ps1`

What still needs hardening before production:

1. Expand the current S3-backed payload path beyond the single-state prototype into a fuller object-manifest model
2. Add alarms and fuller operational runbooks
3. Add deployment safety for production promotion
4. Validate recovery and device-provisioning flows end to end

## Backup Workflow

Use `.\scripts\backup-tst.ps1` from the repository root to export:

- the current DynamoDB state item
- the encrypted notes bucket contents
- a small manifest with bucket versioning and PITR status

The script writes to `dist/backups/<stack>/<timestamp>`.

This is an operator convenience export, not a complete disaster-recovery system. Restoring from it is still a manual process today.
