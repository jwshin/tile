#!/usr/bin/env bash
cd "$(dirname "$0")"
source ./script/setup.sh
test_args=(--disable-xctest)
# Some Command Line Tools releases omit Swift Testing's bundled macro from discovery.
compiler_path="$(xcrun --find swiftc)"
testing_plugin="$(dirname "$compiler_path")/../lib/swift/host/plugins/testing/libTestingMacros.dylib"
if test -f "$testing_plugin" && ! command -v swiftly >/dev/null 2>&1; then
    test_args+=(-Xswiftc -load-plugin-library -Xswiftc "$testing_plugin")
fi
swift test "${test_args[@]}" "$@"
