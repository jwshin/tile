# Development

Build and run on macOS 27 or later with the macOS 27 SDK and Swift 6.4, as pinned in `.swift-version`. The scripts use `swiftly run swift` when swiftly is installed,
and otherwise the selected system Swift. They work with the macOS system Bash.

- `./build-debug.sh`: build the app and copy its executable to `.debug/tile`.
- `./run-debug.sh`: build and start the app; this manages real desktop windows.
- `./swift-test.sh`: run the serialized Swift Testing suites.
- `./test.sh`: tests followed by an app build treating warnings as errors.
- `./lint.sh`: warnings-as-errors app build.
- `./build-release.sh [output.app]`: build/sign `.release/tile.app` (or the supplied path) without installing or launching it.
  Use a separate output path while another build is running.

Open `Package.swift` in Xcode. Running the debug executable from Terminal lets macOS request Accessibility
permission for that host. The release app has a separate bundle identity and permission grant. Stop the
upstream window manager and other debug instances before interactive testing.

After model changes, test with at least two displays: move/focus windows across displays, change the display
arrangement, disconnect/reconnect a display, and lock/unlock. Also exercise floating dialogs, minimize/restore,
native fullscreen, disable/re-enable, and config reload. Unit tests cover model behavior; native Accessibility
behavior still requires a desktop smoke test.

`axDumps` contains window-classification fixtures. Apple's Accessibility Inspector can help investigate
new app compatibility issues. Avoid stripping app-specific classification solely because it is unfamiliar.

The personal TOML schema is intentionally incompatible with upstream. Update `resources/default-config.toml`
and ConfigTest together when changing it. Do not edit the user's existing upstream configuration.

CI uses GitHub’s `xcode-27` runner, which runs macOS 27. This runner is currently a public preview.

The app bundle is `tile.app`, its executable is `tile`, and its release bundle ID is `local.jwshin.tile`.
The debug bundle ID is `local.jwshin.tile.debug`. The personal configuration is `~/.tile.toml`.
When upgrading from an earlier name, copy the existing personal configuration to this path before launching
tile, stop the previous app, and grant Accessibility access to tile if macOS prompts.
