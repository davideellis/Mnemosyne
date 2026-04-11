# Backlog

## Release Readiness

### Windows code signing

Status:
- Blocked

Why it is blocked:
- Windows release artifacts build successfully, but signed distribution is not possible on the current machine.
- `signtool` is installed, but no usable signing certificate is available.
- Latest validation failed with: `No certificates were found that met all the given criteria.`

What is already working:
- Windows executable builds
- Windows release bundle packaging
- Android debug and release APK builds

Unblock conditions:
- Provide a trusted Windows code-signing certificate in the local certificate store, or
- Provide a `.pfx`-based signing workflow and credentials for release signing

Likely follow-up work once unblocked:
- Add a repeatable signing script for the Windows release bundle
- Add signature verification to the release checklist
