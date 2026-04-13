# Backlog

## Release Readiness

### Windows Device Guard blocks local Flutter validation

Status:
- Blocked locally on this workstation

Why it is blocked:
- The Flutter client can stop validating on Windows even when the SDK is present because Windows Device Guard / application control may block the bundled Dart runtime.
- Latest validation failed with: `dart.exe was blocked by your organization's Device Guard policy.`

What is already working:
- Flutter validation and Apple-side builds on the Mac mini
- Windows build validation worked previously before the policy block reappeared
- Go backend validation still works locally through WSL

Unblock conditions:
- Allow the Flutter SDK bundled Dart runtime on this workstation, or
- Move Windows-side Flutter validation to a different machine/profile without that policy block

Likely follow-up work once unblocked:
- Restore direct Windows `flutter analyze`, `flutter test`, and `flutter build windows`
- Capture a stable local validation workflow in the development docs if the policy remains flaky

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
