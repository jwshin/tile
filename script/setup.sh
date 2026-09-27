#!/usr/bin/env bash
set -euo pipefail
# Prefer the repository's pinned toolchain when swiftly is available.
swift() {
    if command -v swiftly >/dev/null 2>&1; then
        command swiftly run swift "$@"
    else
        command swift "$@"
    fi
}
