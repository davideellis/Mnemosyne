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

## Current Status

The stack now deploys a packaged Go Lambda, API Gateway, DynamoDB, and S3 for the test environment.

What is validated today:

1. Lambda packaging from the repository
2. Repeatable deployment to `Mnemosyne-tst`
3. Health checks against the deployed API
4. Single-account bootstrap, login, encrypted push, and encrypted pull smoke-tested against the test stack
5. Encrypted payload bodies can be written to the notes S3 bucket while sync state remains in DynamoDB

What still needs hardening before production:

1. Expand the current S3-backed payload path beyond the single-state prototype into a fuller object-manifest model
2. Add alarms, backups, and operational runbooks
3. Add deployment safety for production promotion
4. Validate recovery and device-provisioning flows end to end
