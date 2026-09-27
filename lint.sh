#!/usr/bin/env bash
cd "$(dirname "$0")"
source ./script/setup.sh
swift build --product tile -Xswiftc -warnings-as-errors
