# Mnemosyne Development Guide

This document is for implementation agents. Use it as the default build plan unless the repository later contains more specific instructions closer to the code.

## Current Phase

The repository is in planning/bootstrap stage.

Immediate goal:

- Establish a clean monorepo skeleton
- Lock the architecture choices from `ARCHITECTURE.md`
- Build the sync core and local vault behavior before polishing advanced UI

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

## AWS Guidance

CloudFormation MVP goals:

- One-command deployment experience as much as possible
- Single-account bootstrap
- Low monthly idle cost
- Clear outputs for API URL and bootstrap credentials flow

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
