# Brief: mascotas nuevas, fixes de poses, lectura de uso y rediseño del panel (rama feat/mascotas-y-uso)

Repo: este checkout (~/Documents/GitHub/vigia), rama `feat/mascotas-y-uso` ya creada desde main (v0.4.5, 772ee6a).
Diseños aprobados: `design/mascotas/conceptos/{gemini/star-buddy-v2,gemini/float-bot-v2,codex/cloud-ghost-v2}` (SVG por estado, README con colores), `design/mascotas/conceptos/concepts.md`, `v2-sheet.png`, logos en `design/mascotas/referencias/`.
Captura del panel actual: `design/panel-actual.png`.
Hay Xcode completo: compila con `swift build` y prueba con `swift test`; app con `bash scripts/make-app.sh`.

## 1. Mascotas nuevas
Star Buddy → Gemini (Gemini CLI), Float Bot → Antigravity, Cloud Ghost → Codex. Sigue la arquitectura existente (patrón ClawdSprites/ClawdMarkView en `Sources/Pulse/StatusBar/`, o BotMark en `Sources/Pulse/Panel/BotMark/`); elige lo más limpio, preferiblemente vectorial/SwiftUI Canvas a partir de los SVG y colores dados. Deben soportar los 7 `MascotPose` (run, type, coffee, awake, sleep, tired, spent) más los estados nuevos del punto 3, en menú, dock y filas del menú (`VigiaStatusFace.mark()`, `VigiaMenuRows.swift`, `UsageDockView.swift`). Legibles a 20 pt en la barra de menú, con versión adaptativa monocroma como Clawd.

## 2. Bugs de la revisión de v0.4.5 (772ee6a)
a) `Usage/UsageStore.swift` ~224-230: un agente visible inactivo >20 min debe volver a `.sleep`; nunca mostrar `.type`/`.run` si no está trabajando (regresión: Clawd parece trabajar estando inactivo).
b) Reemplazar los offsets con `hashValue` (aleatorio por proceso) en `UsageProvider.mascotSlotOffset`, `BotMarkView` (~224) y `LogoMascotView` (~35) por un hash estable (p. ej. FNV-1a del rawValue).
c) Asignar poses conjuntamente entre las mascotas visibles (rotación por índice en el orden del rail) para que cada una muestre pose distinta; la lista diurna solo tiene 4 poses distintas y offsets que difieren en 4 colisionan. Con >N poses disponibles, repetir de forma mínima. Dos cuentas del mismo proveedor también deben diferir.
d) Más variedad entre 06:00-09:00 que coffee/awake.
e) `activity.lastWrite(for:) ?? activity.lastWrite`: el fallback por cuenta/proveedor no debe tomar actividad de otros proveedores.
f) Comentario obsoleto en `Panel/UsageDockView.swift` ~523.
g) Añadir `swift test` al CI (`.github/workflows/`, hoy release.yml solo compila) y mejorar `Tests/PulseTests/MascotPoseTests.swift` para cubrir 1, 2, 3+ y 5 mascotas, mismo proveedor dos veces, y el caso de inactividad >20 min.

## 3. Estados nuevos con animación propia
- 'Esperando input' (turno abierto esperando a una persona; ver `AgentActivity.swift` ~272) y 'error/muerto' (distinto de spent).
- Más animaciones de Clawd en el mismo estilo pixel (grid 17×12, celda 3 px, paleta de ClawdSprites): pensando, esperando, celebrando, error.
- Más animaciones para la bola/fantasma BotMark de Grok/Grok Bot usando estados existentes de `Resources/bot-data.json`: pensando (puntos + chispas doradas), esperando (salto + ?), durmiendo (Zz respiración lenta), error (ojos X, derretirse a teardrop, gris), celebrar (rebote, morph a estrella), arrancando (spawning→waking).
Actualiza todos los switch (ClawdMarkView, LogoMascotView, BotMarkProgramme) y la selección en `UsageStore.mascotPose`.

## 4. Lectura de uso
Se cambió para leer uso sin ejecutar comandos ni abrir apps (p. ej. Antigravity), pero se sospecha que ya no lee bien. Verifica cada proveedor: Claude Code 5h/semanal, Grok Bot semanal, Grok Build semanal (muestra 100% usado: verifica si es real o un fallo de parseo/valor por defecto), Antigravity pools Gemini y Claude/GPT ("Al 3 hours ago" sugiere dato viejo/caché). Encuentra regresiones y corrígelas; nunca requerir lanzar apps ni ejecutar comandos del usuario. Añade tests con fixtures (JSON/respuestas reales anonimizadas).

## 5. Rediseño del panel desplegable de la barra de menú
Ver `design/panel-actual.png`. Jerarquía más clara, tarjetas compactas, porcentaje + hora de reinicio alineados, color por riesgo, estado de frescura/última actualización claro, etiquetas en español consistentes (p. ej. 'Actualizado hace 3 h' en vez de 'Al 3 hours ago'; revisa Localizable.strings en/es), y corrige el aspecto vacío de 'Grok Build 100%' si es erróneo.

## 6. Verificación
`swift build`, `swift test` en verde, `bash scripts/make-app.sh` produce una app que arranca. Si puedes, guarda capturas del panel nuevo y de las mascotas en `~/vigia-capturas/` (puedes usar/adaptar `scripts/capture-screenshots.sh`). No instales sobre /Applications/Vigia.app sin necesidad; si lo haces, conserva `defaults com.vigia.mac` (incluido el token remoto).

## 7. Git
Commits pequeños y lógicos; push de la rama `feat/mascotas-y-uso` a origin. Sin PR, sin release, sin tag, sin cambiar VERSION. Los commits nunca deben mencionar a Alfred ni a Grok Bot como autor/revisor, ni líneas de firma de IA que los nombren. No envíes mensajes ni correos a nadie. `design/` puede ir en un commit propio (deja fuera binarios innecesarios si pesan mucho).

Al terminar, escribe un resumen en `design/RESULTADO.md` (qué se hizo, tests, pendientes, hallazgos de uso por proveedor).

## CAMBIO (12:38): Star Buddy y Float Bot son de Antigravity
No existe en la práctica un proveedor Gemini independiente. Star Buddy y Float Bot pertenecen ambos al proveedor **Antigravity** como dos opciones de mascota seleccionables en Ajustes (por defecto: Float Bot). No asocies Star Buddy a un proveedor Gemini separado. Cloud Ghost sigue siendo de Codex.

## CAMBIO (13 oct, 1:15 PM) — PRIORIDAD: uso en vivo
Juank reporta que Vigía no toma el uso en vivo de ninguna IA: ahora Claude Code está al 100% del límite de 5 h (sesión bloqueada hasta las 5 PM) y Vigía todavía muestra que queda uso. Arreglar como prioridad para TODOS los proveedores (Claude Code, Grok Bot, Grok Build, Antigravity, Codex): refresco frecuente/en vivo (vigilar archivos/estado local y eventos de los hooks, no solo polling lento), detectar al instante "limit reached" (p. ej. por los mensajes/estado de sesión o hooks Notification/Stop), marcar el límite agotado en rojo con hora de reinicio, y mostrar claramente la antigüedad del dato. Sin correr comandos del usuario ni abrir apps. Agregar pruebas.
