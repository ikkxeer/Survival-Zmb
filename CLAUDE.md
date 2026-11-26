# La última verbena — notas para Claude

Juego cooperativo 3D de supervivencia (1–4 jugadores) en **Godot 4.7.2**, GDScript, todo en español. Arte, sonido y música se generan por código (sin texturas ni modelos externos). El usuario habla español: responde en español.

## Estructura
- `game/data.gd` datos (oficios, armas, brotados, defensas, eventos) · `game/map.gd` trazado · `game/nav.gd` cuadrícula y campos de flujo.
- `game/match.gd` simulación autoritativa (host). Todo lo que afecta al resultado va aquí y se replica por instantáneas (`snapshot()`, flags de enemigos en `en[i+6]`).
- `game/main.gd` sesión ENet, entrada, cámara, eventos → efectos/audio/HUD.
- `game/view/`: `world.gd` barrio y casa · `actors.gd` modelos y su actualización · `rig.gd` animación por capas (muelles, ciclo de pasos) · `fx.gd` efectos con pools · `camera_rig.gd`.
- `game/interface.gd` menús, tienda, tablón, barra de construcción, plano · `game/ui/` HUD dibujado (`hud.gd`, `style.gd` paleta/fuentes/iconos, `map3d.gd`, `portrait.gd`).
- `game/audio.gd` síntesis de sonidos (`bank.*`).

## Reglas de código
- GDScript estricto: con valores Variant usa tipo explícito (`var x:float = d[0]`), no `:=`.
- Estilo visual: papel crema, tinta morada (`St.INK`), fuentes Fredoka/Nunito, colores festivos de `style.gd`.
- Tras cambiar la simulación, revisa equilibrio con `soak_test` (varía entre ejecuciones; compara varias).

## Comprobar
```bash
godot --headless --check-only --script res://game/archivo.gd   # sintaxis
godot --headless -s tests/match_test.gd                       # reglas (también coop_test, shop_ui_test, goal_test, camera_test…)
godot --headless -s tests/soak_test.gd                        # partida larga con bots
python tests/run_session.py --jugadores 2 --noches 1          # red
python distribution/empaquetar.py                             # ZIP de Windows en build/
```
Capturas: `xvfb-run` + Vulkan por software (lento); usar escenas de prueba pequeñas y pocas capturas.

## Flujo de trabajo
- Rama de trabajo indicada por la sesión; commits en español, sin PR salvo que se pida.
- Actualiza `README.md` y `TODO.md` cuando cambie algo visible para el jugador.
- Ideas pendientes: sección «Propuestas de mejora» de `TODO.md`.
