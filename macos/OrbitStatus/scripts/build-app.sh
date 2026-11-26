#!/bin/sh
set -eu

project_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
repository_dir="$(CDPATH= cd -- "$project_dir/../.." && pwd)"
configuration="${CONFIGURATION:-release}"
output_dir="${OUTPUT_DIR:-$repository_dir/build/macos}"
version="$(tr -d '[:space:]' < "$project_dir/VERSION")"
app_dir="$output_dir/OrbitConnect.app"
extension_dir="$app_dir/Contents/Library/SystemExtensions/io.orbit.status.network-filter.systemextension"
extension_build_dir="$output_dir/.network-extension-build"
codesign_identity="${CODESIGN_IDENTITY:--}"
app_provisioning_profile="${APP_PROVISIONING_PROFILE:-}"
extension_provisioning_profile="${SYSTEM_EXTENSION_PROVISIONING_PROFILE:-}"
include_system_extension=false

if [ "$codesign_identity" != "-" ]; then
    if [ -z "$app_provisioning_profile" ] || [ ! -f "$app_provisioning_profile" ]; then
        printf '%s\n' \
            'Ошибка: для доверенной подписи нужен APP_PROVISIONING_PROFILE.' >&2
        exit 1
    fi
    if [ -z "$extension_provisioning_profile" ] || \
        [ ! -f "$extension_provisioning_profile" ]; then
        printf '%s\n' \
            'Ошибка: для доверенной подписи нужен SYSTEM_EXTENSION_PROVISIONING_PROFILE.' >&2
        exit 1
    fi
    include_system_extension=true
elif [ -n "$app_provisioning_profile" ] || \
    [ -n "$extension_provisioning_profile" ]; then
    printf '%s\n' \
        'Ошибка: provisioning profiles нельзя использовать с ad-hoc подписью.' >&2
    exit 1
fi

if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
    export DEVELOPER_DIR
fi

cd "$project_dir"
swift build -c "$configuration"
binary_path="$(swift build -c "$configuration" --show-bin-path)/OrbitStatus"

rm -rf "$app_dir"
rm -rf "$extension_build_dir"
mkdir -p \
    "$app_dir/Contents/MacOS" \
    "$app_dir/Contents/Resources"
cp "$binary_path" "$app_dir/Contents/MacOS/OrbitStatus"
cp "$project_dir/Resources/OrbitMenuIcon.png" "$app_dir/Contents/Resources/OrbitMenuIcon.png"
cp "$project_dir/Resources/AppIcon.icns" "$app_dir/Contents/Resources/AppIcon.icns"

sed "s/@VERSION@/$version/g" \
    "$project_dir/Support/Info.plist.in" > "$app_dir/Contents/Info.plist"

if [ "$include_system_extension" = true ]; then
    mkdir -p \
        "$extension_dir/Contents/MacOS" \
        "$extension_build_dir"
    sed "s/@VERSION@/$version/g" \
        "$project_dir/SystemExtension/Info.plist" > "$extension_dir/Contents/Info.plist"

    xcrun swiftc \
        -parse-as-library \
        -emit-module \
        -emit-object \
        -module-name OrbitConnectPolicy \
        "$project_dir/Sources/OrbitConnectPolicy/EgressControlPolicy.swift" \
        -o "$extension_build_dir/OrbitConnectPolicy.o" \
        -emit-module-path "$extension_build_dir/OrbitConnectPolicy.swiftmodule"

    xcrun swiftc \
        -parse-as-library \
        -emit-executable \
        -module-name OrbitConnectFilterExtension \
        -I "$extension_build_dir" \
        "$project_dir/SystemExtension/Sources/FilterDataProvider.swift" \
        "$extension_build_dir/OrbitConnectPolicy.o" \
        -framework NetworkExtension \
        -framework Security \
        -Xlinker -e \
        -Xlinker _NSExtensionMain \
        -o "$extension_dir/Contents/MacOS/OrbitConnectFilterExtension"

    cp "$extension_provisioning_profile" \
        "$extension_dir/Contents/embedded.provisionprofile"
    cp "$app_provisioning_profile" "$app_dir/Contents/embedded.provisionprofile"

    /usr/bin/codesign \
        --force \
        --sign "$codesign_identity" \
        --entitlements "$project_dir/SystemExtension/FilterExtension.entitlements" \
        "$extension_dir"
    /usr/bin/codesign \
        --force \
        --sign "$codesign_identity" \
        --entitlements "$project_dir/Support/OrbitConnect.entitlements" \
        "$app_dir"
else
    /usr/bin/codesign --force --sign - "$app_dir"
fi

rm -rf "$extension_build_dir"

if [ "$include_system_extension" = true ]; then
    printf 'Готово: %s (системный фильтр включён)\n' "$app_dir"
else
    printf 'Готово: %s (ad-hoc, без системного фильтра)\n' "$app_dir"
fi
