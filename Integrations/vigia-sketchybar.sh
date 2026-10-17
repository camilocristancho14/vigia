#!/bin/bash
# Modified for Vigía from Pulse (Apache-2.0).
# Set as an item's script. NAME is supplied by sketchybar.
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
directory="$(dirname "$0")"
if ! label="$(/bin/bash "$directory/vigia-status.sh")"; then
    label="Vigía —"
fi
sketchybar --set "${NAME:-vigia}" label="$label"
