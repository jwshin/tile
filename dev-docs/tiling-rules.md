# tile tiling rules

Living decision document for tile’s tiling algorithm, incorporating the design interview completed on 2026-09-27. This is the authoritative record of accepted behavior. Smaller engineering defaults are identified separately so they are not mistaken for explicit user choices.

The retained [layout prototype](layout-prototype.html) implements these layout decisions and simulates window and screen lifecycle events. The native app now implements these policies through its binary model and macOS adapters; simulated coverage does not replace interactive native validation. Open the HTML directly in Chrome; no server or dependencies are required.

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

Every new split starts at **50/50** after accounting for the gap. Support keyboard and mouse resizing, retaining the resulting ratio for that split. Resizing a window edge must not exchange window positions, even when the edge changes both position and size. Resizing adjusts the nearest ancestor split on the requested axis. In the example, resizing W3 horizontally adjusts the W1/right-column boundary; resizing it vertically adjusts the W2/W3 boundary.

During a native pointer resize, passive refreshes must preserve the held window's native frame even before its first move/resize observation arrives. Cancel obsolete queued frame writes when protecting that window or recognizing its gesture. Neighboring windows follow the observed split; after release, ordinary layout writes resume. Explicit keyboard/menu actions and lifecycle cancellation still apply their resulting layout.

A move carries the selected window’s allocation: horizontal moves preserve its actual width, and vertical moves preserve its actual height. Destination columns or rows and their ancestors adjust around it. Moving a wide window right in a 70% left / 30% right split makes it 30/70; moving a narrow window into the wide side likewise preserves the narrow window’s width. This supersedes the earlier decision to leave dividers fixed. Other ratios stay unchanged where possible and adjust as needed for minimum sizes.

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

The minimum tile size is **160 × 100 logical points**. This engineering default replaces 320 × 200 so smaller laptop screens allow more subdivision and resizing before reaching the baseline. It is a lower bound, not a preferred window size. Larger window-specific minimums take precedence when known. Lack of a reliable application minimum must not prevent operation: use the baseline and handle observed constraints through the native window adapter.

- Clamp interactive resizing before any affected leaf falls below its minimum.
- Float an arriving window when insertion cannot fit, including on an otherwise empty screen.
- When moving, redistribute space to preserve the selected window’s width or height and satisfy all window minimums. A narrower destination alone is not a reason to reject or float a window. Commit the structural swap and ratio changes together. If that tree structure cannot represent the required allocation, leave the whole layout unchanged; do not silently shrink the selected window or float other windows to complete the move.
- For unavoidable changes, such as a shrinking screen or rotation after deletion, preserve ratios where possible; otherwise adjust them only enough to satisfy minimum sizes. If the layout still cannot fit, float its least recently focused tiled windows until the remaining tree can fit.

There is no additional depth limit or general tree rebalancing in the initial design. Minimum sizes bound useful subdivision.

For implementation, minimum section sizes can be calculated bottom-up. A horizontal split needs the sum of its children's minimum widths plus the gap, and the larger minimum height; a vertical split uses the corresponding height sum and larger width. Use these bounds when clamping ratios, then validate the actual leaf rectangles. Retry recovery after each removal because promotion changes split axes.

## 5. Removal and temporary absence

Deleting or floating a tile removes its leaf and promotes its sibling into the removed parent's place. Removing the only tile leaves the tiled layout empty. Promotion preserves the sibling's structure, but its new depth changes subdivision directions; apply minimum-size recovery if needed.

Minimizing, hiding, or entering native fullscreen also removes a window from the tree, letting other windows expand. On return, a previously tiled window uses normal insertion; a previously floating window remains floating. No empty tile is reserved.

Distinguish those explicit lifecycle changes from transient observation failures, such as temporary inaccessibility during screen lock. Reuse the app's existing reconciliation/restoration mechanisms where practical; a missed observation alone is not a close or minimize event.

## 6. Moving tiled windows

There are two operations:

- **Section swap:** exchange the two children of the window's immediate parent. Its sibling may be one window or a whole subdivided section. The subtree moves with its internal structure. The parent divider adjusts so the selected window keeps its size along the movement axis; other ratios change only where required by minimum sizes.
- **Window swap:** exchange two windows between existing leaves. The tree structure stays unchanged. Adjust destination and ancestor dividers to preserve the selected window’s width on a horizontal move or height on a vertical move. Other windows share the remaining space while respecting their minimums.

Both operations must preserve the selected dimension and satisfy minimum sizes. For mouse swaps, the split where the source and destination paths diverge determines the movement axis. Keyboard commands use their requested axis. Cross-screen transfers continue to use the separately agreed insertion rule. The structural distinction between the two swaps is deliberately asymmetric:

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
- Keeping the pointer within the same target region does not repeatedly swap back and forth; it must leave before another swap can trigger. Hovering another screen also clears that target region, so returning over a sibling can immediately swap again.
- Release retains valid changes. Escape or pointer cancellation restores the pre-drag layout. The prototype treats a completed drag as one undo step; a native global undo feature is not required by this specification.

### Dragging between screens

Preview the destination while hovering; transfer only on release. Use the destination's remembered tiled target and the normal insertion rule, including floating if it cannot fit. Focus follows the transferred window.

When the drop is on another screen, **discard all intermediate swaps made during that gesture on the source screen**. Remove the window from its original position and apply ordinary collapse and minimum-size recovery there. Treat the gesture as one transfer, not a transfer plus incidental rearrangements along the pointer's route. Cancellation transfers nothing.

### Directional move commands

Moving toward the immediate sibling performs a section swap. Otherwise choose a tiled window outside the immediate parent, on the same screen, in that direction and perform a window swap. Redistribute the existing space along with the swap; do not substitute a different structural operation. With no target, the direction is unavailable. Screen transfer is a separate operation.

Retain the prototype's target ordering: perpendicular overlap first, then nearest center along the movement axis, then nearest perpendicular center, then stable window identifier. Each command is a fresh operation and has no drag-mode memory. An opposite command therefore need not undo a prior move if the window's parent has changed.

## 7. Focus

Maintain recent-focus history per screen, including both tiled and floating windows.

- Closing the focused window selects the most recently focused surviving, available window on that screen. An automatic replacement reported by macOS during that departure must not overwrite the prior recent-focus history. Apply the selected fallback to native focus as well. An empty screen has no focused window.
- Clicking selects a window; moving, resizing, floating, or retiling it keeps focus with its identity.
- Remember the most recently focused available tiled window as the insertion target. Focusing a float does not replace that target.
- Directional focus considers **tiled windows only**. Floating windows remain reachable through clicking or macOS window switching.
- If no tile is available in the requested direction on the current screen, continue to a tile on another screen in that direction, following the physical monitor arrangement and skipping empty screens. Do not wrap around.

Focus and movement are separate operations: focus can cross screens automatically at an edge; directional movement does not.

## 8. Floating eligibility

Normal, resizable application windows tile by default. Dialogs, palettes, and non-resizable windows retain appropriate floating or system-managed behavior. The `floating-apps` configuration list selects apps whose newly detected managed windows float by default. Match exact, case-sensitive bundle IDs, including IDs outside the built-in compatibility list. The default is an empty list. Popups and overlays remain unmanaged even when their app matches.

Claude (`com.anthropic.claudefordesktop`) has a narrow compatibility exception: a standard, resizable main window at the normal window level remains eligible to tile when its Accessibility fullscreen button is missing or disabled. The exception does not bypass the standard-window subrole check, resizability, minimum-size checks, or `floating-apps`. Claude dialogs remain floating, and its windows at non-normal levels remain unmanaged overlays. Classification uses Accessibility attributes rather than the presence of an “Enter Full Screen” menu item.

Reloading `floating-apps` affects future classifications, including fresh discovery after restarting tile; it does not retile or float existing windows. Manual float/tile toggles remain available, subject to resizability and minimum sizes. A manual choice survives transfers and minimize/hide/fullscreen return; it is not a persistent per-window preference across restarts.

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
- Entering native fullscreen removes the window from tiling but must not activate a replacement window or pull macOS back to another Space. A Space-change refresh must likewise preserve native activation, including discarding queued recovery across cancellation. Logical focus may select an available tile for later commands; close and minimize still apply recent-focus recovery.
- For directional focus, reuse the move target geometry ordering without its sibling-swap rule; a floating source may supply the origin rectangle but is never a directional focus target.
- On disconnection, prefer the most recently focused remaining screen, falling back to the system's main available screen. Preserve the user's focused window during bulk migration rather than focusing every arrival. If no usable screen exists, defer placement until one becomes available.
- Previously tiled windows returning from temporary exclusion use their assigned screen if it still exists, otherwise the remaining-screen fallback. Their old tree position is not retained.
- Space becoming available does not automatically retile floating windows. Use the explicit tile action.
- Reuse existing gap, shortcut, native activation, and window-classification mechanisms where suitable. Concrete key bindings, resize increments, and preview styling can be chosen during implementation.
- Reconcile drag snapshots with concurrent window/screen lifecycle changes; cancellation must not resurrect closed windows or overwrite unrelated newly observed windows. Each display layout state owns its gesture, manipulation tracking, and preview. Changes to another state must not cancel it, even when window identifiers match. After lifecycle cancellation, ignore further movement from the held pointer until release.

These defaults can be changed without reopening the selected binary structure or interaction policies.

## 11. Retained prototype and coverage

Keep the prototype as a small executable reference beside this specification: one self-contained HTML/CSS/JavaScript file, with layout logic independent of the DOM. Window content remains an identifier plus focus color; controls, model state, rectangles, and guided examples remain outside windows. It has no persistence or connection to macOS windows; refresh resets it.

| Behavior | Current prototype |
| --- | --- |
| Binary sections, depth-based directions, removal and promotion | Implemented |
| Outer / Inner for creation, retiling, returning windows, and transfers | Implemented, including centered tie rule |
| Live section/window swaps and drag cancellation | Implemented in the model-owned gesture session; independent owners and lifecycle cancellation have a guided scenario; moves preserve the selected width/height |
| Adjustable ratios and minimum sizes | Implemented; keyboard/buttons and draggable dividers clamp at 160 × 100 or larger known minimums; laptop scenario covers nested insertion; native resize timing simulates the first-observation delay and protected frame writes |
| Automatic floating and minimum-size recovery | Implemented; known per-window limits can be supplied in debug controls |
| Recent-focus history and directional focus | Implemented; arrows skip floats, cross screens, and do not wrap |
| Physical screen arrangement and orientation | Implemented; edit screen X/Y and dimensions, use Auto or an explicit root override |
| Cross-screen dragging | Implemented; preview on hover, transfer on release, discard source swaps |
| Disconnection and reconnection | Simulated; migrate individually, support deferred placement with no screens, reconnect empty |
| Minimization, hiding, native fullscreen, restoration | Simulated through debug controls; fullscreen/Space guided scenario separates native from logical focus; actual native events need an adapter |
| Window classification | Simulated normal/dialog/palette/non-resizable kinds, unmanaged non-normal overlays, exact bundle-ID floating preferences, and Claude’s missing/disabled fullscreen-button exception; raw Accessibility attributes and native classification remain app integration |
| Temporary observation loss and restart | Simulated; observation interruption retains state, restart demonstrates rebuilding without persistent layout storage |

The simulator starts with two 1440 × 900 screens and 12-unit gaps. Screen sizes and positions can be changed independently. These are simulation settings, not requirements for real screens. Use **All screens** for cross-screen dragging or **Active screen** for a larger view of one layout.

The prototype's concrete input choices are engineering defaults: resize buttons change the selected window's share by five percentage points at its nearest matching ancestor, clamped to minimums; divider dragging sets a continuous ratio. Arrow keys focus, Shift + arrows move, and Alt + left/right or up/down shrink/grow width or height. N creates, F toggles floating, Delete closes, and Ctrl/Cmd + Z undoes. Floating windows have an invisible resize target at their bottom-right corner, except simulated non-resizable windows.

The display layout state owns gesture transitions in the DOM-independent model. Independent controls and simulated lifecycle events cancel that state’s in-progress gesture before applying their change. Stale movement, release, or cancellation cannot resurrect a deleted window or lose a new event. A separate model’s lifecycle events leave the first model’s gesture intact. The **Gesture ownership** guided scenario exercises both cases. **Floating cancellation** also verifies that stale movement retains the restored floating rectangle and an independent creation. The native adapter must preserve the same outcome when observations arrive asynchronously.

Browser `pointercancel` ends the input stream: restore the gesture’s original layout and accept the next drag immediately, without waiting for a `pointerup` that will not follow. Escape, lost pointer capture, and lifecycle edits can cancel while the pointer remains held; block further drag attempts until release or terminal browser cancellation, including when that event arrives outside the board. The **Pointer cancellation** guided scenario demonstrates terminal cancellation during a live swap and a transfer preview.

Guided experiments cover floating-app preferences and manual overrides, insertion, section/window swaps, resizing, minimum-size rejection, recovery, recent focus, screen transfers and disconnection, lifecycle events, orientation, window kinds, and the permitted restart fallback. Cross-screen pointer behavior can be exercised directly with both screens visible. All state stays in memory; the restart button simulates the chosen fallback rather than adding a storage layer.

The **Native resize timing** scenario displays a simulated native frame before the model observes it, refreshes while the pointer is held, delivers the observation, then releases. It makes the protected window and neighboring frame-write policy executable. It does not reproduce macOS AX thread scheduling, in-flight calls, or display animation.

The **Claude window eligibility** scenario exercises missing and disabled fullscreen buttons on standard resizable windows, then verifies that dialogs and fixed windows float, non-normal overlays leave the managed layout and focus unchanged, and explicit floating-app preferences still apply. Unmanaged overlay events change only the simulator’s status message: they preserve native fullscreen focus, logical focus, and any active gesture or transfer preview. The **New window fullscreen button** selector supplies simulated metadata for the regular creation control; the existing kind selector supplies dialog/fixed/overlay cases. This focused simulation models Claude’s exception and the generic fallback, not every native app compatibility rule. An omitted button in a UI inspection tree does not establish that its raw Accessibility attribute is absent or disabled.

## 12. Acceptance scenarios

- Retile and transfer at targets in each screen half: Outer / Inner must select the same side as new-window creation, for both axes.
- Resize W3 in the example: width affects the entire right column; height affects only W2/W3. Move the wide window across a 70/30 split and verify the split becomes 30/70 while its width stays unchanged. Move a narrow window into a wider destination and verify that its width also stays unchanged.
- Attempt an insertion below the minimum: only the arriving window floats. Move an existing wide window into the narrow destination: grow the destination to its previous width. Exercise a nested destination that needs both local and ancestor dividers adjusted, and verify exact width and every window’s minimum. If the required allocation cannot be represented, verify that the entire move remains unchanged.
- On a 1280 × 800 usable screen, split a half-width column again and then split its half-height tile. Accept tiles below the former 320 × 200 baseline, clamp at 160 × 100, and still reject an insertion that violates a larger known application minimum. Actual application limits and their Accessibility feedback require native validation.
- Close a window whose promotion rotates a subtree, and shrink a screen: retain valid ratios, clamp when needed, then float least-recently-focused tiles only if necessary.
- Close the focused window after visiting a float: focus returns to that float if it is the most recent surviving available window. Directional focus still skips floats.
- Focus beyond an edge with an empty screen between populated screens: continue in the physical direction without wrapping.
- Swap unequal-width sections, hover another screen, and return over the sibling inside the former target region: permit a new swap without requiring an extra detour.
- Resize a tile from its left or top edge: adjust the split while keeping window identities in place. Native move/resize notification order must not affect this outcome.
- Start a native edge resize, then refresh before handling its first observation: retain the native edge rather than writing the old tile rectangle back. Cancel an earlier queued write, process repeated observations/refreshes, and release; neighbors follow the split without repeatedly resetting the held window.
- Close or minimize the focused tile after focusing a float: select the float, including when macOS initially reports another window as focused.
- Drag through several source-screen swaps and release on another screen: discard intermediate source swaps and perform exactly one transfer. Cancel the same gesture: retain the original layout, accounting for independent lifecycle changes.
- During a live swap or transfer preview, create or close a window or disconnect its screen. Cancel the gesture before applying that event; ignore stale movement until release and retain the event after stale release/cancel. Mutate a separate display layout state with matching window IDs: its changes must leave the first gesture and preview intact.
- Cancel a browser pointer stream during a live swap: restore the original layout, then start the next drag without an extra click. Cancel with Escape or a lifecycle edit while held: reject a new drag until `pointerup` or `pointercancel`, even outside the board, and preserve the lifecycle edit.
- Disconnect a populated screen: migrate windows individually; reconnect a screen: do not restore or move them back.
- Minimize, hide, or fullscreen a tiled window: collapse its old position; on return, use normal insertion rather than restoring a placeholder.
- Add an app to `floating-apps`: its existing windows stay put; a new matching window floats. Tile it manually, transfer it, and minimize/restore it: retain the manual choice. Remove the rule: only future windows return to automatic classification. Matching must not turn unmanaged popups into managed floats.
- Create standard resizable Claude windows with missing and disabled Accessibility fullscreen buttons: tile both when insertion fits. Keep Claude dialogs and fixed windows floating and non-normal overlays unmanaged. Apply an explicit Claude floating-app preference: future managed windows float. Confirm that the generic missing-button fallback still floats an app without this exception.
- Launch a normal window with an initial rectangle on a different screen: insert on the screen that was focused when creation began.

No further product decisions are blocking the initial implementation. Persistent layout storage, general rule scripting, and general rebalancing are outside its scope; the `floating-apps` list is the supported app-level exception.

## 13. Native implementation and validation boundary

The native app implements the accepted rules in `BinaryLayout`, `Workspace`, `DisplayLayoutState`, and
`MouseTiling`. Direction follows depth; moves preserve the selected dimension through allocation bounds;
all insertions share Outer/Inner and the same 50/50 fit check. Focus history includes floats, and native
minimize/hide/fullscreen handling keeps unavailable windows outside the tree. Disconnect migrates leaves
individually and preserves the focused window.

Native focus reconciliation processes departures before importing the observed native focus. Pending fallback survives cancellation and is applied by the next completed refresh or action, except during native fullscreen or Space transitions, which discard recovery to preserve macOS activation. Mouse gesture classification uses the observed frame delta against the last successfully applied native size, including application rounding. Move and resize notifications share the same path; even a small resize must not become a swap across a narrow gap.

Passive refreshes protect the native-focused window while the pointer is down and no gesture or cancellation is registered yet, including optimistic pre-layout. Registered gestures continue to protect their owned window. Both paths cancel obsolete queued AX frame requests and ignore their later size callbacks. Only accepted pointer samples cancel old writes; blocked samples must retain queued floating restoration or independent-action frames. Explicit actions use their normal layout path. Adapter replay tests cover refresh-before-observation snap-back, delayed writes, repeated edge samples, and floating restoration after stale observations. Native refresh awaits focus/fullscreen AX reads before cancelling queued writes, so their ordering against earlier writes remains an integration boundary; an AX call already executing cannot be interrupted. Real Chrome resize flicker remains a native smoke test with the patched build.

The 2026-09-29 investigation replayed a 120-point leading-edge resize on both release 0.3.0 (`041d4af0`, immediately before gesture ownership refactoring) and unpatched 0.4.0. Both reset the native X position from 844 to 964 and width from 1068 to 948 when a refresh preceded the first observation. This establishes that this specific snap-back race predates `d3be185e`; it does not establish that every flicker in the attached recording has that cause.

Native engineering choices: `floating-apps` is an array of bundle-ID strings and defaults to `[]`; invalid array entries reject the entire reload. `new-window-placement` defaults to `outer`; `root-orientation` defaults to
`auto` and accepts `horizontal`/`vertical`. Flipping orientation gives the active screen an in-memory
override. Keyboard width/height resize uses 50-point increments. A translucent outline previews screen
transfer (blue for tiling, orange for floating). Fixed-window eligibility uses Accessibility's settable-size
capability; unknown capability is allowed. Two matching successful native size writes exceeding the
requested dimension by more than 32 points can teach a larger minimum. Smaller discrepancies are
ignored to avoid mistaking terminal cell snapping for an application minimum. The adapter ignores stale requests and active manipulation.
There is no persistent layout or minimum-size store.

Swift acceptance tests cover moves in both axes and directions, nested allocation, atomic failures,
minimum clamps/recovery, insertion, focus, transfers, cancellation, native-state transitions, screen
migration, and transient observation restoration through test adapters. Regression cases cover automatic replacement focus, cancelled reconciliation, leading-edge resizing across narrow gaps, ordinary dragging after application size rounding, and returning from cross-screen hover. The retained prototype's guided
controls and pointer handlers are also exercised through a DOM event simulation. These checks do **not**
validate actual Accessibility timing, native preview rendering, or real monitor hardware. Real application
drag/resize, unplug/reconnect, lock/unlock, and fullscreen smoke tests remain manual validation.

The [native validation record](development.md#native-validation-record-2026-09-28) lists the outstanding desktop checks and the local environment limitation. Prototype lifecycle controls and Swift adapters cannot validate macOS notification timing or physical display changes.

Issue #5 validation boundary: adapter regressions cover fullscreen focus preservation, Space-change departures, and interrupted Space reconciliation. The fullscreen/Space prototype scenario models activation separately. Real fullscreen animations, moving windows between Spaces, AX notification ordering, and desktop focus remain manual checks; this change does not implement per-Space layouts or claim to resolve every transient AX identity failure.

Gesture ownership validation: Swift regressions cover independent state instances, matching window IDs, preview cleanup, frame-write and size-feedback isolation, restoration invalidation, and cancellation until release. The prototype’s model and guided controls exercise interruption by creation, close, and screen disconnection. Pointer-adapter regressions simulate browser cancellation and release both during a drag and after Escape or lifecycle cancellation; rendering is stubbed in these tests. Actual pressed-button sampling, Accessibility notification ordering, native preview rendering, and physical displays remain native integration checks.

Claude classification validation: the prototype’s guided controls cover the narrow exception and its dialog, fixed-window, overlay, and explicit-preference boundaries. Live raw Accessibility attributes, actual window classification, native resizing, and behavior after rediscovery with the patched app remain unverified native integration checks. The observed UI tree alone is not a raw Accessibility dump and does not establish the cause of the reported untiled window.
