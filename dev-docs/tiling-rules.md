# tile tiling rules

This is the working specification for the retained [layout prototype](layout-prototype.html). It records the binary layout design explored so far; the native macOS app does not yet implement this specification. Open the HTML file directly in Chrome to try the rules. No server or dependencies are required.

The structural and movement rules below are the selected design. Details explicitly marked **working defaults** or **open** remain available for experimentation.

## 1. Screens and sections

- Each screen owns an independent tiled layout and a collection of floating windows.
- An empty screen has no tiled section. Otherwise its root section covers the usable tiling area.
- A section contains either one window or exactly two child sections. A section never contains a list of windows alongside child sections.
- Each tiled window occupies exactly one leaf section. Every window belongs to exactly one screen and is either tiled or floating.
- Child order determines position: first means left or top; second means right or bottom.

Example: `[W1, [W2, W3]]` on a screen with a horizontal root:

```text
┌──────────┬──────────┐
│          │    W2    │
│    W1    ├──────────┤
│          │    W3    │
└──────────┴──────────┘
```

## 2. Split direction and size

Each screen has a root direction, horizontal by default. Here **horizontal** means children sit left/right; **vertical** means top/bottom. Each deeper level uses the opposite direction. Direction follows current depth rather than remaining attached to a section.

**Working defaults:** every split divides the available space 50/50 after its gap. The prototype uses 1440 × 900 screens with 12-unit outer and inner gaps. These dimensions are simulator settings, not requirements for real displays. There is currently no resizing, minimum tile size, depth limit, or automatic balancing.

## 3. Creating a window

1. On an empty tiled layout, the new window fills the tiling area.
2. Otherwise split the focused tiled window's section into two children: the existing window and the new window. The split direction follows that section's depth.
3. If focus is floating, use the screen's remembered tiled window; if it is no longer present, use the last leaf in tree order. This is a single remembered window, not a full focus history.
4. Focus follows the new window.

**Outer / Inner** controls which child receives the new window. The setting applies to future creation across all screens; changing it does not rearrange existing windows. Outer is the default.

Compare the target window's center with the screen midpoint along the new split's axis:

| Target position along that axis | Outer | Inner |
| --- | --- | --- |
| Left half | New window on the left | New window on the right |
| Right half | New window on the right | New window on the left |
| Top half | New window above | New window below |
| Bottom half | New window below | New window above |

Outer means toward the nearer **screen edge**; Inner means the opposite side, toward the screen center. This rule applies at every depth. **Working tie rule:** exactly centered targets use right/bottom for Outer and left/top for Inner.

For the example above, creating while W2 is focused splits W2 left/right. Outer creates to its right; Inner creates to its left. Mirroring the column to the left reverses those results.

## 4. Removing a tile

Deleting or floating a tiled window removes its leaf. Its sibling takes the removed parent's place. Removing the only tiled window leaves an empty tiled layout.

If the promoted sibling is itself subdivided, its depth decreases and all split directions in that subtree change accordingly. This rotation is intentional: directions always follow depth. No other balancing is performed.

## 5. Moving tiled windows

There are two operations:

- **Section swap:** exchange the two children of the window's immediate parent. Its sibling may be a window or an entire subdivided section. A subdivided sibling moves intact, with the same internal structure and depth.
- **Window swap:** exchange two windows between their existing leaf sections. The split structure and section sizes stay unchanged; each window takes the other section's rectangle.

The distinction is deliberately asymmetric in this example:

```text
Starting layout       W1 moves right       W3 moves left
┌───────┬───────┐     ┌───────┬───────┐     ┌───────┬───────┐
│       │  W2   │     │  W2   │       │     │       │  W2   │
│  W1   ├───────┤     ├───────┤  W1   │     │  W3   ├───────┤
│       │  W3   │     │  W3   │       │     │       │  W1   │
└───────┴───────┘     └───────┴───────┘     └───────┴───────┘
                      Section swap         Window swap
```

### Mouse dragging

- Clicking focuses a window. Dragging within its immediate parent swaps it with the sibling section when the pointer crosses into the sibling along the parent's split axis.
- Dragging outside that parent onto another tiled window swaps the individual windows. Gaps and empty space are not window targets. Targets stay on the same screen.
- Changes appear during the drag. After the first cross-parent window swap, the gesture stays in window-swap mode until release, including when dragged back into the original parent.
- Keeping the pointer in the same target region does not repeatedly swap back and forth; leave that region to allow another swap.
- Release keeps the result. Escape or pointer cancellation restores the layout from the start of the drag. One completed drag is one layout undo step.

### Directional move controls

Moving toward the immediate sibling performs a section swap. Otherwise choose a tiled window outside the immediate parent in that direction and perform a window swap. With no eligible target, the direction is unavailable.

**Working target selection:** prefer candidates overlapping the source on the perpendicular axis, then the smallest center distance along the movement axis, then perpendicular center distance, then window identifier. Each button press is a new operation; it does not retain a drag's window-swap mode. Consequently, an opposite button press is not guaranteed to undo a previous move if the window's parent has changed.

## 6. Floating windows

Floating windows occupy independent rectangles above the tiled layout and consume no tiled space. They can be focused, freely dragged within the screen, nudged with the move controls, deleted, or tiled again. Changing between tiled and floating retains focus on that window.

**Working defaults:** floating gives a window a smaller rectangle centered near its former tile, constrained to the screen. Tiling again splits the remembered tiled window, placing the returning window second (right/bottom), or fills an empty layout. It does not restore the old tree position. Outer / Inner currently applies only to newly created windows, not returning floating windows.

## 7. Focus and multiple screens

Focus identifies one window and its active screen. Creating, clicking, moving, or transferring a window keeps focus with that window's identity. Each screen remembers a tiled insertion target; focusing a float does not replace that target.

The prototype shows two independent screens, one at a time. Each has its own root direction. “Other screen” removes the focused window from its source and inserts it into the destination; focus follows it. Floating windows remain floating. A transferred tiled window currently splits the destination's remembered target and goes second, regardless of Outer / Inner.

**Working focus fallback:** after deletion, select the next window in tree order followed by floating order, or the previous final window if there is no next one. An empty screen has no focused window. Selecting a screen prefers its tiled target, then its last floating window. These are deterministic prototype defaults, not an agreed focus-history policy.

## 8. Keeping the prototype useful

Keep the prototype as a small executable reference beside this document. It remains one self-contained HTML/CSS/JavaScript file, with the layout model independent of the DOM. Window content stays limited to an identifier and focus color; debug controls, tree state, calculated rectangles, and guided examples stay outside the windows.

Use the “Outer vs inner,” “Mirror the column,” “Window & section moves,” “Collapse & rotate,” “Floating,” and “Two screens” scenarios to check changes. Refreshing resets the prototype; it has no persistence or connection to macOS windows. Update this document and the prototype together when a design decision changes.

## 9. Open design questions

- Should Outer / Inner also control retiling and transfers?
- Should retiling restore a previous position? What focus history should deletion and screen selection use?
- Should splits support resizing, minimum sizes, or a maximum useful depth?
- Should pointer dragging work between screens, and how should differently sized screens, disconnects, and reconnects behave?
- How should the native app handle window size constraints, fullscreen/minimized windows, temporary disappearance, and saved state?

These questions do not change the selected binary structure or the distinction between section swaps and window swaps.
