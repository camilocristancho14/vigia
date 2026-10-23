#!/bin/bash
# Installs scripts/vigia-grok and scripts/grok-bot-watch to ~/bin, and
# (re)starts the watcher detached. Safe to run repeatedly: idempotent, never
# ends up with two watcher processes (the watcher itself takes an flock on
# $VIGIA_STATE_DIR/watch.lock, so a redundant start here just exits at once).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
bin_dir="$HOME/bin"
mkdir -p "$bin_dir"

install -m 0755 "$here/grok-bot-watch" "$bin_dir/vigia-grok-watch"
install -m 0755 "$here/vigia-grok" "$bin_dir/vigia-grok"

state_dir="${VIGIA_STATE_DIR:-$HOME/.cache/vigia}"
mkdir -p "$state_dir"
pidfile="$state_dir/watch.pid"

running=0
pid=""
if [ -f "$pidfile" ]; then
  pid=$(cat "$pidfile" 2>/dev/null || true)
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    running=1
  fi
fi

if [ "$running" -eq 1 ]; then
  echo "vigia-grok-watch ya estaba corriendo (pid $pid)."
else
  nohup "$bin_dir/vigia-grok-watch" >>/tmp/vigia-grok-watch.log 2>&1 &
  disown || true
  echo "vigia-grok-watch arrancado."
fi

echo "Instalado: $bin_dir/vigia-grok y $bin_dir/vigia-grok-watch"
echo "Log: /tmp/vigia-grok-watch.log"
