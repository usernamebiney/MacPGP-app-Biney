# Development

## Requirements

- macOS Tahoe 26.2 or later
- Xcode 26.2+
- macOS Tahoe 26.2+ and Xcode 26.2+. MacPGP supports Apple Silicon (`arm64`) and Intel (`x86_64`) Macs. The vendored `RNPBridge.xcframework` is universal and contains both macOS slices. The Intel bridge must be rebuilt on an Intel Mac using Intel Homebrew libraries before an Intel build.
- Bash 4+ for shell test harnesses such as `scripts/test-manual-testing-guide-modules.sh`; CI and supported dev shells should resolve `/usr/bin/env bash` to Bash 4+.

### Architecture support matrix

Architecture support applies at every layer:

| Layer | Requirement |
| --- | --- |
| Runtime (users) | Apple Silicon (`arm64`) and Intel (`x86_64`) Macs. |
| Development host | Apple Silicon or Intel Mac. The bridge slice for the host architecture must be available. |
| Archive / CI architecture | Universal `arm64` + `x86_64`. |

`scripts/check-bridge-architectures.sh` reports the architectures vendored in `RNPBridge.xcframework` (and, when an app bundle is provided, the final archive's executable) and fails if they diverge from the documented universal matrix.

> Universal (`arm64` + `x86_64`) support is now the target. The Intel slice is built from x86_64 Homebrew libraries on an Intel Mac, then packaged alongside the existing arm64 slice. The bridge is validated for architecture and deployment target before the XCFramework is replaced.

## Intel build

On an Intel Mac, install the required Homebrew packages if they are not already present:

```bash
brew install rnp botan json-c
```

Then regenerate the universal bridge:

```bash
HOMEBREW_PREFIX="$(brew --prefix)" Vendor/RNPBridge/scripts/build-rnp-bridge.sh
```

The bridge script preserves the checked-in `arm64` slice and builds a new `x86_64` slice from the Intel Homebrew static libraries. It validates both slices before replacing the XCFramework.

After the bridge succeeds, build MacPGP normally:

```bash
scripts/build.sh build
```

Or run the complete Intel setup, bridge rebuild, validation, and Release build
with one command:

```bash
scripts/build-intel.sh
```

The main application and all four extensions consume `RNPKit`, so the final build should be tested on the Intel Mac.

## Local Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/ThalesMMS/MacPGP-app.git
   cd MacPGP-app
   ```

2. Open the Xcode project:
   ```bash
   open MacPGP/MacPGP.xcodeproj
   ```

3. Build and run:
   - In Xcode: press `⌘R`.
   - From the command line: `scripts/build.sh run` builds and launches the app.
     Use `scripts/build.sh` to just build, `scripts/build.sh test` for the unit
     tests, and `scripts/build.sh --help` for all commands. It wraps the same
     `xcodebuild` invocation as CI, so by default it builds unsigned (no team or
     provisioning profile required); add `--signed` when you need entitlements
     (App Groups / keychain) to exercise the bundled extensions.

## Dependencies

- Local `RNPKit` Swift wrapper backed by the vendored `Vendor/RNPBridge/RNPBridge.xcframework`
- CI, the Xcode project, and `Vendor/RNPKit/Package.swift` intentionally target macOS 26.2. The vendored bridge archive currently reports `minos 26.0`, which is compatible with that deployment target; `Vendor/RNPBridge/scripts/check-rnp-bridge-minos.sh` guards against accidentally vendoring a newer bridge.
- CI hides the Dock before `MacPGPUITests` so the hosted macOS desktop cannot cover sheet confirmation buttons and steal synthesized clicks.

## Project Structure

```text
MacPGP/
├── Core/
│   ├── Models/
│   ├── Services/
│   ├── Security/
│   └── Persistence/
├── Features/
│   ├── Keyring/
│   ├── KeyDetails/
│   ├── KeyGeneration/
│   ├── Encryption/
│   ├── Signing/
│   └── Settings/
├── Navigation/
└── Shared/
    ├── Components/
    └── Extensions/
```

## Signing and entitlements

The shipped targets are the Main App plus four extensions: FinderSyncExtension,
QuickLookExtension, ThumbnailExtension, and ShareExtension. Each target's
minimum entitlement set and rationale are recorded in `MacPGP/ENTITLEMENTS.md`,
with the machine-readable source of truth in `scripts/entitlements-manifest.json`.

- `scripts/check-archive-entitlements.sh --source` validates the checked-in
  `.entitlements` files against the manifest and runs in CI, so source drift
  (e.g. an unexpected App Group on the sandbox-only ThumbnailExtension) is caught
  without a signed archive.
- `scripts/check-archive-entitlements.sh --archive <path>` validates a signed
  `.xcarchive` before App Store submission (App Group, user-selected file access,
  the app's keychain access group, absence of `get-task-allow`, and the embedded
  extension inventory). See `docs/SIGNING_REFERENCE.md` and `RELEASING.md`.
