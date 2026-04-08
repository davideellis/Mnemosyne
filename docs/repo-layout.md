# Repository Layout

## Current Structure

- `apps/client_flutter`: cross-platform client application shell
- `crates/core_sync`: Rust domain and sync core
- `services/sync_api`: Go API service for encrypted sync
- `infra/aws/cfn`: CloudFormation templates and parameter docs
- `docs`: protocol and repository documentation

## Intent

This repository is being built as a monorepo so the sync contract, product docs, and deployment artifacts evolve together.
