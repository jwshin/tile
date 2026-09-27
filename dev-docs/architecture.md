# Architecture

The app is one process. Keyboard shortcuts invoke typed internal commands directly; there is no CLI or socket server.

```mermaid
flowchart LR
    Config["TOML bindings"] --> Keys["HotKey shortcuts"]
    Keys --> Actions["Internal actions"]
    Actions --> Tree["Window tree per monitor"]
    Events["macOS notifications"] --> Refresh["Reconcile windows and monitors"]
    Refresh --> Tree
    Tree --> Layout["Calculate window frames"]
    Layout --> AX["macOS Accessibility APIs"]
```

`Sources/tile/TileApp.swift` creates the menu and message scenes and calls `initAppBundle`.
`Package.swift` defines the executable, internal AppBundle and Common modules, PrivateApi bridge, and tests.
The release script packages the executable and default configuration into a local macOS app bundle.

## Display layouts

`Workspace` is retained as an internal layout container. There is one per connected display, indexed by
macOS display ID rather than screen coordinates or user-specified workspace names. Display movement
updates geometry without exchanging trees. Disconnecting merges the missing display's tiling subtree,
floating windows, and native fullscreen/hidden windows into the main display. A newly connected display
gets an empty tree. A transient zero-display snapshot does not destroy existing layouts.

There is no inactive-workspace hiding. All registered display layouts are visible. Frozen focus resolves
references to disconnected displays back to the main display. Monitor topology changes invalidate the
closed-window restoration snapshot so unlocking cannot restore an obsolete display arrangement.

## Commands and configuration

Bindings store a typed `Action` selected by exact name. `Action.swift` maps the finite action set to small
internal commands; there is no argument parser, command sequence, window-ID target, or monitor-pattern matching.
Commands operate on the current focus. The shared runner resets restoration caches when needed and refreshes
the model after each action, including failures. Monitor navigation retains directions and wrapping next/previous;
moving a window between monitors always follows it. Directional window focus stops at display edges.

Configuration has only `gap`, `floating-apps`, and `[bindings]`. All displays use the same inner/outer gap,
with 8 points as the default. Key names use fixed QWERTY positions. A custom binding table replaces the defaults.
Parsing collects diagnostics and rejects the entire reload on error. The config path is fixed to
`~/.tile.toml`; the internal URL override exists only for bundled startup validation and tests.

New root layouts use horizontal orientation on landscape displays and vertical on portrait displays.
Single-child groups are always flattened, and nested groups always alternate orientation. Use `join-*` actions
to create groups. Tiling containers store orientation and sizing only. Resize actions use a fixed 50-point step
along the immediate split. Fullscreen preserves outer spacing, close affects only the focused window, and layout
actions toggle orientation or floating state.

## macOS boundary

MacApp serializes Accessibility operations on a dedicated run-loop thread per application. Main-actor
refresh sessions reconcile native events with the mutable model. MacWindow bridges native window IDs
and tree leaves. Keep cancellation, window classification, and lock-screen restoration when changing policy.
Tests use TestWindow and injectable monitor snapshots to verify policy without operating the real desktop.
All model suites are nested under one serialized Swift Testing suite because they share global state.

## Platform baseline

The executable and release bundle require macOS 27. UI models use Observation and are isolated to the main actor.
The diagnostics window uses SwiftUI window controls and selectable read-only text; its Close button handles Return.
Cancellation uses a `Synchronization.Atomic<Bool>` flag. Native `Task` initialization preserves actor context without
an extra wrapper. Accessibility callbacks still use a dedicated run-loop thread per app, including thread-affine cleanup.
