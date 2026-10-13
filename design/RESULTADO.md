# Resultado: mascotas nuevas, fixes de poses, lectura de uso y panel (rama `feat/mascotas-y-uso`)

Base: `main` v0.4.5 (`772ee6a`). Publicada como v0.5.0 por aprobación posterior (PR a main y release con el DMG).

## Cambio de las 13:15 (prioridad): uso en vivo

Vigía tardaba en reflejar que Claude Code había llegado al 100 % del límite de 5 h. La causa era doble: el modo automático refrescaba cada 30 min cuando el panel estaba oculto (aunque la barra de menú siguiera mostrando cifras), y nada leía el aviso de «límite alcanzado» que el propio agente escribe. Ahora (`a5d58bb`):

- **Detección instantánea, sin ejecutar comandos ni abrir apps.** El monitor de actividad ya lee las transcripciones cada 2 s; ahora también reconoce el límite alcanzado.
  - **Claude Code:** el registro del asistente con `error: "rate_limit"`. Trae un bloque `quotaLimits` con la ventana (`five_hour` o `seven_day`) y el reinicio exacto en epoch, que tiene prioridad; la frase «You've hit your session limit · resets 5pm (America/Bogota)» queda como respaldo, interpretada en la zona horaria que dice el mensaje. Comprobado contra registros reales de este Mac.
  - **Codex:** el bloque `rate_limits` del último `token_count` (ventana por `window_minutes` y reinicio por `resets_at`).
  - **Grok Build:** un turno fallido cuyo texto dice que se agotó el límite. No tenía ejemplos reales para confirmar este formato, así que es el menos seguro de los tres.
  - Se lee la transcripción más reciente sin importar su antigüedad, porque un límite dura horas. No cuenta como «turno fallido»: la pose es la de agotado.
- **Se superpone al instante sobre la lectura.** `UsageStore.usage(for:)` marca como agotada la ventana que nombra el aviso, en rojo y con la hora de reinicio del propio mensaje.
  - Una lectura posterior al aviso manda, porque es la palabra del proveedor.
  - La antigüedad de la lectura no se toca, así que la tarjeta sigue diciendo cuántos datos son viejos.
  - Con el límite activo, la mascota pasa a la pose de agotado.
- **Refresco inmediato:** un límite nuevo pide las cifras exactas al proveedor al momento (como máximo una vez cada 30 s por proveedor).
- **Cadencia:** la barra de menú cuenta como «cifras en pantalla», así que un panel oculto ya no significa 30 min. Con un agente escribiendo en los últimos 2 min se pregunta cada 60 s (antes 120 s).
- **Antigüedad del dato:** la tarjeta del notch dice «Actualizado hace …» cuando una lectura «live» pasa de 15 min. Las tarjetas del menú ya lo hacían.
- **Tests (`LiveLimitTests`, 12):** frases de límite en varios formatos y zonas horarias, `quotaLimits` y `rate_limit_info`, Codex, transcripciones con y sin límite levantado, otros errores que no son límite, la superposición, la lectura posterior que gana, el refresco único y la cadencia. Probado además en seco contra las transcripciones reales de este Mac: sin falsos positivos, porque el último límite ya había vencido.
- **Sin señal local, solo cadencia más rápida:** Grok Bot (cuota en el servidor del proveedor) y Antigravity (no deja nada que leer con la app cerrada).

## Commits

| Commit | Qué |
|---|---|
| `063be0e` | Diseños aprobados y brief (SVG, README, referencias, `v2-sheet.png`, captura del panel). Se dejan fuera los PNG por fotograma y los GIF, que repiten lo que ya dicen los SVG. |
| `1f030ef` | Modelo de poses: un agente en reposo nunca aparenta trabajar, reparto conjunto de poses, hash estable y los estados nuevos con sus animaciones (Clawd, logos y BotMark). |
| `9b5cae7` | Float Bot, Star Buddy y Cloud Ghost: vectoriales, con versión monocroma y elegibles en Ajustes. |
| `793fcae` | CI: `swift test` en cada push y PR, y también antes de empaquetar una release. |
| `87a84bf` | Rediseño de las tarjetas del menú de la barra, y textos relativos en el idioma de la app. |
| `65371b2`, `6965e5e` | Tests de lectura de uso con respuestas reales anonimizadas (Grok Build y Antigravity). |
| `4fa6017` | Este `RESULTADO.md` y la sección «CAMBIO (12:38)» del brief. |
| `a5d58bb` | Uso en vivo: límite alcanzado al instante, refresco inmediato y cadencia más rápida. |

## 1. Mascotas nuevas

- **Antigravity:** Float Bot es la mascota por defecto, y en Ajustes se puede elegir Star Buddy o el bot. Ambas son de Antigravity: no existe un proveedor Gemini aparte, tal como pedía el cambio de las 12:38.
- **Codex:** Cloud Ghost por defecto; también se puede elegir el bot.
- **Ajuste nuevo:** fila «Mascota» (`settings.mascotCharacters`). Solo aparece cuando el proveedor ofrece más de un personaje. Las filas de color, forma y persona del bot solo se muestran si el personaje elegido es el bot.
- **Cómo se dibujan:** con SwiftUI Canvas (`StatusBar/VectorMascots.swift`), a partir de los trazados de los SVG en una caja de 64 unidades. Los colores salen de los README. Cada personaje tiene su propio efecto de trabajo:
  - Star Buddy: chispas que orbitan.
  - Float Bot: chevrones de código y chispas de empuje bajo el arco.
  - Cloud Ghost: ojos `>_` con el cursor parpadeando y bits de datos que suben.
- **Dónde salen:** en las tres superficies, que son el anillo del dock (`UsageRingView`), la barra de menú (`VigiaStatusFace`) y las filas del menú (`VigiaMenuRows`).
- **Monocromo:** igual que Clawd, conservan su color salvo que el fondo de la barra se lo coma. En ese caso pasan a una sola tinta con la cara recortada.
- **Tamaño:** se leen bien a 20 pt. La hoja de contacto (abajo) incluye una fila a 20 pt.

## 2. Bugs de la revisión de v0.4.5

- **a)** Un agente visible que lleva más de 20 min inactivo vuelve a `.sleep`. La rotación en reposo ya no contiene `.type`, `.run` ni `.thinking`, así que una mascota en el portátil siempre significa un turno en marcha.
- **b)** `hashValue` se sustituye por `StableHash.fnv1a` en tres sitios: `Provider.mascotPhase` (que reemplaza a `mascotSlotOffset`), `BotMarkView` y `LogoMascotView`.
- **c)** Las poses se reparten por índice entre las mascotas visibles de cada superficie, en el orden del rail (parámetro `slot` de `UsageStore.mascotPose`).
  - Con 4 o menos, todas distintas.
  - Con más de 4, cada pose se repite lo mínimo posible.
  - Dos cuentas del mismo proveedor también difieren.
- **d)** Entre las 06:00 y las 09:00 rotan cuatro poses: despertando, café, estirándose y despierto. De día rotan despierto, café, jugando y estirándose.
- **e)** Se quitó el fallback `?? activity.lastWrite`: solo cuentan las escrituras del propio proveedor.
- **f)** Corregido el comentario obsoleto de `UsageDockView`.
- **g)** CI y tests: ver «Tests» más abajo.

## 3. Estados nuevos

- **`MascotPose`** pasa de 7 a 14 casos. Los nuevos son `thinking`, `waking`, `waiting`, `celebrate`, `stretch`, `play` y `error`.
- **Prioridad de poses en `UsageStore.mascotPose`**, de mayor a menor:
  1. Arrancando (primeros 3 s de un turno).
  2. Trabajando.
  3. Esperando input.
  4. Error.
  5. Celebrando (20 s).
  6. Café (5 min).
  7. Límite (tired o spent).
  8. Reposo, y dormido pasados 20 min.
- **Esperando input:** se detecta en `AgentActivity` como `Verdict.waiting`.
  - Claude Code, cuando el turno llama a `AskUserQuestion` o `ExitPlanMode`.
  - Kiro, con `pending_interaction`, que antes se trataba como turno terminado.
- **Error o sesión muerta:** `Verdict.failed`. Es un estado distinto de `spent`.
  - Claude Code, con `isApiErrorMessage`.
  - Grok Build, con `turn_failed`.
  - ZCode, con `turn.failed`.
  - Además, una sesión que muere en el turno del modelo, cuando pasan los 90 s de gracia. Se muestra durante 15 min.
- **Clawd:** fotogramas pixel nuevos para todos los estados, en la misma rejilla de 17×12 y con la misma paleta.
- **BotMark de Grok y Grok Bot:**
  - Pensando: puntos y chispas doradas.
  - Esperando: salto y «?».
  - Durmiendo: Zz.
  - Error: ojos en X (`BotMarkConfig.crossedEyes`), se derrite hasta una gota (teardrop) y se pone gris.
  - Celebrando: rebote y morph a estrella. La estrella se genera a partir del anillo del blob, así que no entra en la tabla de formas.
  - Arrancando: `spawning` y luego `waking`.
- **Logos sin mascota:** reciben animaciones equivalentes en `LogoMascotView`.

## 4. Lectura de uso: hallazgos por proveedor

No encontré regresiones en la lectura. Cada cifra se contrastó con una fuente independiente en este Mac, sin lanzar apps ni ejecutar los CLI.

- **Claude Code (5 h y semanal): correcto.**
  - La caché coincide con la status line (`~/.claude/pulse-usage.json`): las horas de reinicio son idénticas y las cifras difieren en una sola respuesta.
  - El 14 % de la captura venía de una lectura de unos 30 min antes. Con el panel oculto, el modo automático refresca cada 30 min (`AdaptiveRefresh.ceiling`).
  - Ojo: durante la revisión el uso de 5 h subió al 80 %.
- **Grok Bot (semanal): correcto.** Daba 15 %, después 17 %, con reinicio el 19 oct. No se pudo verificar sin red contra una segunda fuente.
- **Grok Build (semanal): el 100 % es real.** No es un valor por defecto ni un fallo de parseo.
  - El propio CLI registra en `~/.grok/logs/unified.jsonl` `creditUsagePercent: 100.0`, con periodo hasta el 14 oct a las 9:37.
  - La evolución de la semana fue 25 % → 90 % → 100 %.
  - El parser solo toma como 0 % un porcentaje ausente dentro de un periodo en curso, y solo marca «agotado» con 100 % o más.
  - El token es válido y la renovación OIDC funciona.
  - Cambio de interfaz: en el panel nuevo ya no aparece una barra roja vacía de contexto, sino «Agotado hasta el reinicio» junto a la fecha de vuelta.
- **Antigravity (pools Gemini y Claude/GPT): correcto. El dato antiguo es real.**
  - No hay ningún `language_server` de Antigravity en marcha. La última lectura en vivo es de cuando la app estuvo abierta, y se muestra desde la caché marcada como antigua, que es lo previsto.
  - No existe en disco ninguna fuente de cuota que se pueda leer con la app cerrada. `antigravityAuthStatus` en `state.vscdb` solo guarda una instantánea vieja, sin ventanas de 5 h ni semanales.
- **Fallo de localización, corregido:** «Al 3 hours ago» salía en inglés porque `RelativeDateTimeFormatter` no fijaba el idioma de la app. Ahora la tarjeta nueva dice «Actualizado hace 3 h» (en ámbar si el dato es antiguo), y en `es` «As of %@» pasa a ser «Datos de %@».
- **Tests con fixtures:**
  - `grok-billing-captured-exhausted.json`: respuesta real al 100 %, sin identificadores.
  - `closedAppDropsOnlyTheResetPool`: las cuatro ventanas reales de Antigravity con la app cerrada.

## 5. Panel desplegable

Tarjeta propia para el menú, `StatusBar/MenuUsageCard.swift`. La burbuja del notch no se toca.

- **Cabecera:** nombre y, debajo, un punto de frescura con «Actualizado hace N» (verde si el dato es fresco, ámbar si es antiguo o viene de caché), y el plan.
- **Cada límite:**
  - El nombre arriba.
  - Debajo, la barra, el % y la hora de reinicio, en columnas fijas alineadas entre límites y entre tarjetas.
  - El color indica el riesgo, y sube a rojo si la previsión dice que no durará.
  - Una sola línea de aviso: «Se agota en…», «No durará toda la ventana» o «Agotado hasta el reinicio».
- **Etiquetas en español:** el scope se traduce al mostrarlo («Claude y GPT»). La clave interna no cambia.

## Tests y verificación

- `swift build` correcto. `swift test` completo en verde: **1601 tests en 188 suites**, frente a 1571 en la base.
- **Tests nuevos o reescritos:**
  - `MascotPoseTests`: 1, 2, 3, 4 y 5 mascotas, el mismo proveedor dos veces, inactividad de más de 20 min a cualquier hora y en cualquier slot, ningún fallback entre proveedores, variedad matinal, esperando y error, hash estable, y escenas de BotMark para cada pose nueva.
  - `AgentWaitingTests`: transcripciones con pregunta a la persona, error de API, `pending_interaction`, `turn_failed` y sesión muerta.
  - `MascotGalleryTests`: cada personaje en cada pose dibuja algo, en color y monocromo; Clawd tiene fotograma para todas las poses; elección de personaje y valores por defecto.
  - `MenuUsageCardTests`: riesgo, previsión y frescura.
- **App:** `bash scripts/make-app.sh` genera `build.noindex/Vigia.app`, `.dmg` y `.zip`, con la firma ad hoc verificada. La app construida arrancó y siguió en marcha en modo demo; la cerré por PID.
  - No instalé nada sobre `/Applications/Vigia.app`.
  - El modo demo escribe en `defaults com.vigia.mac`. Hice una copia antes, la restauré y comprobé que el dominio queda idéntico al original, token remoto incluido, también 20 s después.
  - La Vigía instalada siguió abierta todo el tiempo. Si mostró algo raro durante esos 10 s, basta con reiniciarla.
- **Capturas** en `~/vigia-capturas/`:
  - `mascotas-poses.png`: los 3 personajes × 14 poses, en color y monocromo, más Clawd y la fila a 20 pt.
  - `panel-nuevo.png`: el panel en español con casos reales (Claude Code al 81 %, Grok Bot, Grok Build agotado y Antigravity con caché).
  - Se generan con `VIGIA_CAPTURE_DIR=~/vigia-capturas swift test --filter "MascotGalleryTests|MenuUsageCardTests"`.
  - No usé `scripts/capture-screenshots.sh`, porque borra `defaults com.vigia.mac`, cierra la Vigía instalada y cambia la apariencia del sistema.

## Pendientes y notas

- **No verificado en la barra de menú real** con la app instalada. Las animaciones se revisaron en la hoja de contacto y las vistas son las mismas que usa la barra.
- **Esperando input en Claude Code:** solo se detecta en preguntas y planes (`AskUserQuestion` y `ExitPlanMode`). Los diálogos de permisos de herramientas no dejan rastro en la transcripción, y Codex y Grok no tienen todavía un registro equivalente identificado.
- **Sin traducir a ja, ko y zh:** las cadenas nuevas (mascota, «Agotado hasta el reinicio», «Claude y GPT») solo existen en en y es. En el resto de idiomas se muestran en inglés.
- **Refresco:** resuelto, ver «Cambio de las 13:15». Con la barra de menú oculta *y* el panel oculto sigue siendo de 30 min, porque entonces nada muestra las cifras.
- **Grok Bot y Antigravity** no tienen ninguna señal local de límite alcanzado; su frescura depende solo de la cadencia de refresco.
- **Nombres de plan:** «Default Raven» en Claude Code es un `rate_limit_tier` que el código no reconoce y pasa tal cual. No afecta a las cifras.
