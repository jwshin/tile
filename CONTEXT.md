# tile

A personal window manager for keyboard-driven tiling across multiple displays.

## Language

**Display layout**: The arrangement of tiled groups and floating windows belonging to one connected display.
_Avoid_: virtual workspace

**Logical focus**: The display layout and optional window selected for the next action.

**Native focus**: The window macOS currently considers focused.

**Action execution**: The complete application of a named keyboard or menu action, including its resulting layout and focus changes.

**Configuration application**: Adoption of valid preferences together with the shortcuts that make them active.

**Restoration snapshot**: A saved arrangement used when windows disappear temporarily, such as while the screen is locked.

**Display layout state**: The current display layouts, logical focus, restoration history, and active gesture taken together.

### Tiling model

**Gesture**: One continuous window drag or resize, from its start until release or cancellation. It belongs to one display layout state, including when it crosses screens.

**Section**: A region of a display layout occupied by one tiled window or subdivided into two child sections.

**Sibling section**: The other section sharing the same immediate parent.

**Section swap**: An exchange of two sibling sections, including any windows and subdivisions they contain.

**Window swap**: An exchange of individual windows between existing tiled sections.

**Outer placement**: Placement of a new window toward the nearer screen edge along the split direction.

**Inner placement**: Placement of a new window on the opposite side from outer placement, toward the screen center.

**Tiled insertion target**: The existing tile selected to share its section with an arriving tiled window.

**Minimum tile size**: The smallest permitted tiled rectangle for a window, combining tile's baseline size with larger known application limits.

**Screen focus history**: The recent ordering of focused windows on one screen, including tiled and floating windows.
