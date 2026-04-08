# Mnemosyne Architecture

This document is for implementation agents. It describes the target MVP architecture and the product constraints that must not drift during early development.

## Product Contract

- Product name: `Mnemosyne`
- Audience: one person syncing their own notes across personal devices
- Supported platforms: iOS, macOS, Windows, Android
- Local storage model: plain `.md` files in a user-chosen folder
- Folder model: folders and subfolders are part of the synced state
- External file edits: supported and auto-detected
- Conflict rule: last write wins
- Delete rule: synced trash, not hard delete
- Version history: not part of MVP beyond trash
- Search: local search only
- Advanced content: tags, wikilinks, backlinks, local graph view
- Attachments: out of scope
- Plugins: out of scope
- Collaboration: out of scope

## Security Contract

- Sync is end-to-end encrypted
- Operators and admins cannot read note contents
- Hosted service password reset cannot recover note contents without the recovery key
- Recovery key is the only recovery path for encrypted data
- Self-hosted operators must also be unable to decrypt user note contents

## Recommended Stack

### Client

- Flutter application shell for iOS, macOS, Windows, and Android
- Rust shared core exposed to Flutter through `flutter_rust_bridge`

Use Flutter for:

- Windowing and app lifecycle
- Navigation and screens
- Editor and preview surfaces
- Command palette
- Settings UI
- Graph view rendering
- Sync status UI

Use Rust for:

- Vault indexing
- Filesystem watching
- Markdown file inventory and path mapping
- Sync state machine
- End-to-end encryption primitives
- Device provisioning logic
- Local backlink and graph index generation
- Settings serialization and sync payload construction

### Server

- Go server with a custom HTTPS JSON API
- Keep the API intentionally small and purpose-built for encrypted sync

Server responsibilities:

- Account and session handling
- Device registration and revocation
- Encrypted payload storage and retrieval
- Metadata manifest storage
- Synced trash metadata
- Settings payload sync
- Rate limiting and request validation

Server non-responsibilities:

- Rendering Markdown
- Indexing note text for search
- Decrypting note contents
- Merging note contents

## Sync Model

### Source of Truth

- The user-chosen local folder is the canonical note store on each device
- The remote service stores encrypted sync state, not plaintext notes

### Tracked Item Types

- Note files: `.md` only
- Folder paths
- Trash entries
- Settings blob
- Device metadata

Ignore all non-Markdown files for MVP.

### Event Types

- Create note
- Update note content
- Rename note
- Move note
- Delete note to trash
- Restore from trash
- Create folder
- Rename folder
- Move folder
- Delete folder
- Update settings

### Conflict Rule

- Last write wins at the note object level
- When two devices edit before sync convergence, the latest accepted update replaces the prior version
- Do not attempt content merge in MVP

This rule is intentionally simple for the first release. If later revisions add more advanced conflict handling, the MVP contract must still be preserved for backward compatibility.

## Encryption Model

### Keys

- User password is not the long-term content key
- Generate a vault master key on account creation
- Encrypt the vault master key with a key-encryption key derived from the user password
- Also encrypt the vault master key with material derived from the recovery key

### Storage Expectations

- Note bodies are encrypted before upload
- Settings payloads are encrypted before upload
- Metadata should reveal as little as possible while still allowing sync to function
- The server may need limited non-content metadata such as opaque object IDs, timestamps, and device IDs

### New Device Provisioning

Allow both flows:

- Sign in with credentials and recovery key
- Approve and provision from an existing authorized device

## Local Data Model

The app must preserve a simple mental model:

- Users can open the vault folder in any editor
- The app watches for filesystem changes
- The app never rewrites Markdown into a proprietary note format
- App-specific state lives outside note bodies where possible

Recommended local side data:

- Hidden app state directory adjacent to or inside the chosen vault root
- Local cache DB for index state, sync cursors, and graph data
- Device-scoped settings and synced-settings separation

Do not store required note semantics in sidecar files.

## AWS Self-Hosted Topology

The self-hosted AWS deployment is single-account and optimized for simplicity.

Recommended MVP shape:

- API Gateway HTTP API
- Go API running on AWS Lambda
- DynamoDB for account, device, manifest, and trash metadata
- S3 for encrypted note payloads and settings blobs
- Secrets Manager or SSM Parameter Store for bootstrap secrets
- CloudWatch for logs and alarms

Optional later additions:

- Custom domain with ACM
- CloudFront
- AWS WAF
- Backup automation beyond native service defaults

## Hosted Service Boundary

Assume the hosted offering is built from the same app and protocol concepts but may include private operational components not stored in this repository.

Public repository scope:

- Client code
- Shared core
- Single-tenant sync service
- AWS self-hosting templates

Private managed-service scope:

- Billing
- Tenant orchestration
- Internal support tools
- Internal operations automation

## Repository Direction

Recommended monorepo structure:

- `apps/client_flutter`
- `crates/core_sync`
- `services/sync_api`
- `infra/aws/cfn`
- `docs/`

Keep public docs free of competitor references.
