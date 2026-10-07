# Development

Build and run on macOS 27 or later with the macOS 27 SDK and Swift 6.4, as pinned in `.swift-version`. The scripts use `swiftly run swift` when swiftly is installed,
and otherwise the selected system Swift. They work with the macOS system Bash.

- `./build-debug.sh`: build the app and copy its executable to `.debug/tile`.
- `./run-debug.sh`: build and start the app; this manages real desktop windows.
- `./swift-test.sh`: run the serialized Swift Testing suites.
- `./test.sh`: tests followed by an app build treating warnings as errors.
- `node --test script/test-layout-prototype.cjs`: test the retained prototype’s model-owned gestures, lifecycle interruption, resizing, cross-screen release, pointer-event cancellation, and read-only diagnostic capture/copy without a browser or external packages; the pointer-adapter tests stub rendering.
- `./lint.sh`: warnings-as-errors app build.
- `./build-release.sh [output.app]`: build/sign `.release/tile.app` (or the supplied path) without installing or launching it.
  Use a separate output path while another build is running. Version metadata comes from `Sources/Common/version.swift`.
- `./package-release.sh [output-directory]`: build/sign an Apple silicon app, bundle license notices, and create a ZIP and SHA-256 checksum. See [releasing](releasing.md).
- `swift script/render-logo.swift`: regenerate the SVG logo, PNG preview, and ICNS app icon from shared geometry using macOS graphics tools.

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

## Native validation record: 2026-09-28

The P2 fixes have automated regression coverage for recent-focus recovery after native close/minimize/fullscreen,
interrupted reconciliation, leading-edge resizing, and returning from cross-screen hover. These are adapter/model
checks, not a completed desktop smoke test. Re-run `./test.sh` and the prototype's guided controls for code validation.

A read-only AppKit/Accessibility probe in this session reported **one connected display** and
**Accessibility trusted: false** for the probe process. The installed release app has its own permission grant;
this probe does not report that app's grant. No desktop-control tool is available in this session.
The required native validation remains open until the following checks are performed with a current build:

| Check | Action and expected result | Status |
| --- | --- | --- |
| Recent focus | Focus a floating window, then a tile. Close/minimize the tile with native controls; the float receives keyboard input. Repeat with the float in another app. | Not run |
| Leading-edge resize | Expand a right-hand tile from its left edge, then a bottom tile from its top edge. Use a small gap and slow initial movements. The split changes; window positions do not exchange. Also drag a terminal window normally after cell-size rounding. | Not run |
| Return from hover | With narrow W1 / wide W2, drag W1 onto W2, hover a second display, then return over W2 near the original divider. Swap back immediately; release on the source display. | Not run |
| Multi-display movement | Move and focus windows across two displays, then change their physical arrangement. Focus and tiling follow the new geometry. | Not run |
| Disconnect/reconnect | Disconnect a populated display. Windows migrate individually; reconnecting starts an empty layout. | Not run |
| Lock/unlock | Lock and unlock with tiles and floats present. Temporary observation loss does not lose windows or corrupt the layout. | Not run |
| Native lifecycle | Minimize/restore, hide/show, and enter/exit native fullscreen. Excluded windows leave the tree; return uses ordinary insertion. Verify dialogs still float. | Not run |
| Configuration lifecycle | Disable/re-enable tiling and reload valid configuration. Shortcuts and layout remain operational. | Not run |
| State diagnostics | Open diagnostics with tiled, floating, minimized, and fullscreen windows across displays. Check model/cache/native IDs and geometry, recapture, copy, and save. Verify access while disabled or permission is missing, partial reports for stalled apps, and that opening the view does not rearrange windows. | Not run |

Record the build/commit, displays, application names, results, and any reproduction details when completing these checks.

## Launch at login

The menu uses `SMAppService.mainApp` through `LaunchAtLogin`. Registration is opt-in and belongs to
macOS; there is no stored Boolean, config key, helper app, or startup-time registration. Status refreshes
when the menu opens and when tile becomes active. Enabling a registration that requires approval opens
Login Items settings only after the user requests it. Failures refresh the actual state and use the
existing diagnostics window. Unbundled/debug executables are ineligible for registration, represented
by a nil service status. A native `.notFound` status can mean macOS has never seen this login service;
it leaves the toggle available and an explicit enable request attempts registration. Bundle eligibility
and registration status must not be conflated. The menu header shows the shared app version.

Tests inject a service adapter to exercise registration, removal, external changes, approval, failure,
and observable menu state without modifying the developer's login items.

For 0.2.0, a disposable ad-hoc signed app on macOS 27.2 exercised the production login model and native
adapter with a unique test bundle identifier. It confirmed `.notFound` with the toggle available,
successful registration (`.enabled`), and removal (`.notRegistered`). The temporary app was removed;
tile's own registration was not changed. This validates native registration, not launch during login.

Manual validation still needs an installed signed `tile.app`: enable the toggle, check System Settings,
disable/re-enable there and reopen the menu, then log out/in and confirm tile starts. Disabling the
toggle should prevent the next login launch without quitting the current app. These native menu and
login/logout checks are not automated.
