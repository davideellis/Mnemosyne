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

### Apple developer signing and provisioning

Status:
- Blocked

Why it is blocked:
- Apple build outputs are working for simulator and unsigned release artifacts, but signed iOS distribution is not possible yet.
- `flutter build ipa` currently fails because the Mac mini does not have valid Apple development/distribution certificates and provisioning configured for this app.
- Latest validation failed with: `No valid code signing certificates were found`

What is already working:
- macOS release build
- iOS simulator build
- iOS release build with `--no-codesign`

Unblock conditions:
- Sign in to Xcode on the Mac mini with the Apple developer account
- Select a valid development team for bundle ID `com.davideellis.mnemosyne`
- Let Xcode create or download the required certificates and provisioning profiles

Likely follow-up work once unblocked:
- Validate `flutter build ipa`
- Document the Apple signing and archive workflow
- Add TestFlight-ready packaging steps to the release checklist

## Test Environment

### Backup export resilience

Status:
- Open

Why it matters:
- During the `Mnemosyne-tst` account reset, the backup script hit a broken-state edge case where the metadata referenced an S3 payload key that no longer existed.
- `.\scripts\backup-tst.ps1` currently fails hard on that condition instead of exporting what it can and reporting the dangling references cleanly.

What is already working:
- normal backup export for healthy state
- test-stack reset and re-bootstrap
- live full smoke verification against `Mnemosyne-tst`

Unblock conditions:
- Make `.\scripts\backup-tst.ps1` tolerate missing payload objects
- Emit a clear manifest entry for any dangling payload reference found during export

Likely follow-up work once unblocked:
- use backup export as a safer default before all destructive `tst` maintenance
- add a regression test or fixture around missing S3 payload objects
