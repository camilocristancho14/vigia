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

# A 1024-wide framebuffer puts the centered notch on top of the Help menu.
# Ask for a wider mode when the window server lists one.
widen_display() {
    local bin list id spec
    bin="$(mktemp)"
    curl -fsSL -o "$bin" "https://github.com/jakehilborn/displayplacer/releases/download/v1.4.0/displayplacer-apple-v140" || return 0
    chmod +x "$bin"
    xattr -c "$bin" 2>/dev/null || true
    list="$("$bin" list 2>/dev/null || true)"
    printf '%s\n' "$list"
    id="$(printf '%s\n' "$list" | awk '/Persistent screen id:/{print $4; exit}')"
    [ -n "$id" ] || { rm -f "$bin"; return 0; }
    spec="$(printf '%s\n' "$list" | awk '
        /res:[0-9]+x[0-9]+/ {
            if (match($0, /res:[0-9]+x[0-9]+.*/)) {
                rest = substr($0, RSTART)
                n = split(rest, a, " ")
                spec = a[1]
                for (i = 2; i <= n; i++) {
                    if (a[i] ~ /^(hz|color_depth|scaling):/) spec = spec " " a[i]
                }
                split(a[1], wh, "x")
                gsub("res:", "", wh[1])
                w = wh[1] + 0
                if (w >= 1440 && chosen == "") chosen = spec
            }
        }
        END { print chosen }
    ')"
    if [ -n "$spec" ]; then
        echo "Setting display $id $spec"
        "$bin" "id:${id} ${spec}" || true
        sleep 2
    fi
    rm -f "$bin"
}

widen_display || true

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
