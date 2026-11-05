# Avisos de tus bots a Vigía

Vigía es una app de barra de menú para macOS que muestra el uso de servicios de IA y puede reflejar cuándo trabaja un agente remoto. El agente envía pequeños avisos a Vigía; estos actualizan el indicador de actividad. Vigía no ejecuta los comandos recibidos.

## Requisitos

- Vigía debe estar abierto en el Mac que recibirá los avisos.
- En ese Mac, abre **Ajustes → Remote Claude Code activity** y activa la opción. El receptor escucha en el puerto **7717** mientras esté activado.
- El equipo que envía los avisos debe tener conexión privada al Mac receptor, por ejemplo Tailscale con MagicDNS. No expongas el puerto a Internet.
- Necesitas el token del Mac receptor. Cada Mac tiene su propio token; si tienes varios Mac receptores, configura una URL y token para cada uno.

## Token y URL

En Vigía, abre **Ajustes → Remote Claude Code activity**, activa la opción y pulsa **Copy token**. El token se genera y guarda en ese Mac. Pégalo como `<TOKEN>` en la configuración del agente que enviará avisos; mantenlo secreto.

La URL se forma con el nombre MagicDNS del Mac receptor y el endpoint del receptor:

`http://<MAC>.tailXXXX.ts.net:7717/activity`

Reemplaza `<MAC>.tailXXXX.ts.net` por el nombre MagicDNS real del Mac receptor. Usa exactamente el token copiado de ese mismo Mac.

Los avisos usan `POST /activity`, el encabezado `Authorization: Bearer <TOKEN>` y JSON. Los campos principales son `event`, `provider`, `source` y `tool`. Vigía también admite `agent` opcional para identificar un bot, y `kind` opcional para clasificar una herramienta de shell como `test` o `build`.

## Prompt para configurar Claude Code

Copia este texto en Claude Code, en el equipo remoto. Sustituye los dos placeholders por los datos del Mac que tiene Vigía:

> Configura un hook de Claude Code para avisar a Vigía en `http://<MAC>.tailXXXX.ts.net:7717/activity`. Usa el token `<TOKEN>` únicamente en `Authorization: Bearer <TOKEN>`. Envía un POST con `Content-Type: application/json` y un cuerpo JSON con `event`, `provider`, `source` y `tool`. Configura los hooks para `UserPromptSubmit`, `PreToolUse`, `PostToolUse` y `Stop`; el valor de `event` debe ser el nombre del evento recibido. Usa `provider` igual a `claudeCode`, `source` igual a `claude-code` y `tool` igual al nombre de la herramienta cuando exista (cadena vacía si no hay herramienta). Por ejemplo, `{"event":"PreToolUse","provider":"claudeCode","source":"claude-code","tool":"Bash"}`. No envíes texto del prompt, argumentos ni contenido de archivos. No inventes eventos ni opciones de Claude Code: consulta la configuración de hooks disponible en esta instalación y aplica el cambio allí. Conserva el trabajo incluso si el aviso falla.

`Stop` informa a Vigía que terminó la actividad. Si el proceso desaparece sin ese evento, el indicador remoto vence por sí solo después de un tiempo limitado.

## Prompt para que un bot lance Codex o Antigravity con avisos

Úsalo con un bot/agente que pueda iniciar un proceso local. La secuencia de inicio, latidos periódicos y fin coincide con los ejemplos `ai_run.sh` y `vigia_heartbeat.sh`:

> Antes de lanzar el trabajo de Codex o Antigravity, configura avisos al receptor Vigía `http://<MAC>.tailXXXX.ts.net:7717/activity` con token `<TOKEN>`. Para cada aviso haz `POST /activity`, `Authorization: Bearer <TOKEN>`, `Content-Type: application/json` y JSON con `event`, `provider`, `source` y `tool`. Envía `UserPromptSubmit` al iniciar, `PostToolUse` cada 30 segundos mientras el proceso siga vivo y `Stop` al terminar, también si termina con error. Para Codex usa `provider: "codex"`; para Antigravity usa `provider: "antigravity"`. Usa un `source` estable que identifique este proceso, por ejemplo `ai_run:codex:mi-trabajo` o `ai_run:agy:mi-trabajo`, y `tool: "ai_run"`. No mandes prompts, argumentos ni datos del proyecto. Un fallo de aviso no debe detener el trabajo. Inicia el proceso y mantén los latidos mientras siga ejecutándose; al finalizar cancela el emisor de latidos y manda `Stop`.

El ejemplo `/workspace/ai_run.sh` hace avisos al empezar, cada 30 segundos y al terminar. `/workspace/vigia_heartbeat.sh` es otro ejemplo de emisor periódico: recibe PID, proveedor y nombre del bot, manda `PreToolUse` durante la vida del PID y `Stop` al salir. No se deben confundir esos avisos de actividad con notificaciones de fin de trabajo de otros sistemas.

## Prompt para trabajos que ya estaban en marcha

Si el agente ya empezó antes de configurar Vigía, usa este prompt para conectarlo a la actividad en curso:

> El proceso de Codex/Antigravity ya está ejecutándose. Sin reiniciarlo ni interrumpirlo, inicia un emisor de avisos a `http://<MAC>.tailXXXX.ts.net:7717/activity` con `Authorization: Bearer <TOKEN>`. Envía un POST JSON con `event: "PostToolUse"`, `provider: "codex"` (o `"antigravity"`), `source` único para este proceso y `tool: "ai_run"` ahora y cada 30 segundos mientras el PID original exista. Cuando ese PID termine, detén el emisor y envía un último aviso con `event: "Stop"` y los mismos `provider` y `source`. No lances un segundo agente ni mates el proceso original. Si no tienes el PID, identifica con cuidado el proceso ya activo antes de asociar el latido; no inventes uno.

## Prueba con curl

Desde el equipo emisor, sustituye los placeholders y ejecuta:

```sh
curl -sS -m 6 -o /dev/null -w '%{http_code}\n' \
  -X POST 'http://<MAC>.tailXXXX.ts.net:7717/activity' \
  -H 'Authorization: Bearer <TOKEN>' \
  -H 'Content-Type: application/json' \
  -d '{"event":"UserPromptSubmit","provider":"codex","source":"prueba","tool":"curl"}'
```

**204** significa que el aviso llegó y fue aceptado. **000** indica que no se pudo establecer la conexión: comprueba la red/Tailscale, MagicDNS, que Vigía esté abierto y el receptor activado. Un **401** suele indicar token incorrecto; **404**, ruta distinta de `/activity`; **400**, JSON inválido o sin `event`/proveedor reconocido.

## Solución de problemas

- **No llega ningún aviso (curl muestra 000):** abre Vigía en el Mac receptor, activa **Remote Claude Code activity**, comprueba que ambos equipos estén conectados a Tailscale y que el nombre MagicDNS resuelva desde el emisor. Verifica el puerto `7717` y la ruta completa `/activity`.
- **401:** vuelve a copiar el token con **Copy token** en el Mac receptor y actualiza la configuración del emisor. No uses el token de otro Mac.
- **400:** comprueba que el cuerpo sea JSON válido y contenga `event`; usa un `provider` reconocido, como `claudeCode`, `codex`, `antigravity` o `grok`.
- **204, pero el indicador no cambia como esperabas:** usa `UserPromptSubmit`, `PreToolUse` o `PostToolUse` para actividad en curso y `Stop` al terminar. `Stop` no significa actividad; `SessionEnd` también se acepta como fin. Envía latidos mientras el agente sigue ocupado; Vigía descarta estados remotos que quedan sin actualizar.
- **Claude Code:** confirma que el hook instalado se ejecuta en los eventos seleccionados y que puede usar `curl` y alcanzar la URL. El aviso debe fallar sin impedir el trabajo del agente.
- **Secreto expuesto o configuración dudosa:** elimina el token de conversaciones y registros compartidos, vuelve a copiarlo desde Ajustes y actualiza el emisor. No publiques la URL junto con el token.
