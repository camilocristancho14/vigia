# Vigía

Vigía es una app de barra de menú para macOS. Muestra, para cada agente de IA en este Mac, si está trabajando ahora y cuánto lleva usado de sus límites. No llama a ningún modelo: lee lo que esos programas ya guardaron en el equipo.

Cubre Claude Code, Codex, Cursor, Gemini CLI y Grok Build (`~/.grok`), y el resto de proveedores que ya sabían leer los proyectos de los que sale esta app (más de setenta).

Hay tres formas de verlo, y se cambian en Ajustes:

- **Barra de menú.** El ítem y el menú siguen el aspecto de claude-status-bar. Claude Code puede mostrar a Clawd, el cangrejo en píxeles; Grok Build puede mostrar una bola con ojos. Si el agente trabaja, la mascota se mueve; si no, se queda quieta.
- **Notch.** El panel del borde de la pantalla, con los anillos de uso, como en Pulse. Se abre al pasar el puntero o al hacer clic.
- **Ambos.**

Cada agente tiene un interruptor en Ajustes para usar el logo oficial o la mascota animada. La apariencia clara y oscura sigue al sistema. La interfaz está en español, y lo que aún no está traducido se lee en inglés.

## Capturas

El notch plegado, el notch abierto, la barra de menú con su menú, y la ventana de ajustes:

![Notch plegado](docs/notch-collapsed-light.png)

![Notch abierto](docs/notch-expanded-light.png)

![Barra de menú](docs/menu-light.png)

![Ajustes](docs/settings-light.png)

## Instalar

Las instalaciones salen de [GitHub Releases](https://github.com/camilocristancho14/vigia/releases), no de los artefactos de Actions.

1. Abre la release, descarga `Vigia.dmg`.
2. Ábrelo y arrastra **Vigia.app** a Aplicaciones.
3. La primera vez macOS puede bloquearla porque la firma es ad hoc. Ábrela una vez y luego ve a Ajustes del Sistema > Privacidad y seguridad > «Abrir de todos modos».
4. Si sigue sin abrir: `xattr -dr com.apple.quarantine "/Applications/Vigía.app"`

El archivo dentro de la imagen se llama `Vigia.app`. Si al copiarlo el nombre quedó con tilde, el comando de arriba es el que corresponde; si quedó sin tilde, usa `"/Applications/Vigia.app"`.

También puedes descargar `Vigia.zip` y descomprimirlo. Requiere macOS 14 o posterior.

## Créditos

Vigía reutiliza el código y el diseño visual de tres proyectos:

- [Pulse](https://github.com/qunqin24/Pulse) de qunqin24 — Apache-2.0. El panel del notch, los anillos y los lectores de uso. Licencia en `LICENSES/Pulse-Apache-2.0.txt`.
- [codenotch](https://github.com/vinzdg/codenotch) de Vinz — MIT. La actividad local de Grok Build, Cursor y Gemini CLI. Licencia en `LICENSES/codenotch-MIT.txt`.
- [claude-status-bar](https://github.com/m1ckc3s/claude-status-bar) de Mick Cesanek — MIT. El ítem de la barra de menú y Clawd. Licencia en `LICENSES/claude-status-bar-MIT.txt`.

Los avisos completos están en `THIRD_PARTY_NOTICES.md`. Las marcas de los proveedores vienen de [Lobe Icons](https://github.com/lobehub/lobe-icons). La bola animada de los anillos parte de [grokbot-animation](https://github.com/iduu/grokbot-animation).
