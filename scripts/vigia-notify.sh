#!/bin/bash
# Hook de Claude Code (o Grok Build) que avisa a Vigía de la actividad de la IA
# en otra máquina. Plantilla: cópiala a esa máquina, por ejemplo a
# ~/.claude/vigia-notify.sh, y regístrala en ~/.claude/settings.json para
# UserPromptSubmit, PreToolUse, PostToolUse y Stop (ver README, «Actividad
# remota»). Nunca bloquea a la IA: siempre sale con 0.
#
# Configuración en ~/.config/vigia/env:
#   VIGIA_URL=http://<tu-mac>:7717/activity   # por Tailscale o un túnel SSH
#   VIGIA_TOKEN=<el token de Ajustes > Barra de menú > Copiar token>
#   VIGIA_SOURCE=<nombre de esta máquina>     # opcional; por defecto el hostname
#
# Envía {provider, source, event, tool} y, desde 0.6.0, "kind": "test" o
# "build" cuando un PreToolUse de Bash es una prueba o una compilación, para
# que Vigía muestre «Probando…» o «Compilando…». El comando se clasifica aquí
# y NUNCA sale de esta máquina: solo viaja la categoría. Un Vigía anterior
# ignora el campo. Requiere bash (vale el 3.2 de macOS), jq y curl.
#
# Las reglas de vigia_command_kind son las de CommandWait.kind(of:) en
# Sources/Pulse/Usage/CommandWait.swift; scripts/test-vigia-notify.sh las
# comprueba contra la misma tabla (Tests/PulseTests/Fixtures/command-kinds.tsv).

# --- Clasificación de comandos -------------------------------------------------

_VIGIA_NEVER=" echo printf cat less more head tail grep egrep rg ag find fd ls tree git gh sed awk cd pwd which type man vim vi nano code open cp mv rm mkdir touch chmod pip pip3 brew apt apt-get curl wget jq wc sort diff kill pkill ps tee xargs export source gem "
_VIGIA_RUNNERS=" pytest py.test tox nox unittest jest vitest mocha rspec phpunit ctest karma ava "
_VIGIA_PM_BUILTIN=" install i add ci remove rm uninstall update up upgrade init create publish link outdated audit why info view list ls login config cache version pack "

# Whether any of the arguments of the word being read is one of "$@".
_vigia_any() {
  local word name
  for word in ${_vigia_args[@]+"${_vigia_args[@]}"}; do
    for name in "$@"; do [ "$word" = "$name" ] && return 0; done
  done
  return 1
}

# A package.json script, by its name.
_vigia_script() {
  case $1 in
    *test*|*e2e*|*spec*|*playwright*|*cypress*|*jest*|*vitest*) _vigia_v=test ;;
    build*|compile|bundle|dist) _vigia_v=build ;;
    *) _vigia_v=none ;;
  esac
}

# npm test, npm run test:e2e, yarn build, pnpm exec jest.
_vigia_package_manager() {
  local program=$1 sub=$2 script=$3
  [ -n "$sub" ] || { _vigia_v=none; return; }
  case $sub in
    test|t|tst) _vigia_v=test; return ;;
    exec|dlx|x) _vigia_v=skip; return ;;
    run|run-script) _vigia_script "$script"; return ;;
  esac
  [ "$program" = npm ] && { _vigia_v=none; return; }
  case $_VIGIA_PM_BUILTIN in *" $sub "*) _vigia_v=none; return ;; esac
  _vigia_script "$sub"
}

# The verdict of the word "$1", given the words after it: test, build, none
# (decides: neither) or skip (a word nobody knows: read on).
_vigia_verdict() {
  local program=${1##*/} first second word
  shift
  _vigia_args=()
  for word in "$@"; do case $word in -*) ;; *) _vigia_args+=("$word") ;; esac; done
  first=${_vigia_args[0]-}
  second=${_vigia_args[1]-}

  case $_VIGIA_NEVER in *" $program "*) _vigia_v=none; return ;; esac
  case $_VIGIA_RUNNERS in *" $program "*) _vigia_v=test; return ;; esac
  case $program in
    python*|py)
      # python -c "import pytest" no corre pruebas; python -m pytest sí.
      if [ "${1-}" = "-c" ]; then _vigia_v=none; else _vigia_v=skip; fi
      return ;;
  esac

  _vigia_v=none
  case $program in
    manage.py|playwright) [ "$first" = test ] && _vigia_v=test ;;
    cypress) [ "$first" = run ] && _vigia_v=test ;;
    swift|go|dotnet)
      case $first in test) _vigia_v=test ;; build) _vigia_v=build ;; esac ;;
    cargo)
      case $first in test|nextest) _vigia_v=test ;; build) _vigia_v=build ;; esac ;;
    mix)
      case $first in test) _vigia_v=test ;; compile) _vigia_v=build ;; esac ;;
    xcodebuild)
      if _vigia_any test test-without-building; then _vigia_v=test; else _vigia_v=build; fi ;;
    make|gmake)
      if _vigia_any test tests check; then _vigia_v=test
      elif [ -z "$first" ] || _vigia_any build all release; then _vigia_v=build; fi ;;
    mvn|mvnw)
      if _vigia_any test verify integration-test; then _vigia_v=test
      elif _vigia_any package install compile; then _vigia_v=build; fi ;;
    gradle|gradlew)
      for word in ${_vigia_args[@]+"${_vigia_args[@]}"}; do
        case $word in check|test*|*:test) _vigia_v=test; return ;; esac
      done
      for word in ${_vigia_args[@]+"${_vigia_args[@]}"}; do
        case $word in assemble*|build|*:build) _vigia_v=build; return ;; esac
      done ;;
    rake|rails)
      case $first in test*|spec*) _vigia_v=test ;; esac ;;
    docker|podman)
      # docker compose exec web pytest se lee hasta pytest; un build es un build.
      _vigia_v=skip
      if [ "$first" = build ]; then _vigia_v=build
      else case $first in compose|buildx|image) [ "$second" = build ] && _vigia_v=build ;; esac; fi ;;
    uv|poetry|pipenv|pdm|hatch|rye|pixi|bundle|conda|mamba)
      # uv run pytest se lee hasta pytest; poetry add pytest instala.
      case $first in run|exec) _vigia_v=skip ;; esac ;;
    tsc|webpack) _vigia_v=build ;;
    vite|next|nuxt|astro) [ "$first" = build ] && _vigia_v=build ;;
    npm|pnpm|yarn|bun) _vigia_package_manager "$program" "$first" "$second" ;;
    *.sh)
      case $program in *test*) _vigia_v=test ;; *build*) _vigia_v=build ;; *) _vigia_v=skip ;; esac ;;
    *) _vigia_v=skip ;;
  esac
}

# One segment of a command, as words: assignments first, then the first word
# that decides.
_vigia_segment() {
  local name
  while [ $# -gt 0 ]; do
    name=${1%%=*}
    [ "$name" != "$1" ] || break
    case $name in ''|*[!a-z0-9_]*) break ;; esac
    shift
  done
  while [ $# -gt 0 ]; do
    _vigia_verdict "$@"
    case $_vigia_v in test|build) return ;; none) _vigia_v=; return ;; esac
    shift
  done
  _vigia_v=
}

# Prints "test", "build" or nothing for the shell command "$1". A compound
# command counts as its slowest part: swift build && swift test is a test run.
vigia_command_kind() {
  local text segment found= IFS
  text=$(printf '%s' "$1" | LC_ALL=C tr '[:upper:]' '[:lower:]')
  # Every separator becomes a newline. Not \001: bash uses it internally, and
  # the 3.2 that ships with macOS mangles it.
  text=${text//&&/$'\n'}
  text=${text//||/$'\n'}
  text=${text//;/$'\n'}
  text=${text//|/$'\n'}
  text=${text//&/$'\n'}
  set -f
  IFS=$'\n'
  for segment in $text; do
    segment=$(printf '%s' "$segment" | tr "\"'\`()" '     ')
    IFS=$' \t'
    _vigia_segment $segment
    IFS=$'\n'
    case $_vigia_v in
      test) set +f; echo test; return 0 ;;
      build) found=build ;;
    esac
  done
  set +f
  [ -n "$found" ] && echo "$found"
  return 0
}

# Sourced (by scripts/test-vigia-notify.sh): only the functions.
[ "${BASH_SOURCE[0]}" != "$0" ] && return 0

# --- El hook -------------------------------------------------------------------

{
  input=$(cat)
  CONF="$HOME/.config/vigia/env"
  [ -r "$CONF" ] || exit 0
  . "$CONF"
  [ -n "$VIGIA_URL" ] && [ -n "$VIGIA_TOKEN" ] || exit 0
  command -v jq >/dev/null || exit 0
  if [ -n "$GROK_HOOK_EVENT" ]; then provider=grok; else provider=claudeCode; fi
  source_name=${VIGIA_SOURCE:-$(hostname -s 2>/dev/null || echo remote)}
  event=$(printf '%s' "$input" | jq -r '.hook_event_name // empty' 2>/dev/null)
  tool=$(printf '%s' "$input" | jq -r '.tool_name // .toolName // empty' 2>/dev/null)
  case "$event" in
    UserPromptSubmit|PreToolUse|PostToolUse|Stop) ;;
    StopFailure|StopCancelled|SessionEnd) event=Stop ;;
    *) exit 0 ;;
  esac
  kind=
  if [ "$event" = PreToolUse ]; then
    case $(printf '%s' "$tool" | tr '[:upper:]' '[:lower:]') in
      bash|shell|run_command|run_shell_command|terminal|exec_command)
        cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // .toolInput.command // .tool_input.cmd // empty' 2>/dev/null)
        kind=$(LC_ALL=C vigia_command_kind "$cmd")
        unset cmd ;;
    esac
  fi
  body=$(jq -cn --arg p "$provider" --arg s "$source_name" --arg e "$event" --arg t "$tool" --arg k "$kind" \
    '{provider:$p,source:$s,event:$e,tool:$t} + (if $k == "" then {} else {kind:$k} end)')
  ( code=$(curl -s -m 6 -o /dev/null -w '%{http_code}' -X POST "$VIGIA_URL" \
      -H "Authorization: Bearer $VIGIA_TOKEN" -H 'Content-Type: application/json' -d "$body" 2>/dev/null)
    echo "$(date '+%F %T') $provider $event ${tool:--} ${kind:--} http=$code" >> /tmp/vigia-notify.log ) >/dev/null 2>&1 &
} >/dev/null 2>&1
exit 0
