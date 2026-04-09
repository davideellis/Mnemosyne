# Sync Protocol Draft

This document captures the initial wire contract for the Mnemosyne MVP sync service.

## Goals

- Keep the server blind to note contents
- Keep the API small and easy to self-host
- Support one user with many personal devices
- Support last-write-wins semantics
- Sync note files, folders, trash state, and settings

## Notes

- The API stores encrypted note blobs and encrypted settings blobs.
- Paths are client concerns. The server stores opaque object identifiers plus encrypted metadata.
- The server can see timestamps, device IDs, and object IDs, but not note contents.

## Route Summary

### `POST /v1/account/bootstrap`

Creates the single account for a self-hosted deployment or a normal account in the hosted environment.

Request:

```json
{
  "email": "user@example.com",
  "passwordVerifier": "opaque-string",
  "encryptedMasterKeyForPassword": "base64",
  "encryptedMasterKeyForRecovery": "base64",
  "recoveryKeyHint": "optional-short-hint",
  "device": {
    "deviceId": "uuid",
    "deviceName": "Windows Laptop",
    "platform": "windows"
  }
}
```

### `POST /v1/auth/login`

Returns a session token plus the wrapped master-key material needed for the client to recover the vault key locally.

### `POST /v1/auth/recover`

Returns a session token plus the wrapped master-key material needed for the client to recover the vault key with the recovery key.

### `POST /v1/devices/register`

Registers a new device through recovery-key flow or an approval flow.

### `POST /v1/sync/pull`

Returns changes after the supplied cursor.

### `POST /v1/sync/push`

Accepts a batch of encrypted changes and returns the updated cursor.

### `POST /v1/trash/restore`

Restores a note or folder from synced trash.

## Change Envelope

```json
{
  "changeId": "uuid",
  "objectId": "uuid",
  "kind": "note",
  "operation": "upsert",
  "logicalTimestamp": "2026-04-08T15:30:00Z",
  "originDeviceId": "uuid",
  "encryptedMetadata": "base64",
  "encryptedPayload": "base64"
}
```

`encryptedMetadata` is expected to contain values such as:

- relative path
- title cache
- tags cache
- link targets
- deletion status

The exact metadata envelope can evolve, but it must remain encrypted.

## Auth Response Shape

Bootstrap and login responses return:

```json
{
  "accountId": "acct_local",
  "sessionToken": "opaque-session-token",
  "encryptedMasterKeyForPassword": "base64",
  "encryptedMasterKeyForRecovery": "base64",
  "recoveryKeyHint": "optional-short-hint"
}
```

The server stores wrapped key material, but it must not have enough information to decrypt note contents on its own.

Bootstrap requests also store verifier material for password-based auth and recovery-key-based auth. Recovery auth validates the recovery verifier and returns the wrapped recovery-key envelope without exposing plaintext note data.

## Conflict Handling

- The client sends logical timestamps with each mutation.
- The server orders accepted changes by timestamp and tie-breaks by change ID.
- The effective sync policy is last write wins.
- Stale writes for an object are ignored once the server has already accepted a newer change.
- Clients may show local warnings, but the server does not merge content.
