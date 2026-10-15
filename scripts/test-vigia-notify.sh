#!/bin/bash
# Checks the hook's Bash copy of the command rules against the table the Swift
# tests use, so «Probando…» means the same thing on every machine. No network:
# only the classifier is loaded, never the part that posts.
#
#   scripts/test-vigia-notify.sh [path/to/vigia-notify.sh]
set -u
here=$(cd "$(dirname "$0")" && pwd)
hook=${1:-$here/vigia-notify.sh}
table=$here/../Tests/PulseTests/Fixtures/command-kinds.tsv

# shellcheck source=vigia-notify.sh
. "$hook"

rows=0 failures=0
while IFS=$'\t' read -r want command; do
  case $want in ''|'#'*) continue ;; esac
  [ "$want" = - ] && want=
  got=$(LC_ALL=C vigia_command_kind "$command")
  rows=$((rows + 1))
  if [ "$got" != "$want" ]; then
    failures=$((failures + 1))
    echo "FAIL: want '${want:--}' got '${got:--}': $command"
  fi
done < "$table"

echo "$rows commands, $failures failures ($hook)"
[ "$failures" -eq 0 ] && [ "$rows" -gt 60 ]
