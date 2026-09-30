# Releasing tile

The distributable is an Apple silicon `tile.app` for macOS 27 or later. Version numbers live in
`Sources/Common/version.swift`; the build script copies that version into both bundle version keys.
The app retains its `local.jwshin.tile` bundle ID so installations share one Accessibility identity.

## Prepare and validate

1. Set the numeric `major.minor.patch` version in `Sources/Common/version.swift`.
2. Run `./test.sh`, then `./package-release.sh .release/dist`.
3. Verify the archived app after extraction: its signature, bundle version, minimum OS, arm64 architecture,
   app icon, default config, and license notices must match the release. Confirm `Contents/MacOS/tile --version`.
4. Commit and push the release source. Tag that commit `v<version>`. Publish subsequent releases under
   a new version and keep the release archive, checksum, and cask synchronized.

Packaging produces `tile-<version>-macos-arm64.zip` and a companion `.zip.sha256` file. The archive
contains only `tile.app`, including `LICENSE.txt` and `legal/` in `Contents/Resources`. The build script
uses ad-hoc signing by default; `TILE_CODESIGN_IDENTITY` can select an installed signing identity.
Developer ID notarization is not configured. Keep quarantine intact and document Apple's
[Open Anyway](https://support.apple.com/en-us/102445) flow instead of disabling Gatekeeper.

## Publish the release and tap

Create a GitHub release for the version tag and upload the ZIP and checksum. Identify the supported
platform, changes, installation steps, and known limitations in its notes. The native desktop validation
record in [development](development.md#native-validation-record-2026-09-28) is separate from automated tests.

The Homebrew cask is maintained in [jwshin/homebrew-tap](https://github.com/jwshin/homebrew-tap),
`Casks/tile.rb`. Update its `version` and `sha256` to match the published archive, then run Homebrew's
style and cask audit checks. Keep the download URL pinned to the version tag, the macOS/architecture
requirements explicit, and `app "tile.app"` as the installation artifact. Do not bundle a personal config
or add cleanup that deletes `~/.tile.toml`.

Push the cask and verify `brew fetch --cask jwshin/tap/tile` against the uploaded checksum. Test installation
with Homebrew; launch, Gatekeeper approval, and Accessibility approval on another Mac remain user steps.
Installation commands are in the main README and the tap README.
