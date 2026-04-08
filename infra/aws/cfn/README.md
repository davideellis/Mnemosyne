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

This is infrastructure scaffolding, not a production-ready deployment yet.

Before deploying to AWS for real, the following needs to happen:

1. Replace the inline Lambda placeholder with the built Go binary artifact.
2. Wire the Go API to DynamoDB and S3.
3. Add alarms, backups, and deployment packaging.
4. Validate the bootstrap flow for the single-account self-hosted mode.
