#!/usr/bin/env bash
cd "$(dirname "$0")"
source ./script/setup.sh

# Keep distribution bundles separate from a running development installation.
output_dir="${1:-.release/dist}"
app_path="$output_dir/tile.app"
./build-release.sh "$app_path"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")"
arch="$(lipo -archs "$app_path/Contents/MacOS/tile")"
if [[ "$arch" != arm64 ]]; then
    printf 'The release cask supports arm64; this build contains %s\n' "$arch" >&2
    exit 1
fi
asset="tile-$version-macos-arm64.zip"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$output_dir/$asset"
(cd "$output_dir" && shasum -a 256 "$asset" > "$asset.sha256")
printf 'Packaged %s/%s\n' "$output_dir" "$asset"
