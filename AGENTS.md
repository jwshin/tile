# Tiling design workflow

When discussing or changing tiling behavior, read [dev-docs/tiling-rules.md](dev-docs/tiling-rules.md), the authoritative record of accepted decisions.

Keep that document and [dev-docs/layout-prototype.html](dev-docs/layout-prototype.html) synchronized in the same change. Update the affected rule, executable behavior, and a guided scenario; exercise the affected controls before considering the change complete. Record native-only integration boundaries explicitly in the coverage notes.

Keep the retained prototype runnable as a single self-contained HTML/CSS/JavaScript file, with its model independent of the DOM. Use simulation controls for native lifecycle events. Future native implementation changes must remain consistent with the documented decisions and prototype.
