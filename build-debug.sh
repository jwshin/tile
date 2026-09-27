#!/usr/bin/env bash
cd "$(dirname "$0")"
source ./script/setup.sh
swift build --product tile "$@"
mkdir -p .debug
cp "$(swift build --show-bin-path)/tile" .debug/tile
