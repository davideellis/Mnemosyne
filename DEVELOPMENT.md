# Mnemosyne Development Guide

This document is for implementation agents. Use it as the default build plan unless the repository later contains more specific instructions closer to the code.

## Current Phase

The repository is in active implementation with a working test deployment path.

Immediate goal:

- Harden the encrypted sync path across client, API, and AWS test infrastructure
- Keep the deployed `Mnemosyne-tst` stack aligned with the local codebase
- Move backend storage closer to the intended DynamoDB-plus-S3 model before production work

## Priority Order

Build in this order:

1. Repository scaffold and tooling
2. Rust core for local vault indexing, file watching, and sync state
3. Cryptography and recovery-key flows
4. Go sync API with encrypted object storage contract
5. AWS CloudFormation stack for single-account self-hosting
6. Flutter client shell with account setup, vault selection, editor, preview, and sync status
7. Tags, wikilinks, backlinks, and graph view
8. Settings sync

## Implementation Rules

- Preserve the local-first model at all times
- `.md` files in the chosen folder are the user data contract
- Never require note parsing features that rewrite note bodies into a proprietary format
- Ignore non-Markdown files in MVP
- Treat delete as synced trash, not immediate destruction
- Keep the server blind to note contents
- Keep sync transport small and purpose-built
- Prefer explicit state machines over hidden sync heuristics

## Client Guidance

Recommended baseline:

- Flutter stable channel
- Dart package boundaries for UI, local app services, and FFI bindings
- Rust core exposed with `flutter_rust_bridge`

Client MVP screens:

- First-run onboarding
- Sign-in / bootstrap account
- Recovery key setup and confirmation
- Vault folder selection
- Note list and folder tree
- Editor and preview
- Search
- Backlinks
- Graph view
- Settings
- Trash

Client UX requirements:

- Full offline usability
- Minimal sync state indicators only
- Automatic background sync plus manual sync action
- External file changes reflected without app restart

## Rust Core Guidance

Suggested modules:

- `vault_scan`
- `fs_watch`
- `note_index`
- `link_index`
- `sync_engine`
- `crypto`
- `device_auth`
- `settings_sync`
- `trash_state`

Suggested local persistence:

- SQLite for local metadata, indexes, sync cursors, and cached graph state

Important behavior:

- File rename and move detection must be stable
- Last-write-wins must be deterministic
- Sync engine must handle offline replay cleanly

## Go API Guidance

Suggested packages:

- `auth`
- `devices`
- `manifests`
- `objects`
- `trash`
- `settings`
- `middleware`

API design principles:

- Version routes from day one
- Keep endpoints coarse enough to reduce chattiness
- Use opaque IDs instead of path-derived storage keys
- Keep request/response shapes stable and documented
- Make local development runnable without AWS where practical

Windows note:

- Windows Smart App Control can block unsigned Go test executables
- On this machine, prefer running Go tests through WSL instead of disabling Smart App Control
- Use `.\scripts\test-go.ps1` from the repo root for the default backend test path
- Android builds on this machine expect `JAVA_HOME` to point at Android Studio's bundled JBR
- Use `.\scripts\build-client-artifacts.ps1` from the repo root for the standard Windows + Android build pass
- Add `-IncludeApple` to the same script to also drive the Mac mini for macOS and iOS simulator artifacts

## AWS Guidance

CloudFormation MVP goals:

- One-command deployment experience as much as possible
- Single-account bootstrap
- Low monthly idle cost
- Clear outputs for API URL and bootstrap credentials flow

Current test deployment workflow on this machine:

- Use `.\scripts\deploy-tst.ps1` from the repo root
- The script is intentionally hard-scoped to AWS account `163649805194`
- It builds the Lambda artifact, uploads it under a fresh S3 key, deploys `Mnemosyne-tst`, and runs a `/healthz` smoke check
- Use `flutter pub run tool/smoke_sync_api.dart --base-url <api> --email <email> --password <password>` from `apps/client_flutter` for an encrypted login/push/pull smoke test
- The smoke runner also supports `--device-name`, `--device-platform`, `--list-devices`, `--start-approval`, `--consume-approval`, and `--revoke-device --target-device-id <id>`
- Do not point this script at production; keep production changes manual until the test path is stable

Document at least:

- Required AWS services
- Required parameters
- Upgrade strategy
- Backup expectations
- Disaster recovery limitations

## Testing Priorities

Test these early:

1. External file edit detection
2. Rename and move synchronization
3. Delete-to-trash synchronization
4. Offline edits on multiple devices with last-write-wins resolution
5. New-device provisioning with recovery key
6. Existing-device approval flow
7. Settings sync convergence
8. Server inability to decrypt note contents

## Documentation Rules

- Public-facing docs must not mention comparison products
- Keep claims aligned with implemented behavior
- Document limitations clearly, especially around recovery-key loss and last-write-wins
