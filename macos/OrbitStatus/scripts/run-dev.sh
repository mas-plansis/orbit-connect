#!/bin/sh
set -eu

demo=0
restart=0
for argument in "$@"; do
    case "$argument" in
        --demo) demo=1 ;;
        --restart) restart=1 ;;
        *)
            printf 'Неизвестный аргумент: %s\n' "$argument" >&2
            printf 'Использование: %s [--demo] [--restart]\n' "$0" >&2
            exit 2
            ;;
    esac
done

project_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
runtime_dir="${ORBIT_CONNECT_DEV_DIR:-/tmp/orbit-connect-development}"
mkdir -p "$runtime_dir"
runtime_dir="$(CDPATH= cd -- "$runtime_dir" && pwd -P)"
build_dir="$runtime_dir/swift-build"
app_dir="$runtime_dir/OrbitConnectDevelopment.app"
log_file="$runtime_dir/orbit-connect-development.log"
pid_file="$runtime_dir/orbit-connect-development.pid"

if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
    export DEVELOPER_DIR
fi

if [ -f "$pid_file" ]; then
    existing_pid="$(tr -d '[:space:]' < "$pid_file")"
    if [ -n "$existing_pid" ] && kill -0 "$existing_pid" 2>/dev/null; then
        if [ "$restart" -eq 0 ]; then
            printf 'Dev-сборка уже запущена, PID %s\n' "$existing_pid"
            printf 'Для перезапуска используйте --restart. Лог: %s\n' "$log_file"
            exit 0
        fi
        process_command="$(ps -p "$existing_pid" -o command= 2>/dev/null || true)"
        case "$process_command" in
            "$app_dir/Contents/MacOS/OrbitStatus"*)
                kill "$existing_pid"
                attempts=0
                while kill -0 "$existing_pid" 2>/dev/null && [ "$attempts" -lt 50 ]; do
                    sleep 0.1
                    attempts=$((attempts + 1))
                done
                ;;
            *)
                printf 'PID %s не принадлежит dev-сборке Orbit Connect\n' "$existing_pid" >&2
                exit 1
                ;;
        esac
    fi
fi

cd "$project_dir"
swift build -c debug --scratch-path "$build_dir"
binary_path="$(swift build -c debug --scratch-path "$build_dir" --show-bin-path)/OrbitStatus"
version="$(tr -d '[:space:]' < "$project_dir/VERSION")-dev"

rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_path" "$app_dir/Contents/MacOS/OrbitStatus"
cp "$project_dir/Resources/OrbitMenuIcon.png" "$app_dir/Contents/Resources/OrbitMenuIcon.png"
cp "$project_dir/Resources/AppIcon.icns" "$app_dir/Contents/Resources/AppIcon.icns"

sed \
    -e "s/@VERSION@/$version/g" \
    -e 's/io\.orbit\.status/io.orbit.status.development/g' \
    -e 's/<string>Orbit Connect<\//<string>Orbit Connect Dev<\//g' \
    "$project_dir/Support/Info.plist.in" > "$app_dir/Contents/Info.plist"

if [ "$demo" -eq 1 ]; then
    /usr/libexec/PlistBuddy \
        -c 'Add :OrbitConnectDemoMode bool true' \
        "$app_dir/Contents/Info.plist"
fi

/usr/bin/codesign --force --sign - "$app_dir"

rm -f "$log_file"
/usr/bin/open -n --stdout "$log_file" --stderr "$log_file" "$app_dir"

sleep 2
pid="$(pgrep -f "$app_dir/Contents/MacOS/OrbitStatus" | tail -n 1)"
if [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; then
    printf 'Dev-сборка завершилась при запуске. Лог: %s\n' "$log_file" >&2
    exit 1
fi
printf '%s\n' "$pid" > "$pid_file"

printf 'Orbit Connect Dev запущен, PID %s\n' "$pid"
if [ "$demo" -eq 1 ]; then
    printf 'Режим: демонстрационные данные\n'
fi
printf 'Приложение: %s\n' "$app_dir"
printf 'Лог: %s\n' "$log_file"
