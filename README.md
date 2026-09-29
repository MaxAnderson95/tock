> [!WARNING]
> This project is a work in progress. It is still being built and is not ready for use.

# Tock

Tock is a macOS menu bar app that shows your two-factor codes. Click the menu bar icon to see the current code for every service, and click a code to copy it.

- Codes follow RFC 6238 (TOTP). Each service can set its digits (6, 7, or 8), period (5 to 300 seconds), and algorithm (SHA-1, SHA-256, or SHA-512). New services start at 6 digits, 30 seconds, SHA-1, which is what almost every site uses.
- Each service, secret included, is stored as one item in your login keychain. Tock writes nothing else to disk except the list order and two preferences in its app defaults.
- You add services by typing the setup key a site shows under "Can't scan the QR code?". Pasting an `otpauth://` link fills in every field. There is no QR scanning.
- Copied codes are marked concealed for clipboard managers and are cleared from the clipboard after 30 seconds unless you copy something else first.

Requires macOS 26 on Apple Silicon.

## Install

Download `Tock-vX.Y.Z-macos-arm64.zip` from the latest GitHub release, unzip it, and move `Tock.app` to `/Applications`. Tock must run from `/Applications` for menu bar managers such as Bartender to place its icon on macOS 27.

To build from source with Command Line Tools only (no Xcode), build against the macOS 26 SDK:

```sh
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk bash scripts/build-app.sh --build-system native
rm -rf /Applications/Tock.app && cp -R build/Tock.app /Applications/
open /Applications/Tock.app
```

Tock turns on Launch at login the first time it runs. Change it in Settings.

The build is ad-hoc signed. The keychain lets the build that saved your services read them silently. After you install a new build, macOS asks once whether Tock may use its keychain items; choose Always Allow.

## Use

- Click the menu bar icon, then click a code to copy it. You can also type to filter and press Return to copy the top match.
- The ring beside each code shows the seconds left before it changes. It turns orange in the last five seconds.
- Use the + button to add a service, or the gear button to reorder, edit, or delete services. The editor shows the live code once the key is valid, so you can confirm it against the site before saving.
