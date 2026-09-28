# tile tiling rules

Living decision document for tile’s tiling algorithm, incorporating the design interview completed on 2026-09-27. This is the authoritative record of accepted behavior. Smaller engineering defaults are identified separately so they are not mistaken for explicit user choices.

The retained [layout prototype](layout-prototype.html) implements these layout decisions and simulates window and screen lifecycle events. Actual macOS observation, window classification, and native window manipulation remain application integration work. Open the HTML directly in Chrome; no server or dependencies are required.

**Maintenance rule:** whenever a tiling decision changes, update the relevant rule here and the prototype behavior in the same change. Add or revise a guided scenario that demonstrates the decision, exercise the affected controls, and update the coverage notes when simulation boundaries change. Keep undecided proposals distinct from accepted behavior. The prototype and this document should agree before the change is considered complete.

## 1. Screens and sections

- Each screen owns an independent tiled layout and a collection of floating windows.
- An empty screen has no tiled section. Otherwise its root section covers the usable tiling area.
- A section contains either one window or exactly two child sections. There are no single-child splits or lists of windows within leaves.
- Each tiled window occupies exactly one leaf. Each managed window belongs to one screen and is either tiled, floating, or temporarily excluded while minimized, hidden, or in native fullscreen.
- Child order determines position: first means left/top; second means right/bottom.

Example: `[W1, [W2, W3]]` on a screen with a horizontal root:

```text
┌──────────┬──────────┐
│          │    W2    │
│    W1    ├──────────┤
│          │    W3    │
└──────────┴──────────┘
```

## 2. Orientation and split ratios

**Horizontal** means children sit left/right; **vertical** means top/bottom. Choose a screen's initial root direction from its usable shape: horizontal for wide screens, vertical for portrait screens. Allow an explicit override and a command to flip the root direction. If shape information is unavailable, fall back to horizontal.

Every deeper level uses the opposite direction. Direction follows current depth rather than remaining attached to a section. Promoting a section after removal can therefore rotate its subdivisions.

Every new split starts at **50/50** after accounting for the gap. Support keyboard and mouse resizing, retaining the resulting ratio for that split. Resizing adjusts the nearest ancestor split on the requested axis. In the example, resizing W3 horizontally adjusts the W1/right-column boundary; resizing it vertically adjusts the W2/W3 boundary.

Ratios describe positions within a split. Swapping its two children leaves the divider in place: a 70% left / 30% right split remains 70/30. A moved subtree retains its internal splits and ratios, subject to the swap's minimum-size validation.

## 3. One insertion rule

Use the same rule for creating a tiled window, retiling a floating window, returning a previously tiled window from minimization/hiding/fullscreen, transferring a tiled window, and receiving windows from a disconnected screen:

1. Resolve the destination screen. Newly created application windows use the currently focused screen, regardless of the application's initial placement. Explicit transfers use their requested destination.
2. On an empty tiled layout, use the whole tiling area.
3. Otherwise split the destination's remembered tiled target into the existing window and the arriving window, initially 50/50. Prefer its focused tile; floating focus does not replace the remembered tiled target.
4. Use Outer / Inner to choose which child receives the arriving window.
5. If the proposed placement cannot satisfy both windows' minimum sizes, leave the existing tree unchanged and make the arriving window floating on the destination screen. Do not resize surrounding sections to make room for an insertion.
6. User-created windows and explicitly transferred windows receive focus. Manual retiling retains focus on the same window.

Returning windows do not restore their former tree position.

**Outer / Inner** applies across all screens and affects future insertions only. Outer is the default. Compare the target tile's center with the screen midpoint along the new split's axis:

| Target position along that axis | Outer | Inner |
| --- | --- | --- |
| Left half | New window on the left | New window on the right |
| Right half | New window on the right | New window on the left |
| Top half | New window above | New window below |
| Bottom half | New window below | New window above |

Outer means toward the nearer **screen edge**; Inner means the opposite side, toward the screen center. This remains screen-relative at every depth. Retain the prototype's deterministic tie rule: exactly centered targets use right/bottom for Outer and left/top for Inner.

For the example above, inserting at W2 splits W2 left/right. Outer creates to its right; Inner creates to its left. Mirroring the column to the left reverses those results.

## 4. Minimum sizes and recovery

The initial minimum tile size is **320 × 200 logical points**. Larger window-specific minimums take precedence when known. Lack of a reliable application minimum must not prevent operation: use the baseline and handle observed constraints through the native window adapter.

- Clamp interactive resizing before any affected leaf falls below its minimum.
- Float an arriving window when insertion cannot fit, including on an otherwise empty screen.
- Reject an entire section or window swap if its resulting rectangles violate any affected window's minimum. Leave tree, ratios, and window positions unchanged.
- For unavoidable changes, such as a shrinking screen or rotation after deletion, preserve ratios where possible; otherwise adjust them only enough to satisfy minimum sizes. If the layout still cannot fit, float its least recently focused tiled windows until the remaining tree can fit.

There is no additional depth limit or general tree rebalancing in the initial design. Minimum sizes bound useful subdivision.

For implementation, minimum section sizes can be calculated bottom-up. A horizontal split needs the sum of its children's minimum widths plus the gap, and the larger minimum height; a vertical split uses the corresponding height sum and larger width. Use these bounds when clamping ratios, then validate the actual leaf rectangles. Retry recovery after each removal because promotion changes split axes.

## 5. Removal and temporary absence

Deleting or floating a tile removes its leaf and promotes its sibling into the removed parent's place. Removing the only tile leaves the tiled layout empty. Promotion preserves the sibling's structure, but its new depth changes subdivision directions; apply minimum-size recovery if needed.

Minimizing, hiding, or entering native fullscreen also removes a window from the tree, letting other windows expand. On return, a previously tiled window uses normal insertion; a previously floating window remains floating. No empty tile is reserved.

Distinguish those explicit lifecycle changes from transient observation failures, such as temporary inaccessibility during screen lock. Reuse the app's existing reconciliation/restoration mechanisms where practical; a missed observation alone is not a close or minimize event.

## 6. Moving tiled windows

There are two operations:

- **Section swap:** exchange the two children of the window's immediate parent. Its sibling may be one window or a whole subdivided section. The parent divider stays put; the subtree moves with its internal structure and ratios.
- **Window swap:** exchange two windows between existing leaves. The tree, divider positions, and section sizes stay unchanged; each window takes the other's rectangle.

Both operations must satisfy minimum sizes. Their difference is deliberately asymmetric:

```text
Starting layout       W1 moves right       W3 moves left
┌───────┬───────┐     ┌───────┬───────┐     ┌───────┬───────┐
│       │  W2   │     │  W2   │       │     │       │  W2   │
│  W1   ├───────┤     ├───────┤  W1   │     │  W3   ├───────┤
│       │  W3   │     │  W3   │       │     │       │  W1   │
└───────┴───────┘     └───────┴───────┘     └───────┴───────┘
                      Section swap         Window swap
```

### Dragging within a screen

- Clicking focuses a window. Within its immediate parent, dragging into its sibling along the parent's split axis performs a section swap.
- Outside that parent, dragging onto another tile performs a window swap. Gaps and empty space are not window targets.
- Rearrange live during the drag. After the first cross-parent window swap, keep the gesture in window-swap mode until release, including when it returns to the original parent.
- Keeping the pointer within the same target region does not repeatedly swap back and forth; it must leave before another swap can trigger.
- Release retains valid changes. Escape or pointer cancellation restores the pre-drag layout. The prototype treats a completed drag as one undo step; a native global undo feature is not required by this specification.

### Dragging between screens

Preview the destination while hovering; transfer only on release. Use the destination's remembered tiled target and the normal insertion rule, including floating if it cannot fit. Focus follows the transferred window.

When the drop is on another screen, **discard all intermediate swaps made during that gesture on the source screen**. Remove the window from its original position and apply ordinary collapse and minimum-size recovery there. Treat the gesture as one transfer, not a transfer plus incidental rearrangements along the pointer's route. Cancellation transfers nothing.

### Directional move commands

Moving toward the immediate sibling performs a section swap. Otherwise choose a tiled window outside the immediate parent, on the same screen, in that direction and perform a window swap. Reject an invalid swap; do not substitute a different operation. With no target, the direction is unavailable. Screen transfer is a separate operation.

Retain the prototype's target ordering: perpendicular overlap first, then nearest center along the movement axis, then nearest perpendicular center, then stable window identifier. Each command is a fresh operation and has no drag-mode memory. An opposite command therefore need not undo a prior move if the window's parent has changed.

## 7. Focus

Maintain recent-focus history per screen, including both tiled and floating windows.

- Closing the focused window selects the most recently focused surviving, available window on that screen. An empty screen has no focused window.
- Clicking selects a window; moving, resizing, floating, or retiling it keeps focus with its identity.
- Remember the most recently focused available tiled window as the insertion target. Focusing a float does not replace that target.
- Directional focus considers **tiled windows only**. Floating windows remain reachable through clicking or macOS window switching.
- If no tile is available in the requested direction on the current screen, continue to a tile on another screen in that direction, following the physical monitor arrangement and skipping empty screens. Do not wrap around.

Focus and movement are separate operations: focus can cross screens automatically at an edge; directional movement does not.

## 8. Floating eligibility

Normal, resizable application windows tile by default. Dialogs, palettes, and non-resizable windows retain appropriate floating or system-managed behavior. Use a manual float/tile toggle for eligible exceptions; no per-application rules are needed initially.

Floating windows consume no tiled space. They can be focused, dragged, resized through ordinary window interaction, nudged by move commands, transferred, or tiled again. A floating transfer keeps the window floating. Retiling follows normal insertion and remains floating if the attempted insertion cannot fit.

The prototype's smaller centered rectangle on entering floating mode is an experimental presentation default, not a requirement for the native adapter.

## 9. Screen disconnection and restart

When a screen disconnects, permanently migrate its windows to a remaining screen. Insert tiled windows **individually** through normal Outer / Inner insertion; float arrivals that cannot fit. Floating windows remain floating. Do not preserve the disconnected layout as a group for later restoration.

A newly connected or reconnected screen receives an empty tile layout; windows are not automatically moved back. Its initial orientation follows its usable shape or configured override. Reconnection does not imply that it is the same physical monitor.

Restart restoration is best effort. Reuse existing support if practical, but **do not add a persistent window-layout storage system for the initial implementation**. If layout and ratio restoration would require that extra system, rebuild from currently open windows. In-memory recovery from temporary observation loss remains useful and is distinct from restart persistence or monitor reconnection.

## 10. Engineering defaults and scope

The interview settles product behavior above. Use these modest defaults where exact mechanics were not specified:

- A square screen uses horizontal orientation. A surviving split retains its ratio when promoted onto a different axis, subject to minimum-size recovery.
- With no usable focus history, choose the last eligible leaf in tree order as the insertion target. Break other ordering ties deterministically.
- Selecting a screen restores its most recently focused available window. When an unavailable window leaves focus, use the same recent-focus fallback as deletion.
- For directional focus, reuse the move target geometry ordering without its sibling-swap rule; a floating source may supply the origin rectangle but is never a directional focus target.
- On disconnection, prefer the most recently focused remaining screen, falling back to the system's main available screen. Preserve the user's focused window during bulk migration rather than focusing every arrival. If no usable screen exists, defer placement until one becomes available.
- Previously tiled windows returning from temporary exclusion use their assigned screen if it still exists, otherwise the remaining-screen fallback. Their old tree position is not retained.
- Space becoming available does not automatically retile floating windows. Use the explicit tile action.
- Reuse existing gap, shortcut, native activation, and window-classification mechanisms where suitable. Concrete key bindings, resize increments, and preview styling can be chosen during implementation.
- Reconcile drag snapshots with concurrent window/screen lifecycle changes; cancellation must not resurrect closed windows or overwrite unrelated newly observed windows.

These defaults can be changed without reopening the selected binary structure or interaction policies.

## 11. Retained prototype and coverage

Keep the prototype as a small executable reference beside this specification: one self-contained HTML/CSS/JavaScript file, with layout logic independent of the DOM. Window content remains an identifier plus focus color; controls, model state, rectangles, and guided examples remain outside windows. It has no persistence or connection to macOS windows; refresh resets it.

| Behavior | Current prototype |
| --- | --- |
| Binary sections, depth-based directions, removal and promotion | Implemented |
| Outer / Inner for creation, retiling, returning windows, and transfers | Implemented, including centered tie rule |
| Live section/window swaps and drag cancellation | Implemented; invalid swaps leave the layout unchanged |
| Adjustable ratios and minimum sizes | Implemented; keyboard/buttons and draggable dividers clamp at minimums |
| Automatic floating and minimum-size recovery | Implemented; known per-window limits can be supplied in debug controls |
| Recent-focus history and directional focus | Implemented; arrows skip floats, cross screens, and do not wrap |
| Physical screen arrangement and orientation | Implemented; edit screen X/Y and dimensions, use Auto or an explicit root override |
| Cross-screen dragging | Implemented; preview on hover, transfer on release, discard source swaps |
| Disconnection and reconnection | Simulated; migrate individually, support deferred placement with no screens, reconnect empty |
| Minimization, hiding, native fullscreen, restoration | Simulated through debug controls; actual native events need an adapter |
| Window classification | Simulated normal/dialog/palette/non-resizable kinds; native classification remains app integration |
| Temporary observation loss and restart | Simulated; observation interruption retains state, restart demonstrates rebuilding without persistent layout storage |

The simulator starts with two 1440 × 900 screens and 12-unit gaps. Screen sizes and positions can be changed independently. These are simulation settings, not requirements for real screens. Use **All screens** for cross-screen dragging or **Active screen** for a larger view of one layout.

The prototype's concrete input choices are engineering defaults: resize buttons change the selected window's share by five percentage points at its nearest matching ancestor, clamped to minimums; divider dragging sets a continuous ratio. Arrow keys focus, Shift + arrows move, and Alt + left/right or up/down shrink/grow width or height. N creates, F toggles floating, Delete closes, and Ctrl/Cmd + Z undoes. Floating windows have an invisible resize target at their bottom-right corner, except simulated non-resizable windows.

Independent controls and simulated lifecycle events cancel an in-progress gesture before applying their change. This prevents cancellation from resurrecting a deleted window or losing a new event. The native adapter must preserve the same outcome when observations arrive asynchronously.

Guided experiments cover insertion, section/window swaps, resizing, minimum-size rejection, recovery, recent focus, screen transfers and disconnection, lifecycle events, orientation, window kinds, and the permitted restart fallback. Cross-screen pointer behavior can be exercised directly with both screens visible. All state stays in memory; the restart button simulates the chosen fallback rather than adding a storage layer.

## 12. Acceptance scenarios

- Retile and transfer at targets in each screen half: Outer / Inner must select the same side as new-window creation, for both axes.
- Resize W3 in the example: width affects the entire right column; height affects only W2/W3. Swap a 70/30 pair and verify the parent divider stays put.
- Attempt an insertion below the minimum: only the arriving window floats. Attempt an invalid swap: the complete layout remains unchanged.
- Close a window whose promotion rotates a subtree, and shrink a screen: retain valid ratios, clamp when needed, then float least-recently-focused tiles only if necessary.
- Close the focused window after visiting a float: focus returns to that float if it is the most recent surviving available window. Directional focus still skips floats.
- Focus beyond an edge with an empty screen between populated screens: continue in the physical direction without wrapping.
- Drag through several source-screen swaps and release on another screen: discard intermediate source swaps and perform exactly one transfer. Cancel the same gesture: retain the original layout, accounting for independent lifecycle changes.
- Disconnect a populated screen: migrate windows individually; reconnect a screen: do not restore or move them back.
- Minimize, hide, or fullscreen a tiled window: collapse its old position; on return, use normal insertion rather than restoring a placeholder.
- Launch a normal window with an initial rectangle on a different screen: insert on the screen that was focused when creation began.

No further product decisions are blocking the initial implementation. Persistent layout storage, per-application rules, and general rebalancing are outside its scope.
