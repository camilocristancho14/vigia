#!/bin/bash
# Step 1b: the puffle care screen's asset libraries (one per classic colour
# that had one: black, blue, gold, orange, pink, rainbow, red, white), from
# media1.clubpenguin.com/play/v2/client/puffle/care/, found with the Wayback
# Machine's CDX API like the sprites. care_sources.tsv lists each snapshot.
# They hold the bath, the brush, tickling, petting and, for gold and rainbow,
# the care screen's reactions. Raw bytes with the `id_` flag.
#   fetch_care.sh <swf dir>      then extract_frames.sh on that dir as well
set -euo pipefail
OUT="$1"; mkdir -p "$OUT"
while IFS=$'\t' read -r name snapshot original; do
  url="${snapshot/\/http/id_\/http}"
  [ -s "$OUT/$name" ] || curl -sL -m 90 -o "$OUT/$name" "$url"
  head -c 3 "$OUT/$name" | grep -qE 'CWS|FWS|ZWS' || { echo "not a SWF: $name" >&2; rm -f "$OUT/$name"; }
done < "$(dirname "$0")/care_sources.tsv"
