#!/bin/sh
set -eu

project_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
repository_dir="$(CDPATH= cd -- "$project_dir/../.." && pwd)"
configuration="${CONFIGURATION:-release}"
output_dir="${OUTPUT_DIR:-$repository_dir/build/macos}"
version="$(tr -d '[:space:]' < "$project_dir/VERSION")"
app_dir="$output_dir/OrbitConnect.app"
codesign_identity="${CODESIGN_IDENTITY:--}"
swift_build_flags="${SWIFT_BUILD_FLAGS:-}"

if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
    export DEVELOPER_DIR
fi

cd "$project_dir"
# Intentional word splitting lets local verification pass SwiftPM flags such as
# --disable-sandbox without changing release defaults.
# shellcheck disable=SC2086
swift build -c "$configuration" $swift_build_flags
# shellcheck disable=SC2086
binary_path="$(swift build -c "$configuration" $swift_build_flags --show-bin-path)/OrbitStatus"
# shellcheck disable=SC2086
agent_path="$(swift build -c "$configuration" $swift_build_flags --show-bin-path)/OrbitConnectAgent"

rm -rf "$app_dir"
mkdir -p \
    "$app_dir/Contents/MacOS" \
    "$app_dir/Contents/Resources"
cp "$binary_path" "$app_dir/Contents/MacOS/OrbitStatus"
cp "$agent_path" "$app_dir/Contents/Resources/OrbitConnectAgent"
cp "$project_dir/Support/io.orbit.connect.agent.plist" \
    "$app_dir/Contents/Resources/io.orbit.connect.agent.plist"
cp "$project_dir/Resources/OrbitMenuIcon.png" "$app_dir/Contents/Resources/OrbitMenuIcon.png"
cp "$project_dir/Resources/AppIcon.icns" "$app_dir/Contents/Resources/AppIcon.icns"

sed "s/@VERSION@/$version/g" \
    "$project_dir/Support/Info.plist.in" > "$app_dir/Contents/Info.plist"

/usr/bin/codesign --force --sign "$codesign_identity" \
    "$app_dir/Contents/Resources/OrbitConnectAgent"
/usr/bin/codesign --force --sign "$codesign_identity" "$app_dir"

printf 'Готово: %s (встроенный системный kill switch)\n' "$app_dir"
