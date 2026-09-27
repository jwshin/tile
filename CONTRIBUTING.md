# Development of this personal fork

This repository is tile, a reduced window manager for keyboard-driven tiling across multiple monitors.
Read [the architecture](dev-docs/architecture.md) and [development guide](dev-docs/development.md)
before changing window-management behavior.

Keep configuration limited to shortcuts, one gap value, and floating-app exceptions. Bindings select
named actions from `Sources/AppBundle/command/Action.swift`; there is no CLI or command server.

Run `./test.sh` before submitting changes. For changes to native window handling, also perform the
multi-monitor desktop checks described in the development guide. Describe the behavior changed and
what you verified in the pull request.

For a problem in this fork, record the reproduction steps, personal configuration, macOS version,
and any runtime diagnostic. Diagnose it here before treating it as an upstream issue.

Contributions are licensed under the repository's MIT license. Preserve upstream copyright notices
and the third-party notices in `legal/`.
