# Mnemosyne Agent Guide

This file is for coding agents working in this repository.

## Mission

Build a local-first, end-to-end encrypted notes system for one person syncing plain Markdown notes across their own devices.

## Non-Negotiable Product Rules

- Use the product name `Mnemosyne`
- Do not mention competitor products in public docs, marketing text, comments intended for users, or examples
- Notes are plain `.md` files in a user-chosen folder
- The app must remain useful offline
- The server must not be able to read note contents
- Self-hosted AWS MVP is single-account only
- Managed hosting internals are outside the public repository
- Non-Markdown files are ignored in MVP
- Plugins are out of scope in MVP
- Collaboration is out of scope in MVP

## MVP Behavior Rules

- One account, many personal devices
- Folders and subfolders sync
- External file edits are detected automatically
- Rename and move operations sync
- Deletes go to synced trash
- No version history beyond trash
- Last write wins on conflicting edits
- App settings sync across devices
- Search is local-only
- Tags and wikilinks are supported
- Backlinks and graph view are in scope

## Architecture Defaults

Unless a later maintainer explicitly changes direction, assume:

- Flutter for cross-platform app UI
- Rust shared core via `flutter_rust_bridge`
- Go sync API
- Custom HTTPS sync protocol
- AWS CloudFormation for self-hosting

## Working Style

- Favor small, composable modules
- Prefer predictable behavior over cleverness
- Add tests around sync edge cases before broadening scope
- Keep encryption boundaries obvious in code
- Keep local user data and internal app state clearly separated

## Documentation Style

- `README.md` is for human readers
- `ARCHITECTURE.md`, `DEVELOPMENT.md`, and `AGENT.md` are implementation-facing
- Keep public docs free of promises not yet implemented
- State sharp edges clearly, especially recovery-key loss and sync conflict rules

## Near-Term Build Sequence

1. Create the monorepo scaffold
2. Build the Rust core state model
3. Implement encrypted sync primitives
4. Build the minimal Go API
5. Add the AWS CloudFormation stack
6. Build the Flutter shell and note workflows
7. Add graph and backlink features
