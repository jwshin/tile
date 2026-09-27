# tile

A reduced, keyboard-driven fork of [the upstream project](https://github.com/nikitabobko/AeroSpace).
Each connected monitor has one permanent tiling layout. There are no virtual workspace switches,
hidden desktops, CLI server, external automation callbacks, or binding modes.

## Behavior

- Tile windows using a binary tree: each split contains exactly two windows or subtrees.
- Focus, rearrange, resize, balance, float, or expand windows using keyboard shortcuts.
- Focus another monitor or move the focused window to it.
- Keep each display's layout when displays are rearranged.
- When a display disconnects, merge its windows into the main display, retaining tiling groups.
- When a display connects, create an empty layout. Windows are not automatically moved back.
- Preserve macOS dialog/popup classification, native fullscreen/minimize handling, and lock-screen recovery.
- Allow normal mouse interaction with windows.

## Build and run

Requires macOS 27 or later and the macOS 27 SDK. Use the Swift toolchain in `.swift-version` (6.4). Open `Package.swift` in Xcode or your Swift editor.

```sh
./test.sh          # Swift Testing regression suite and warnings-as-errors app build
./run-debug.sh     # Build and run from the terminal
./build-release.sh # Build .release/tile.app; no installation
```

Grant Accessibility permission when prompted. Quit other window managers before running tile;
the app checks for another tile or upstream instance at startup. If running multiple unbundled debug
executables, stop the old process first. The release bundle has its own identity, `local.jwshin.tile`.
The release script uses ad-hoc signing by default. Set `TILE_CODESIGN_IDENTITY` to your own
code-signing certificate to use it instead. Ad-hoc rebuilds may require renewing Accessibility permission.

## Configuration

A new tiled window splits the focused tiled window's region 50/50. When focus is floating,
tile uses the most recently focused tiled window on that display. Wide regions split side by side;
tall regions split top/bottom. The chosen orientation stays fixed until you toggle it.
Closing or floating a window promotes its sibling into the freed region. Nested splits may share an orientation.

The old `join-*`, `flatten-layout`, and `toggle-orientation` actions are removed. Use directional
`move-*` actions to reinsert beside a neighbor, and `toggle-split` to change the immediate split.
Update old personal bindings before reloading; invalid configuration is rejected as a whole.

The personal config is `~/.tile.toml`.
Use **Open config** in the menu to create a copy of [the defaults](resources/default-config.toml).
Reload manually from the menu or with `alt-shift-r`. Invalid configuration leaves the current settings intact.
Configuration has just three fields:

```toml
gap = 8
floating-apps = []

[bindings]
alt-h = 'focus-left'
alt-minus = 'shrink'
alt-tab = 'next-monitor'
alt-shift-tab = 'move-to-next-monitor'
```

`gap` is one non-negative integer, used for all inner and outer spacing on every monitor.
It defaults to 8. Key names refer to fixed QWERTY key positions; shortcuts remain editable.
`floating-apps` accepts application bundle IDs whose windows should float. Dialogs and popups
still receive automatic native classification. Omitting `[bindings]` keeps all bundled shortcuts.
An explicit `[bindings]` table replaces the entire shortcut set; an empty table disables all shortcuts.

Each shortcut names exactly one action. Command arguments, arrays, monitor-name patterns,
window IDs, key-mapping presets, per-monitor gaps, and `--config-path` are unsupported.
Older command strings must be replaced with the names below; old `[gaps]` tables become `gap = 8`.
Unknown fields or actions reject the entire reload, preserving the working configuration.

| Action names | Fixed behavior |
|---|---|
| `focus-left`, `focus-down`, `focus-up`, `focus-right` | Focus a neighboring window, including floating windows; stop at monitor edges |
| `move-left`, `move-down`, `move-up`, `move-right` | Reinsert the focused tiled window on that side of a neighboring tiled window; stop at display edges |
| `swap-left`, `swap-down`, `swap-up`, `swap-right` | Exchange neighboring window positions, keeping focus on the original window |
| `next-monitor`, `previous-monitor` | Cycle monitors, wrapping at either end |
| `left-monitor`, `down-monitor`, `up-monitor`, `right-monitor` | Focus a monitor in that direction; stop at edges |
| `move-to-next-monitor`, `move-to-previous-monitor` | Cycle the focused window to a monitor and follow it, wrapping at either end |
| `move-to-monitor-left`, `move-to-monitor-down`, `move-to-monitor-up`, `move-to-monitor-right` | Move the focused window to a monitor in that direction and follow it |
| `grow`, `shrink` | Move the immediate split divider by 50 points to grow/shrink the focused window; manual ratios are limited to 10–90% |
| `toggle-split` | Toggle the focused split between horizontal and vertical |
| `toggle-floating` | Toggle the focused window between floating and tiling |
| `fullscreen` | Toggle filling the monitor's available area, keeping the gap |
| `balance-sizes` | Distribute space by leaf count within each split, retaining the tree; gaps can cause small area differences |
| `close` | Close the focused window |
| `toggle-tiling` | Enable/disable window management |
| `reload-config` | Apply the personal configuration if valid |

Default shortcuts:

| Shortcut | Action |
|---|---|
| `alt-h/j/k/l` | Focus left/down/up/right |
| `alt-shift-h/j/k/l` | Move the window left/down/up/right |
| `alt-ctrl-h/j/k/l` | Swap with a neighboring tiled window |
| `alt-minus/equal` | Shrink/grow along the current split |
| `alt-shift-equal` | Balance window sizes |
| `alt-slash` | Toggle horizontal/vertical split |
| `alt-shift-space` | Toggle floating/tiling |
| `alt-f` | Toggle filling the monitor's available area |
| `alt-tab` | Focus the next monitor, wrapping around |
| `alt-shift-tab` | Move the window to the next monitor and follow it |
| `alt-shift-r` | Reload configuration |

Mouse gestures retain native window dragging and resizing. Drag over a tiled window's center to
swap positions on the same display; drag near an edge to split that window's region in that direction.
Layouts update during the drag, including when moving between displays. Resizing adjusts the corresponding
binary dividers.
Floating windows remain freely movable and resizable.

The menu provides enable/disable, config access, permission status, and quit. When disabled, shortcuts
are unregistered; re-enable from the menu. Quitting leaves window positions as they are.

## Source map

- `Sources/tile`: SwiftUI application entry point.
- `Sources/AppBundle/tree`: binary layout model, window registry, and macOS app adapters. `Workspace` now means a display's layout.
- `Sources/AppBundle/layout`: action execution, reconciliation, and native frame application.
- `Sources/AppBundle/command`: the small internal keyboard-action set.
- `Sources/AppBundle/config`: TOML parsing, keybindings, one gap value, and floating-app exceptions.
- `Sources/AppBundle/ui`: minimal menu and error messages.
- `Sources/Common`: shared geometry, result types, and utilities; no command parser, network protocol, or executable client.
- `Sources/AppBundleTests`: pure binary-layout tests and serialized application/monitor lifecycle tests.
- `axDumps`: accessibility fixtures used by window-classification tests.

See [architecture](dev-docs/architecture.md) and [development](dev-docs/development.md).
Original copyright and third-party licenses are retained in `LICENSE.txt` and `legal/`.
