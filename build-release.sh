#!/usr/bin/env bash
cd "$(dirname "$0")"
source ./script/setup.sh
codesign_identity="${TILE_CODESIGN_IDENTITY:--}"
version="$(sed -nE 's/^public let appVersion = "([0-9]+\.[0-9]+\.[0-9]+)"$/\1/p' Sources/Common/version.swift)"
if [[ -z "$version" ]]; then
    printf 'Expected a numeric major.minor.patch version in Sources/Common/version.swift\n' >&2
    exit 1
fi
swift build -c release --product tile
app_path="${1:-.release/tile.app}"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/tile" "$app_path/Contents/MacOS/tile"
cp resources/default-config.toml LICENSE.txt "$app_path/Contents/Resources/"
cp resources/tile.icns "$app_path/Contents/Resources/"
cp -R legal "$app_path/Contents/Resources/"
cat > "$app_path/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.jwshin.tile</string>
<key>CFBundleName</key><string>tile</string>
<key>CFBundleExecutable</key><string>tile</string>
<key>CFBundleIconFile</key><string>tile.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>$version</string>
<key>CFBundleShortVersionString</key><string>$version</string>
<key>LSMinimumSystemVersion</key><string>27.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign "$codesign_identity" "$app_path"
codesign --verify --strict "$app_path"
printf 'Built %s\n' "$app_path"
