#!/bin/bash
# Box-only test for scripts/vigia-grok's dedupe and ensure-watcher behaviour.
# Not part of CI (test.yml runs on macOS and has no /home/box/.claude/vigia-notify.sh
# or real exec-daemon agents) -- run this on the box itself:
#
#   scripts/test-vigia-grok.sh
#
# Uses a throwaway $HOME and a loopback HTTP test server; never touches the
# real ~/.config/vigia/env, ~/.cache/vigia or /home/box/bin, and never
# reaches any real Vigía endpoint.
set -u
here=$(cd "$(dirname "$0")" && pwd)
hook="$here/vigia-grok"

[ -r /home/box/.claude/vigia-notify.sh ] || { echo "skip: /home/box/.claude/vigia-notify.sh not present (not on the box)"; exit 0; }
command -v jq >/dev/null || { echo "skip: jq not installed"; exit 0; }

tmp=$(mktemp -d)
trap 'kill "$server_pid" 2>/dev/null; rm -rf "$tmp"' EXIT

mkdir -p "$tmp/home/.config/vigia" "$tmp/home/.cache/vigia" "$tmp/home/bin"
printf 'VIGIA_TOKEN=test-token\n' > "$tmp/home/.config/vigia/env"

counter="$tmp/request-count"
echo 0 > "$counter"
cat > "$tmp/server.py" <<'PY'
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

counter_path = sys.argv[2]

class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        self.rfile.read(length)
        with open(counter_path) as f:
            n = int(f.read().strip() or "0")
        with open(counter_path, "w") as f:
            f.write(str(n + 1))
        self.send_response(204)
        self.end_headers()

    def log_message(self, *args):
        pass

HTTPServer(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()
PY

port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')
python3 "$tmp/server.py" "$port" "$counter" &
server_pid=$!
sleep 0.3

run() {
  HOME="$tmp/home" VIGIA_URL_OVERRIDE="http://127.0.0.1:$port/activity" VIGIA_GROK_SYNC=1 \
    VIGIA_DEDUPE_WINDOW=2 VIGIA_AGENT="${2:-Dobby}" "$hook" "$1"
}

failures=0
check() {
  want=$1; got=$(cat "$counter"); desc=$2
  if [ "$got" != "$want" ]; then
    echo "FAIL: $desc (want $want, got $got)"
    failures=$((failures + 1))
  else
    echo "ok: $desc"
  fi
}

# Two calls for the same agent+event within the dedupe window -> one request.
run UserPromptSubmit Dobby
run UserPromptSubmit Dobby
check 1 "dedupe collapses two rapid identical calls into one request"

# A different agent is never deduped against another agent's stamp.
run UserPromptSubmit Alfred
check 2 "a different agent is not deduped"

# After the window elapses, the same agent+event sends again.
sleep 2.2
run UserPromptSubmit Dobby
check 3 "dedupe window expires"

# ensure-watcher: vigia-grok starts a missing watcher and does not duplicate it.
cat > "$tmp/home/bin/vigia-grok-watch" <<'EOF'
#!/bin/bash
echo $$ > "$HOME/.cache/vigia/watch.pid"
trap 'rm -f "$HOME/.cache/vigia/watch.pid"' EXIT
sleep 30
EOF
chmod +x "$tmp/home/bin/vigia-grok-watch"
rm -f "$tmp/home/.cache/vigia/watch.pid"

run Stop Marcus
sleep 0.3
pid1=$(cat "$tmp/home/.cache/vigia/watch.pid" 2>/dev/null || true)
if [ -n "$pid1" ] && kill -0 "$pid1" 2>/dev/null; then
  echo "ok: ensure-watcher started the watcher"
else
  echo "FAIL: ensure-watcher did not start the watcher"
  failures=$((failures + 1))
fi

run Stop Marcus
sleep 0.2
pid2=$(cat "$tmp/home/.cache/vigia/watch.pid" 2>/dev/null || true)
if [ "$pid1" = "$pid2" ]; then
  echo "ok: ensure-watcher is idempotent (same pid, no duplicate)"
else
  echo "FAIL: ensure-watcher started a second watcher ($pid1 vs $pid2)"
  failures=$((failures + 1))
fi
kill "$pid1" 2>/dev/null

echo "$failures failures"
exit "$([ "$failures" -eq 0 ] && echo 0 || echo 1)"
