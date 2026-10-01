#!/bin/bash
# Launches the real app in demo mode and captures the four scenes in light and dark.
# Requires build.noindex/Vigia.app from scripts/make-app.sh.
set -euo pipefail

cd "$(dirname "$0")/.."

APP="build.noindex/Vigia.app"
test -d "$APP"
OUT="build.noindex/screenshots"
rm -rf "$OUT"
mkdir -p "$OUT"

kill_app() {
    killall Vigia 2>/dev/null || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        if ! pgrep -x Vigia >/dev/null; then
            return 0
        fi
        sleep 0.3
    done
    killall -9 Vigia 2>/dev/null || true
    sleep 0.5
}

set_appearance() {
    local mode="$1"
    if [ "$mode" = "dark" ]; then
        defaults write -g AppleInterfaceStyle Dark || true
        osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to true' || true
    else
        defaults delete -g AppleInterfaceStyle 2>/dev/null || true
        osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to false' || true
    fi
    killall SystemUIServer 2>/dev/null || true
    sleep 2
}

launch_scene() {
    local scene="$1"
    local mode="$2"
    kill_app
    rm -f /tmp/vigia-ready
    printf '%s\n' "$scene" > /tmp/vigia-demo
    printf '%s\n' "$mode" > /tmp/vigia-appearance
    defaults delete com.vigia.mac 2>/dev/null || true
    # `open` may drop the environment. The files above are the fallback the app also reads.
    if ! open -g --env VIGIA_DEMO=1 --env "VIGIA_SCENE=$scene" --env "VIGIA_APPEARANCE=$mode" "$APP"; then
        open -g "$APP"
    fi
    local i
    for i in $(seq 1 40); do
        if [ -f /tmp/vigia-ready ]; then
            sleep 0.6
            screencapture -x "$OUT/${scene}-${mode}.png"
            return 0
        fi
        if ! pgrep -x Vigia >/dev/null; then
            echo "Vigia exited before scene ${scene}/${mode} was ready" >&2
            exit 1
        fi
        sleep 0.5
    done
    echo "Timed out waiting for scene ${scene}/${mode}" >&2
    exit 1
}

kill_app
for mode in light dark; do
    set_appearance "$mode"
    for scene in collapsed expanded menu settings; do
        launch_scene "$scene" "$mode"
    done
done

kill_app
rm -f /tmp/vigia-demo /tmp/vigia-appearance /tmp/vigia-ready
defaults delete -g AppleInterfaceStyle 2>/dev/null || true
osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to false' || true

expected="collapsed-light expanded-light menu-light settings-light collapsed-dark expanded-dark menu-dark settings-dark"
for name in $expected; do
    test -s "$OUT/${name}.png"
done
echo "→ $OUT"
