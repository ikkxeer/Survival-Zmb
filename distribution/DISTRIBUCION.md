# Empaquetar la edición de prueba de Windows

Instala Python 3.9 o posterior, el editor estándar de Godot 4.7.2 y sus plantillas oficiales de exportación. En el editor se instalan desde **Editor → Administrar plantillas de exportación**. Desde la raíz del repositorio ejecuta:

```console
python distribution/empaquetar.py
```

Si no quieres descargar el paquete completo de plantillas (1,2 GB), `python distribution/obtener_plantilla.py` extrae solo la de Windows x64 por rangos HTTP (109 MB) y la instala donde la busca Godot.

El resultado es `build/LaUltimaVerbena-win64.zip`. Si el editor no está en el PATH, pasa su ruta con `--godot`. Puedes elegir otro ZIP con `--salida`. El proceso importa el proyecto, exporta en modo release, añade las instrucciones para jugadores y los avisos, y comprueba la integridad del ZIP antes de reemplazar la salida anterior.

| Origen | Versión utilizada |
| --- | --- |
| Motor y plantillas | Godot estándar 4.7.2, Windows Desktop x86_64 |
| Paquete oficial de plantillas | `Godot_v4.7.2-stable_export_templates.tpz` |
| SHA-256 de ese paquete | `f298490b8d44d934be425a5a65a51bf15f422428b229a06a6e11d9ffea248011` |
| Avisos del motor | `distribution/licencias/Godot-LICENSE.txt` y `Godot-COPYRIGHT.txt` de la misma etiqueta |

[Descarga oficial de Godot 4.7.2](https://github.com/godotengine/godot-builds/releases/tag/4.7.2-stable)

## Pasar el ZIP a jugadores

Entrega el ZIP como un único archivo. El ejecutable y el PCK deben provenir de la misma exportación. Para identificar una descarga concreta calcula su SHA-256 con `Get-FileHash .\LaUltimaVerbena-win64.zip` en PowerShell. Anota el commit y ese hash en las notas de la candidata.

Antes de distribuir una candidata con cambios de contenido, actualiza el inventario de materiales y las instrucciones del ZIP. Registra el origen, los permisos de uso y los créditos de cualquier audio, fuente, textura, modelo o biblioteca incorporados. Si cambia el motor, actualiza también las plantillas y los dos avisos oficiales.

La comprobación pendiente para cerrar la tarea P0 es descomprimir la candidata en dos PC Windows sin el editor, abrir una sesión desde el menú y conectar el segundo equipo al primero. Registra la versión de Windows, el hash del ZIP de ambos equipos y el resultado.

## Candidata de integración

| Dato | Valor |
| --- | --- |
| Commit | rama `claude/kind-babbage-zix1mv` (ver el historial) |
| ZIP | 38 MB: `LaUltimaVerbena.exe` (plantilla release x86_64, 109 MB sin comprimir), `LaUltimaVerbena.pck` (0,3 MB), instrucciones y licencias |
| Plantilla Windows | SHA-256 `d34d36f3be1a6c49…` según `obtener_plantilla.py` |
| Verificación | El PCK exportado arranca y construye el barrio con el motor 4.7.2 de Linux (`godot --main-pack`). En el equipo de integración no hay Wine ni Windows, así que el ejecutable no se ha abierto. |
