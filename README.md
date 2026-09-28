# tile

A personal, keyboard-driven fork of [AeroSpace](https://github.com/nikitabobko/AeroSpace).
Each connected monitor has one permanent layout. There are no virtual workspace switches,
CLI server, external automation callbacks, or binding modes.

## Layout

Each section is one window or two child sections. Split directions alternate by depth, starting
left/right on a wide screen and top/bottom on a portrait screen. New splits start at 50/50 and can
be resized. New windows split the remembered tiled target using **Outer** (toward the nearer screen
edge) or **Inner** placement. Floating focus does not replace that tiled target.

Moves carry the selected window's width for horizontal moves or height for vertical moves.
For example, moving the wide window across a 70/30 split produces 30/70. Neighboring dividers adjust
to preserve the allocation. Moving toward the immediate sibling swaps the whole sibling section;
moving beyond the parent swaps individual windows. Closing or floating a window promotes its sibling,
with split directions following the new depth.

Tiles have a 320 × 200 point baseline minimum, raised when an application demonstrates a larger limit.
A new window floats if its insertion cannot fit. Resizing clamps at minimums. Screen changes and collapse
adjust ratios as needed, then float the least recently focused tiles only if necessary.

Focus follows per-screen history, including floats. Directional focus visits tiles, crosses screens
in their physical arrangement, skips empty screens, and does not wrap. Directional moves stay on the
current screen; monitor transfer is a separate action. Disconnected-screen windows migrate individually
to the most recently focused remaining screen, falling back to the main screen. Reconnected screens
start empty. There is no persistent layout store.

The [tiling rules](dev-docs/tiling-rules.md) are the authoritative specification.
Open the retained [interactive prototype](dev-docs/layout-prototype.html) directly in Chrome to experiment
with layouts, minimums, screen changes, and window lifecycle events. It needs no server or dependencies.

## Build and run

Requires macOS 27, the macOS 27 SDK, and Swift 6.4 (see `.swift-version`). Open `Package.swift` in Xcode.

```sh
./test.sh          # Swift Testing suite and warnings-as-errors app build
./run-debug.sh     # Build and run; manages real desktop windows
./build-release.sh # Build/sign .release/tile.app without installing or launching
```

Grant Accessibility permission when prompted. Quit other window managers before starting tile.
The release bundle ID is `local.jwshin.tile`; debug is `local.jwshin.tile.debug`.
The release script uses ad-hoc signing unless `TILE_CODESIGN_IDENTITY` is set; ad-hoc rebuilds may
require renewing Accessibility permission. Stop any older unbundled debug process before launching.

## Configuration

Use **Open config** in the menu to create `~/.tile.toml` from [the defaults](resources/default-config.toml).
Reload from the menu or with `alt-shift-r`. Invalid configuration preserves the working configuration.

```toml
gap = 8
new-window-placement = 'outer' # outer | inner
root-orientation = 'auto'     # auto | horizontal | vertical
```

`gap` controls all inner and outer spacing. Root orientation follows usable screen shape in Auto;
`toggle-orientation` sets an in-memory override for the selected screen. Disconnecting discards that override.
Placement affects future insertions, including retiling, returning windows, and transfers.

Omit `[bindings]` to keep the default shortcuts. An explicit table replaces the whole set; an empty
one disables shortcuts. Keys use fixed QWERTY positions, and each shortcut names one action:

```toml
[bindings]
alt-h = 'focus-left'
alt-equal = 'grow-width'
alt-tab = 'next-monitor'
alt-shift-tab = 'move-to-next-monitor'
```

**Migration:** remove `floating-apps` and replace `join-*` or `flatten-layout` bindings. Manual floating
and native dialog classification remain. Configuration is intentionally incompatible with the old
container model; unknown settings or actions reject the reload as a whole.

| Actions | Behavior |
| --- | --- |
| `focus-left/down/up/right` | Directional tile focus, including across screens |
| `move-left/down/up/right` | Section/window move with size preservation; nudge a float |
| `swap-left/down/up/right` | Individual-window swap, preserving the selected dimension |
| `grow-width`, `shrink-width`, `grow-height`, `shrink-height` | Resize the nearest split on that axis by 50 points, clamped to minimums |
| `grow`, `shrink` | Resize the immediate split by 50 points |
| `toggle-orientation` | Flip the screen root and all alternating subdivisions |
| `toggle-floating` | Float/retile an eligible window through normal insertion |
| `balance-sizes` | Reset splits to 50/50, then enforce minimums |
| `fullscreen` | Toggle filling the monitor's available area, retaining its tile |
| `close` | Close the focused window |
| `next-monitor`, `previous-monitor` | Cycle screens with wrapping |
| `left/down/up/right-monitor` | Select a screen in that physical direction |
| `move-to-next-monitor`, `move-to-previous-monitor` | Transfer and focus, cycling with wrapping |
| `move-to-monitor-left/down/up/right` | Transfer and focus in that physical direction |
| `toggle-tiling`, `reload-config` | Enable/disable management; reload preferences |

The slash-separated names in the table denote individual actions (for example, `focus-left`).

| Default shortcut | Action |
| --- | --- |
| `alt-h/j/k/l` | Focus left/down/up/right |
| `alt-shift-h/j/k/l` | Move left/down/up/right |
| `alt-ctrl-h/j/k/l` | Swap individual windows |
| `alt-minus/equal` | Shrink/grow width |
| `alt-ctrl-minus/equal` | Shrink/grow height |
| `alt-shift-equal` | Balance split sizes |
| `alt-slash` | Flip screen orientation |
| `alt-shift-space` | Toggle floating |
| `alt-f` | Toggle filling the available screen area |
| `alt-tab` | Focus next monitor |
| `alt-shift-tab` | Transfer to next monitor |
| `alt-shift-r` | Reload config |

## Mouse and native lifecycle

Drag within the immediate parent to swap sibling sections; cross its boundary to swap individual windows.
Changes are live. Once a drag crosses a parent boundary, it keeps swapping individual windows until release.
The pointer must leave a target region before another swap. Escape cancels the gesture.

Hovering another screen shows an outline; releasing transfers using normal insertion. Source-screen swaps
made during that gesture are discarded on a cross-screen drop. Floating windows remain freely draggable
and resizable. Native tiled resizing adjusts the corresponding binary dividers.

Minimized, hidden, and native fullscreen windows leave the tree and reinsert on return. Floating windows
remain floating. In-memory snapshots support recovery from temporary Accessibility observation loss.
Restart rebuilds from discovered windows rather than writing layouts to disk.

The menu provides enable/disable, config access, permission status, and quit. Disabled shortcuts are
unregistered; re-enable from the menu. Quitting leaves window positions as they are.

## Source map

- `Sources/tile`: SwiftUI app entry point.
- `Sources/AppBundle/tree`: pure binary layout, display/window state, native app/window adapters.
- `Sources/AppBundle/layout`: action sessions, reconciliation, native frame application.
- `Sources/AppBundle/mouse`: drag/resize transactions and destination preview.
- `Sources/AppBundle/command`: keyboard and menu actions.
- `Sources/AppBundle/config`: TOML preferences and shortcut registration.
- `Sources/AppBundle/ui`: menu and error messages.
- `Sources/Common`: geometry and small shared utilities.
- `Sources/AppBundleTests`: layout, focus, gesture, lifecycle, configuration, and adapter tests.
- `axDumps`: native window-classification fixtures.

See [architecture](dev-docs/architecture.md) and [development](dev-docs/development.md).
Original copyright and third-party licenses remain in `LICENSE.txt` and `legal/`.
