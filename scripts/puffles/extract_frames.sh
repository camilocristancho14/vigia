#!/bin/bash
# Step 2 of 3: every DefineSprite of each original SWF, one PNG per frame,
# with JPEXS Free Flash Decompiler (ffdec 26.4.0,
# https://github.com/jindrapetrik/jpexs-decompiler/releases/tag/version26.4.0).
#   extract_frames.sh <ffdec-cli.jar> <swf dir> <frames dir>
# Then: build_puffles.py <frames dir> Sources/Pulse/Resources
set -euo pipefail
JAR="$1"; SWF="$2"; OUT="$3"
mkdir -p "$OUT"
ls "$SWF" | grep -v '^adopt' | xargs -P 6 -I{} sh -c \
  'n=$(basename {} .swf); [ -d "'"$OUT"'/$n" ] || java -jar "'"$JAR"'" -format sprite:png -export sprite "'"$OUT"'/$n" "'"$SWF"'/{}" >/dev/null 2>&1; echo {}'
