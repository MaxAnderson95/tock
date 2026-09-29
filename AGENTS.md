# Tock

A native SwiftUI menu bar app (AppKit `NSStatusItem` plus `NSPopover`) that generates TOTP codes. Read `README.md` for the product.

## Layout

- `Sources/TockCore`: `Service` (RFC 6238 code generation and `otpauth://` parsing), `Base32`, and `Vault` (keychain storage). No UI.
- `Sources/TockApp`: `Store` (app state, ordering, clipboard, launch at login), `CodeList` (popover), `Settings` (service list and editor), `Theme` (palette and shared controls), `main.swift` (status item, popover, and Settings window).
- `Tests/TockTests`: RFC 6238 Appendix B vectors, Base32, `otpauth://` parsing, and a `Vault` round trip against the real login keychain under a throwaway keychain service name.

## Contracts

Changing these loses or strands a user's saved services:

- Keychain items: generic passwords with service `tech.maxanderson.tock`, account set to the Service UUID, and the JSON-encoded `Service` as data.
- Bundle identifier `tech.maxanderson.tock` and the UserDefaults keys `order`, `clearsClipboard`, and `loginSetupCompleted`.

## Keychain

`Vault` uses the file-based login keychain. The data protection keychain returns `errSecMissingEntitlement` (-34018) for ad-hoc signed apps because it needs a provisioning profile. Every rebuild changes the ad-hoc signature, so the first keychain read after installing a new build prompts once.

## Build and test

This Mac has Command Line Tools (Swift 6.4), not Xcode. Use the macOS 26 SDK and the native build system; the default MacOSX27 SDK and Swift Build fail on SwiftUI and Swift Testing macros.

```sh
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk bash scripts/test-swift.sh --build-system native
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk bash scripts/build-app.sh --build-system native
```

`scripts/test-swift.sh` adds the Command Line Tools Testing framework paths. `scripts/build-app.sh` builds `build/Tock.app`, ad-hoc signed; install by copying it to `/Applications`. Bartender on macOS 27 cannot place menu bar items for apps running from `~/Applications` or other folders. `scripts/make-icons.sh` regenerates `assets/Tock.icns` from `assets/tock-icon.svg`.

CI runs on macOS 26 with Xcode (`DEVELOPER_DIR` in `.github/workflows/ci.yml`), so a local pass with Command Line Tools is not a CI-equivalent check.

## Release

Push an annotated tag `vX.Y.Z`. `.github/workflows/release.yml` rejects lightweight and non-SemVer tags, builds the app, stamps the version into `Info.plist`, ad-hoc signs it, and publishes `Tock-vX.Y.Z-macos-arm64.zip` to a GitHub release with generated notes.
