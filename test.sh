#!/usr/bin/env bash
cd "$(dirname "$0")"
source ./script/setup.sh
./swift-test.sh "$@"
./build-debug.sh -Xswiftc -warnings-as-errors
