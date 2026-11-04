# Motor de animación: estados, mascotas y puffles

Cada IA del panel tiene una **marca**, que se elige en Ajustes › la IA › **Marca**:

- **Logo**: el logo de la empresa de IA, animado según lo que hace el agente.
- **Mascota**: la mascota propia de esa IA en Vigía (Clawd para Claude Code, Float Bot o Star Buddy para Antigravity, Cloud Ghost para Codex, la bolita para las demás).
- **Puffle**: un puffle de Club Penguin, de cualquier color o variante, con vista previa en vivo.

Las tres pasan por el mismo motor (`Sources/Pulse/StatusBar/MarkChoreography.swift`):

1. `UsageStore.mascotPose` dice qué hace el agente (trabaja, espera un comando, celebra, descansa, duerme…).
2. `MarkMood.resolve` combina eso con el uso del límite principal y da un **estado** (tabla de abajo).
3. `MarkChoreographer` reparte, dentro de ese estado, una secuencia de animaciones: **selección aleatoria ponderada**, **nunca la misma dos veces seguidas**, cada una durante unos segundos (en los puffles, siempre vueltas completas del clip, para no cortar un salto a la mitad). La semilla sale de la cuenta, así que dos marcas vecinas no se mueven a la vez.
4. Un cambio de estado corta la animación en curso y abre con la animación principal del estado nuevo (la noticia nunca espera). Entre una animación y otra hay un **fundido cruzado** de 0,3 s (0,35 s en las mascotas).

**Nunca quietas**, salvo en *Agotado*. Con «Reducir movimiento» de macOS todas muestran un fotograma fijo.

## Estados

| Estado | Cuándo | Mascotas de IA (poses que rota) | Puffles (clips que rota) |
| --- | --- | --- | --- |
| **En espera** | Sin turno, uso < 50 % | despierta/parpadea, estirarse, jugar, café | idle (parpadeo), mirar a los lados, rebote, saltar, mimos, comer, cavar, pararse de cabeza, hablar, dormitar breve, chapotear |
| **Preocupado** *(nuevo)* | Sin turno, uso ≥ 50 % | despierta, cansado a ratos, estirarse, jugar | mirar a los lados (nervioso), pensar en comida (*hambriento*), hablar, caminar, dormitar |
| **Cansado** | Uso ≥ 75 % | cansado (sudor), estirarse, café | bostezo largo, dormitar, idle lento, mirar |
| **Exhausto** *(nuevo)* | Uso ≥ 90 % | cansado, dormitar | dormitar, bostezo, lengua verde (*malestar*), dormir |
| **Agotado** | Límite al 100 % | la pose de agotado, **quieta** y sin temporizador | dormido con los ojos cerrados, **quieto** y atenuado |
| **Trabajando** | Turno en curso, el modelo gasta tokens | la pose que pide el estado (teclear / correr / pensar) la mayor parte del tiempo, intercalada con las otras dos poses de trabajo | caminar hacia el frente, caminar de perfil, rodar, cavar, saltar, levantar pesas, rebote, giro |
| **Esperando comando** *(nuevo)* | Turno en curso esperando pruebas, compilación o un comando largo | tubo de ensayo o reloj de arena, y pensar | cavar con paciencia, mirar, idle, caminar |
| **Te necesita** *(nuevo)* | El turno espera una respuesta o un permiso | esperando (signo de pregunta), despierta | hablar, rebote, saltar, mirar |
| **Despertando** | Acaba de empezar un turno (3 s) | despertando | despertar con sobresalto, rebote |
| **Celebrando** | Acaba de terminar un turno (20 s) | celebrar, jugar | salto con giro, pararse de cabeza, saltar, rebote, rodar |
| **Descanso** *(nuevo)* | Hasta 5 min después de un turno | café, estirarse, despierta | comer, mimos, idle, chapotear, mirar |
| **Dormido** | 20 min sin actividad (o de noche si no se puede observar) | dormir con «Z», parpadeo breve | dormir con «Z» (respira), dormitar |
| **Error** *(nuevo)* | El turno falló o la sesión murió | error, cansado | malestar (lengua verde), mirar confundido, hablar, dormitar |
| **Renace** *(nuevo)* | El límite se acaba de reiniciar | celebrar, despertar, jugar | despertar, salto con giro, rebote, saltar |

Trabajar manda sobre todo; el descanso de después de un turno manda sobre el uso; el uso colorea el tiempo libre en los umbrales 50, 75, 90 y 100 %. Un estado de espera nunca elige una pose de trabajo, así que una mascota tecleando siempre significa un turno en curso.

El tempo también cambia con el estado: 0,8× cansado, 0,65× exhausto y dormido, 1,1× trabajando y celebrando.

Un clip que una variante no tiene se omite de su menú (las bibliotecas antiguas solo traen bostezo, hambre y malestar para los puffles clásicos; el rebote es de las criaturas). Si a un estado no le queda nada, el puffle hace su idle.

## Eficiencia

- Los puffles se redibujan solo al ritmo de sus fotogramas: 12,5 por segundo, 6,25 dormidos o exhaustos, y la mitad en modo de bajo consumo.
- Cada variante tiene dos atlas PNG ya a su tamaño (celdas de 44 px = 22 pt @2x para la barra de menú, 80 px para los anillos y la vista previa). Se decodifican una vez, al usarse, y cada fotograma se recorta del atlas sin copiar píxeles.
- Agotado y «Reducir movimiento» son una imagen fija, sin línea de tiempo.
- La coreografía de las mascotas se consulta una vez por segundo; la animación de cada pose conserva su propio ritmo (Clawd, vectores, logos).

## Puffles: de dónde salen

Solo sprites originales del juego, nada redibujado ni generado:

1. `scripts/puffles/fetch_swfs.py` baja, del índice CDX de la Wayback Machine (`scripts/puffles/cdx_puffle.json`), los 284 SWF de `media1.clubpenguin.com/play/v2/content/global/puffle/sprites/`. `scripts/puffles/sources.tsv` lista cada archivo con su snapshot exacto.
2. `scripts/puffles/extract_frames.sh` exporta con JPEXS ffdec 26.4.0 cada `DefineSprite` como un PNG por fotograma.
3. `scripts/puffles/build_puffles.py` clasifica los símbolos (idle de 5 direcciones de 8 fotogramas, caminatas de 12, ciclo de sueño de ~210, rebote de 64, bostezo de 167, hambre de 85, malestar de 45, y la copia grande de cada truco), arma los clips con fotogramas consecutivos, recorta, escala, centra en la celda y paletiza. `scripts/puffles/clip_sources.json` dice de qué SWF salió cada clip de cada variante.

Cada variante usa solo sus propios SWF: el naranja clásico y el naranja gato (1007, con orejas y cola) son opciones separadas, igual que cada criatura de cualquier color. El puffle café no tiene biblioteca de caminar ni de iglú en el archivo, así que su idle son los primeros fotogramas de su truco de hablar. Se dejaron fuera los clips donde la utilería (columpio, poste, hidrante, buceo) dejaba al puffle diminuto, y el cangrejo azul (1023), del que solo sobrevivió su SWF de cavar.

Club Penguin y los puffles son propiedad de Disney.
