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

**Nunca quietas**, salvo las mascotas en *Agotado*: un puffle agotado duerme (se anima a 6,25 fotogramas por segundo). Con «Reducir movimiento» de macOS todas muestran un fotograma fijo. La selección recuerda las últimas animaciones (hasta cuatro, según lo largo del menú), así que un menú largo da la vuelta antes de repetir (0.14).

## Cada animación según su sentido (0.14)

Cada clip de `puffles.json` trae su **tipo** (`kind`). Los estados piden tipos; todo lo que un puffle tenga de ese tipo entra en el menú (el peso de un tipo se reparte entre sus clips, para que un puffle con cuatro juguetes no juegue todo el tiempo). En total son 39 variantes con 573 clips originales: los colores clásicos traen hasta 30 (juguetes, baño, cepillo y las reacciones de la pantalla de cuidado), las criaturas sobre todo sus caminatas y trucos.

| Tipo | Clips originales | Estados donde aparece |
| --- | --- | --- |
| `rest` | idle (parpadeo; el fantasma flota), calma | espera, preocupado, descanso, esperando comando, y como respiro en cansado y exhausto |
| `look`, `think` | mirar a los lados; pensar (arcoíris, morado) | espera, preocupado, trabajando, te necesita, esperando comando, error |
| `walk` | caminar de frente y de perfil | **trabajando**, esperando comando, espera, preocupado |
| `work` | rodar, cavar, pesas, saltar la cuerda | **trabajando**, esperando comando |
| `power` | — (fuego del negro, hielo del blanco: no se leen a 22 pt) | trabajando |
| `play` | chicle, pelota de playa, pelota de estrellas, patineta, aro, carrito, cuerda, nube, burbuja, globo, nube de nieve | espera, descanso |
| `trick` | salto, salto con giro, pararse de cabeza, rebote | espera, trabajando, **celebrando**, despertando, renace, te necesita |
| `cheer`, `dance` | 100 % de cuidado, encantado (dorado, arcoíris) | **celebrando (terminó)**, renace |
| `happy`, `laugh` | mimos, caricias, calma, cosquillas | espera, descanso, celebrando, renace |
| `eat`, `bath`, `groom` | comer, merienda, chapotear, **bañarse** en la tina, cepillarse | descanso, espera |
| `speak` | hablar | **te necesita**, trabajando, espera, preocupado |
| `surprise` | caja sorpresa, que lo toquen | despertando, renace |
| `yawn`, `doze`, `wake` | bostezo, dormitar, despertar con sobresalto | **solo con uso alto (≥ 75 %)**: cansado, exhausto |
| `hungry`, `sad`, `sick` | pensar en comida; decepcionado, molesto; lengua verde | preocupado (hambre), **uso alto**, exhausto, error |
| `sleep` | dormir con «Z», dormir en la almohada (naranja), soñar (amarillo) | cansado, exhausto, dormido con el límite agotado, **agotado** |

**Dormir es el límite** (0.13.1, se conserva): los tipos de sueño (`doze`, `sleep`, `wake`, `yawn`, `PuffleKind.sleepy`) solo salen con el límite al 75 % o más, y a un puffle trabajando solo con el límite agotado. Un agente pensando nunca muestra un puffle dormido. Desde el 75 %, aunque esté en espera, el puffle pasa casi todo el tiempo dormitando, con algún respiro (idle, hambre, tristeza, malestar).

## Estados

| Estado | Cuándo | Mascotas de IA (poses que rota) | Puffles (tipos que rota) |
| --- | --- | --- | --- |
| **En espera** | Sin turno, uso < 50 % | despierta/parpadea, estirarse, jugar, café | rest, look, play, trick, walk, happy, laugh, bath, groom, eat, think, dance, speak |
| **Preocupado** | Sin turno, uso ≥ 50 % | despierta, cansado a ratos, estirarse, jugar | look, think, hungry, rest, speak, walk, sad |
| **Cansado** | Uso ≥ 75 % | cansado (sudor), estirarse, café | doze, yawn, sleep, wake; a ratos hungry, sad, sick, rest |
| **Exhausto** | Uso ≥ 90 % | cansado, dormitar | doze, sleep, yawn, wake; a ratos sick, sad, rest |
| **Agotado** | Límite al 100 % | la pose de agotado, **quieta** y sin temporizador | **dormido** (sleep); si no tiene, dormitar; si tampoco, su idle lento |
| **Trabajando** | Turno en curso, el modelo gasta tokens | la pose que pide el estado la mayor parte del tiempo, intercalada con las otras dos poses de trabajo | walk, work, power, trick, speak, think, look. Agotado: dormido |
| **Esperando comando** | Turno esperando pruebas, compilación o un comando largo | tubo de ensayo o reloj de arena, y pensar | work, look, think, rest, walk |
| **Te necesita** | El turno espera una respuesta o un permiso | esperando (signo de pregunta), despierta | speak, think, trick, look |
| **Despertando** | Acaba de empezar un turno (3 s) | despertando | trick, surprise y lo de trabajando (nunca sale de la cama) |
| **Celebrando** | Acaba de terminar un turno (20 s) | celebrar, jugar | cheer, trick, dance, laugh, happy |
| **Descanso** | Hasta 5 min después de un turno | café, estirarse, despierta | eat, bath, groom, happy, laugh, rest, play |
| **Dormido** | 20 min sin actividad | dormir con «Z», parpadeo breve | con el límite agotado: sleep, doze; si no, lo de espera (o lo de cansado desde el 75 %) |
| **Error** | El turno falló o la sesión murió | error, cansado | sad, sick, look, think |
| **Renace** | El límite se acaba de reiniciar | celebrar, despertar, jugar | cheer, trick, surprise, happy |

Trabajar manda sobre todo; el descanso de después de un turno manda sobre el uso; el uso colorea el tiempo libre en los umbrales 50, 75, 90 y 100 %. Un estado de espera nunca elige una pose ni un clip de trabajo, así que un puffle rodando o una mascota tecleando siempre significa un turno en curso.

El tempo también cambia con el estado: 0,8× cansado, 0,65× exhausto, dormido y agotado, 1,1× trabajando y celebrando.

Un tipo que una variante no tiene se omite de su menú. Si a un estado no le queda nada, usa su respaldo (por ejemplo, preocupado → espera) y, al final, el idle.

## Tamaño en la barra (0.13.1 y 0.13.2, se conservan)

Cada celda del atlas se recorta al puffle (un recorte común por clip, para que no tiemble, y una escala por variante), con el idle llenando el alto; la celda es tan ancha como la variante lo necesita (hasta 1,4 veces el alto). Los clips que se desplazan de lado (rodar, caminar de perfil) siguen al puffle con una cámara suave; los de utilería que vuela (cavar, chicle, tina, cepillo) dejan la cámara fija en el puffle.

Luego `measure_bodies.py` mide el cuerpo del puffle en cada clip y `PuffleLayout` lo dibuja **del mismo tamaño en todos los clips y en todas las variantes** —el naranja incluido—: 14,6 pt de cuerpo en una caja de 28 × 22 pt en la barra, siempre reducido desde el atlas grande. Un clip que en la barra no alcanza ese tamaño dentro de un 10 % (casi todos los saltos y piruetas, y los juguetes cuya utilería empequeñece al puffle) **queda fuera de la rotación de la barra**; en los anillos del panel y en la vista previa de Ajustes sí se ve, algo más pequeño. Con los atlas de 0.14 la barra conserva 429 de los 573 clips.

## Eficiencia

- Los puffles se redibujan solo al ritmo de sus fotogramas: 12,5 por segundo, 6,25 dormidos o exhaustos, y la mitad en modo de bajo consumo.
- Cada variante tiene dos atlas PNG (celdas de 44 px de alto para las filas del menú, 80 px de alto para todo lo animado: barra de menú, anillos y vista previa; el ancho es el de la variante). Se decodifican una vez, al usarse; cada fotograma se recorta del atlas grande y se reduce una vez, con filtrado de alta calidad, exactamente a los píxeles que ocupa, y se guarda.
- Agotado (mascotas) y «Reducir movimiento» son una imagen fija, sin línea de tiempo.
- La coreografía de las mascotas se consulta una vez por segundo; la animación de cada pose conserva su propio ritmo (Clawd, vectores, logos).

## Puffles: de dónde salen

Solo sprites originales del juego, nada redibujado ni generado:

1. `scripts/puffles/fetch_swfs.py` baja, del índice CDX de la Wayback Machine (`scripts/puffles/cdx_puffle.json`), los 284 SWF de `media1.clubpenguin.com/play/v2/content/global/puffle/sprites/`. `scripts/puffles/sources.tsv` lista cada archivo con su snapshot exacto.
2. `scripts/puffles/extract_frames.sh` exporta con JPEXS ffdec 26.4.0 cada `DefineSprite` como un PNG por fotograma.
3. `scripts/puffles/fetch_care.sh` baja las bibliotecas de la pantalla de cuidado de puffles (`media1.clubpenguin.com/play/v2/client/puffle/care/assetLibrary<Color>.swf`, una por cada color clásico que la tuvo: negro, azul, dorado, naranja, rosado, arcoíris, rojo y blanco), listadas con su snapshot en `scripts/puffles/care_sources.tsv`. Traen el baño, el cepillo, las cosquillas, las caricias y, en el dorado y el arcoíris, las reacciones de esa pantalla.
4. `scripts/puffles/build_puffles.py <frames> <recursos> [--report informe.json]` clasifica los símbolos (idle de 5 direcciones de 8 fotogramas, o de 60 en el fantasma, caminatas de 12, ciclo de sueño de ~210, rebote de 64, bostezo de 167, hambre de 85, malestar de 45, y la copia grande de cada truco), suma los de `scripts/puffles/extra_clips.json` (juguetes, baño, reacciones: escogidos a ojo, símbolo por símbolo, con su tipo), arma los clips con fotogramas consecutivos, recorta, escala, los pone en su celda y paletiza. `scripts/puffles/clip_sources.json` dice de qué SWF y de qué símbolo salió cada clip de cada variante. Al terminar llama a `measure_bodies.py`.
5. `scripts/puffles/measure_bodies.py [recursos]` mide, leyendo solo los atlas grandes, qué tan grande queda el puffle en cada clip —por su área, no su altura: el pelo en punta del naranja no cuenta como cuerpo, y la utilería pegada al puffle (pelota, burbuja, cuerda) se separa antes de medir— (`body`, `bodyScale`, `box`, `bodyBox` en `puffles.json`). Se puede volver a correr solo, sin rehacer los atlas.

Cada variante usa solo sus propios SWF: el naranja clásico y el naranja gato (1007, con orejas y cola) son opciones separadas, igual que cada criatura de cualquier color. El puffle café no tiene biblioteca de caminar ni de iglú en el archivo, así que su idle son los primeros fotogramas de su truco de hablar. Se dejaron fuera los clips donde la utilería dejaba al puffle diminuto (columpio, poste, hidrante y buceo; y de las bibliotecas: caballete, cámara, monociclo y malabares, bolos, pista de hielo, trampolín, bola de disco, cañón, fuego y ola de hielo, sombrero hélice; la lista está en `extra_clips.json` › `leftOut` y en el registro del build), el sueño del dorado (desaparece entre destellos) y el cangrejo azul (1023), del que solo sobrevivió su SWF de cavar. La excavación del dorado se conserva (estaba en 0.13.2); en la barra no sale porque no alcanza el tamaño.

Club Penguin y los puffles son propiedad de Disney.
