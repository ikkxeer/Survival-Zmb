# Prioridades de La última verbena

Objetivo de la próxima versión: que un grupo pueda descargar el juego, entrar en la misma casa y superar tres noches entendiendo por qué sobrevive o por qué pierde.

## Entregado en la rama de coordinación cooperativa

- [x] **Orientarse desde la calle.** M abre el plano con el norte fijo. Muestra jugadores, caídos, enemigos, casa, puestos y defensas a partir del estado real de la partida.
- [x] **Pedir apoyo sin voz.** G marca tu posición. Un clic en el plano marca un destino. La señal aparece también en el mundo, indica la distancia y caduca a los ocho segundos. Los caídos pueden señalar dónde reanimarlos.
- [x] **Avisar de una brecha.** El HUD indica qué acceso recibe daño o se ha perdido. El plano resalta el mismo punto. Reparar o reconstruir despeja el aviso.
- [x] **Verificar la réplica.** Un anfitrión y tres clientes emiten señales y comprueban su posición, la construcción de una barricada y el gasto compartido. Las pruebas locales cubren caducidad, límites del mapa y cierre de sesión.

## P0 · Conseguir una versión que se pueda probar con amigos

- [x] **Combinar las dos ramas en una candidata.** La rama de gráficos y jugabilidad queda como base y recupera lo entregado en coordinación:
  - La rueda lleva la cámara de la vista táctica a la tercera persona; arrastrar con el botón derecho la gira y WASD sigue a la cámara. Un clic derecho corto da un sartenazo.
  - M o Tab abren el plano con el norte fijo, y un clic en él señala un destino sin disparar. G pide apoyo, también tras caer.
  - Las señales viven en el anfitrión con las mismas reglas: ocho segundos, una cada 1,5 s, dentro del barrio. Se ven con oficio y distancia.
  - Los avisos de brecha cubren norte, este, sur y oeste, golpes a la casa y estandartes atacados.
  - Comprobado con `camera_test`, `coop_test`, `match_test` y `network_test` (anfitrión y tres clientes con señales y barricadas), y con capturas del plano abierto y de la tercera persona. Falta repetirlo a mano con ratón y teclado.
- [x] **Empaquetar Windows x64.** Perfil de exportación release, instrucciones de juego y avisos del motor incluidos en el ZIP. Dos instancias del ejecutable descomprimido bajo Wine se conectaron por bucle local y mostraron Equipo 2/4. [Procedimiento de exportación](distribution/DISTRIBUCION.md)
- [ ] **Entregar un ZIP de Windows.** Preparar una exportación reproducible y abrirla en un PC sin Godot instalado. Dos equipos deben poder crear y unirse a una partida con esa misma descarga.
  - Exportación reproducible de la rama integrada: `python distribution/obtener_plantilla.py`, que descarga solo la plantilla de Windows (109 MB en lugar de 1,2 GB), y después `python distribution/empaquetar.py`. Genera un ZIP de 38 MB en 15 s.
  - Su PCK arranca y construye el barrio con el motor de Linux.
  - Falta abrirlo en dos PC Windows sin Godot y conectarlos.
- [x] **Sostener una sesión de tres noches.** `python tests/run_session.py --jugadores 1|2|4` lanza un anfitrión y clientes reales por ENet con bots y el tiempo a ×4. Con cuatro, un cliente tiene 150 ms de latencia simulada (`--latencia=ms`) y otro sale a mitad de la segunda noche. Al tercer amanecer todos los procesos comparan vida de la casa, materiales, defensas, jugadores y fichas de cada uno.
  - Resultado: coherentes con uno, dos y cuatro jugadores, y el equipo sigue jugando tras la salida.
  - La prueba destapó un fallo real que ya está corregido: una torreta podía consultar un brotado que había caído antes en el mismo paso.
  - Falta una partida a mano por Internet con latencia real.
- [ ] **Medir una oleada llena.** Registrar CPU, GPU, memoria y tiempos de fotograma con 48 enemigos y las dos opciones gráficas en un PC identificado. Repetir el mismo recorrido tras integrar los cambios visuales.
  - Herramienta lista: `godot --path . -s tests/benchmark.gd -- --calidades=0,2 --enemigos=50` juega la misma noche con cuatro jugadores en cada calidad. Guarda en `user://benchmark.md` el equipo, los FPS, la media, p95, p99 y máximo, el render en CPU y GPU, la física, las llamadas de dibujo, las primitivas, la RAM y la VRAM.
  - Primera medida en la máquina de integración (Xeon de 4 núcleos con render por software, no representativa de GPU): reveló demasiadas primitivas en la vegetación. El césped, las flores y el follaje se aligeraron de 0,74 M a 0,53 M primitivas en Baja y de 1,69 M a 1,31 M en Alta.
  - Pendiente: ejecutarla en un PC con GPU identificada y anotar aquí sus resultados.

## P1 · Mejorar las decisiones que se toman durante una noche

- [ ] **Validar la lectura de las brechas con jugadores.** En una prueba sin instrucciones, comprobar si otro jugador llega al acceso anunciado y lo repara. Medir el tiempo desde el aviso hasta la reparación.
  - Medición lista: el anfitrión guarda un registro por partida en `user://registros/partida-*.jsonl`. Cada brecha anota el acceso, la defensa perdida, cuánto tardó en cerrarse y quién la cerró. Falta la prueba con jugadores.
- [ ] **Afinar la primera noche.** Observar a un jugador nuevo desde el menú hasta el amanecer. Anotar cuándo encuentra la primera caja, qué construye y si entiende el coste de conquistar. Corregir el primer bloqueo observado y repetir.
  - Preparado: el primer día muestra una lista de pasos que se van marcando: rebuscar, construir en el lado del ataque, una opción arriesgada y tocar la campana. Falta observar a jugadores nuevos.
- [ ] **Diferenciar las armas al oído y al disparar.** Coordinar con la rama de jugabilidad el sonido, la animación y la lectura del impacto de cada arma. Probar una defensa cercana y otra a distancia con los tres modelos.
  - Implementado en la rama integrada: siete armas con sonido sintetizado propio, color y grosor de trazadora, fogonazo, sacudida, retroceso del personaje y empuje. El soplete y el lanzatracas tienen efectos propios. Falta la prueba de defensa cercana y lejana con jugadores.
- [ ] **Afinar los ataques por varias calles.** Registrar por dónde llega cada grupo y qué defensa elige atacar. Probar al menos dos preparaciones distintas que permitan superar la misma oleada.
  - Registro listo: cada grupo anota su calle, su tamaño y su asalto. Cada amanecer anota el daño recibido por acceso y la defensa perdida en cada brecha. Falta comparar dos preparaciones.
- [x] **Dar opciones de comodidad.** Ajustes incluye sensibilidad de cámara, volumen general, de efectos y de música, tamaño de interfaz, sacudidas, destellos y números de daño, y todas las acciones reasignables (una tecla ocupada se intercambia). Se guardan de forma segura en `user://ajustes.cfg` con versión. `tests/settings_test.gd` verifica que se conservan al reiniciar y que la ayuda muestra las teclas elegidas.

## P2 · Ampliar el barrio después de validar el núcleo

- [x] **Primer rescate jugable.** Un vecino atrapado aparece de día en una casa con dos guardianes. Mantener E lo libera y camina solo hasta la casa por la ruta de los brotados; los brotados pueden atacarlo por el camino.
  - Si llega, se une a la comunidad con una ventaja compartida: el carpintero da materiales, la enfermera cura en la plaza y el vigía dispara desde el tejado.
  - Si cae, se anuncia y la oportunidad se pierde.
- [x] **Primer jefe de barrio.** El Gigantón llega cada cinco noches. Antes de su pisotón aparece un anillo rojo durante casi un segundo: dentro reciben daño jugadores y defensas. Además convoca brotados cada 11 s.
  - Primera estrategia: esquivar el anillo y atacar entre pisotones.
  - Segunda estrategia: frenarlo lejos de la casa con bobinas que lo aturden, alambradas y minas, porque el pisotón destroza barricadas.
  - Falta comprobar con jugadores que ambas funcionan.
- [x] **Progresión entre partidas.** Cada oficio acumula experiencia entre partidas (`user://perfil.cfg`, versionado) y sube de rango:
  - Rango 2: ingeniera con materiales extra, médico con tres botiquines, soldado con trabuco y exploradora con fichas.
  - Rango 3: +15 de vida.
  - Se guarda en cada amanecer, al acabar y al salir. La escritura usa un archivo temporal y conserva una copia anterior, así que si el archivo queda a medias se recupera la copia; un perfil de una versión futura no se aplica.
  - El menú muestra el rango, el progreso y las ventajas de cada oficio. Verificado en `tests/profile_test.gd`.

## P1 · Que siempre haya una decisión disponible

Primero probar este ritmo durante tres noches con los cuatro puestos actuales. Por ejemplo, al atardecer quedan materiales para reforzar la entrada sur. El dispensario pide ayuda y la exploradora ha encontrado un atajo. En solitario puedes cerrar el acceso y volver mañana. En cooperativo, alguien puede cubrirte mientras vas a por el botiquín. Ambas decisiones deberían dar lugar a una noche interesante.

- [ ] **Dar una pista útil al salir de casa.** Desde el porche deben distinguirse un recurso cercano y una oportunidad más arriesgada. En una prueba con cinco personas nuevas, observar si al menos cuatro eligen su primer destino sin abrir la ayuda.
  - Implementado: el primer día marca en pantalla «✦ Botín cercano» y la propiedad libre más próxima como «arriesgado», además del vecino atrapado. Falta la prueba con cinco personas.
- [x] **Ofrecer un encargo corto y otro ambicioso.** El tablón junto a la tienda (E) ofrece cada día uno corto cerca de la plaza y otro ambicioso lejos.
  - Antes de aceptar muestra el lugar, la distancia, el riesgo y la recompensa común.
  - Tres tipos: búsqueda, transporte hasta el porche (quien carga va más despacio y suelta la caja si cae) y defensa de una zona durante 25 s mientras llegan brotados.
  - Se pueden abandonar y caducan al anochecer. El HUD, el plano y las marcas en pantalla guían al destino.
  - Verificado en `tests/jobs_test.gd`. Falta probarlo en pareja.
- [x] **Permitir adelantar la noche.** La campana de la plaza (mantener E) o N marcan a cada vecino como listo, y volver a tocarla lo cancela. Cuando todos los presentes están listos, la noche llega en 4 s; en solitario basta con una persona. Quien se desconecta deja de contar. Verificado en `match_test`.
- [x] **Dar trabajo útil a quien se queda en casa.** El plano indica el acceso más débil (defensas y resistencia por lado). En la tienda se prepara un lote por 4 materiales comunes: munición, botiquín, traca y 40 de salud, que se deja en el porche para un compañero. La recogida se anuncia con el nombre de quien lo preparó y la pantalla final cuenta los lotes de cada uno. Falta comprobar con jugadores que lo explican.
- [x] **Introducir pausas elegidas durante el asalto.** Cada noche se divide en dos asaltos, o tres a partir de la tercera. Tras rechazar uno hay 15 s de respiro con cuenta atrás, y un globo deja una caja en el exterior. Si no da tiempo a todo, el siguiente asalto llega con la tarea a medias. Verificado en `match_test`. Falta medir con jugadores cuántas acciones caben.
- [x] **Cambiar la siguiente decisión al amanecer.** El informe del amanecer muestra lo ganado, lo que aportó cada propiedad y cada vecino de la comunidad, el acceso más castigado (y si sigue abierto) y la caja común. Falta comprobar si el equipo lo usa para decidir.
- [ ] **Medir la espera real.** Revisar grabaciones de sesiones en solitario y en grupo. Anotar por jugador los tramos de más de 20 segundos en los que quería actuar y no encontraba cómo. Distinguirlos del descanso voluntario y repetir la prueba tras corregir el tramo más frecuente.
  - Registro listo: el anfitrión anota cada tramo de más de 20 s sin moverse ni actuar, con jugador, duración y fase. Falta cruzarlo con grabaciones para separar el descanso voluntario.

## P2 · Convertir el barrio en un lugar al que merezca la pena volver

- [x] **Dar una meta final a la partida.** «Encender la verbena»:
  - Al conquistar el Taller, el Almacén, el Economato y la Gasolinera aparece en cada uno una pieza: cuadro eléctrico, guirnalda maestra, altavoces y bidón de gasoil.
  - Hay que cargarla hasta el escenario de la plaza. Quien la lleva va más despacio y la suelta si cae.
  - Con las cuatro instaladas, el escenario permite encender la verbena: empieza una noche final de 120 s por todas las calles. Si se aguanta hay victoria con fuegos artificiales; si cae la casa, derrota.
  - Al terminar, el anfitrión ofrece una revancha con el mismo grupo.
  - Desde el primer día el HUD y el plano indican las piezas que faltan y dónde están. Verificado en `tests/goal_test.gd`. Falta ensayarlo con un grupo.
- [ ] **Abrir rutas con consecuencias.** Crear un atajo del taller a la plaza que también pueda aprovechar la horda. Comparar dos partidas con la misma oleada y registrar cuándo interesa abrirlo y cuándo conviene mantenerlo cerrado.
- [ ] **Dar una función jugable a cada interior.** Empezar con el dispensario: una pista visible desde fuera, dos salidas y un botiquín que hay que transportar. Probar que la cámara permite ver al portador y a sus perseguidores en las puertas.
- [ ] **Encadenar decisiones entre días.** Un vecino rescatado puede atender el dispensario o reforzar el taller. Hacer visible el efecto de su destino la noche siguiente y verificar que ambos destinos aportan ventajas distintas.
- [x] **Variar los encargos con reglas sencillas.** El generador alterna búsqueda, transporte y defensa con destinos alcanzables según la navegación, recompensas útiles y sin repetir tipo y lugar del día anterior. `jobs_test` genera diez partidas de seis días (60 días) y no encuentra destinos inaccesibles, recompensas inútiles ni encargos idénticos consecutivos.
- [x] **Diseñar una recuperación tras una mala noche.** Si el amanecer llega con menos de 8 materiales, un globo deja reservas (14–18 materiales) junto a la plaza: es una salida corta. Si el equipo va bien, no hay ayuda extra, así que ahorrar sigue teniendo sentido. Verificado en `match_test`.
- [ ] **Crear combinaciones entre roles.** Probar al explorador localizando un relevo de energía y al ingeniero instalándolo mientras otro cubre el regreso. El mismo objetivo debe poder completarse solo, en varias visitas.
- [ ] **Diversificar las compras.** Comparar una inversión personal, una defensa automática y la conquista de un puesto con el mismo presupuesto inicial. Si una opción domina las tres primeras noches en todas las pruebas, revisar coste, utilidad o momento de acceso.
- [ ] **Dar motivos para probar otra estrategia.** Ofrecer al final una variante voluntaria, como un barrio con apagones y más rutas de suministro. Mostrar sus reglas antes de empezar y comprobar que cambia al menos una decisión de ruta o de construcción.

## P2 · Conseguir una identidad visual y sonora reconocible

Coordinar estos puntos con la rama de gráficos y jugabilidad. Revisar primero lo que ya resuelve su versión integrada.

- [ ] **Crear una escena de referencia artística.** Pulir el trayecto del porche al taller con un personaje, un brotado, escaparates y guirnaldas. Aprobar el tratamiento de materiales, iluminación y proporciones en capturas de día y de noche antes de extenderlo al barrio.
- [ ] **Reconocer el peligro por la silueta.** Diferenciar corredor, grandullón y enemigo común por postura, movimiento y preparación del ataque. Probar su identificación al anochecer y en una captura en escala de grises.
- [x] **Animar las interacciones importantes.**
  - Las piezas y las cajas se llevan sobre la cabeza.
  - Reparar, reanimar y rebuscar tienen una animación de manos con barra de progreso y sonido.
  - Recibir un golpe interrumpe la acción y reinicia su progreso (verificado en `match_test`).
  - Falta revisarlo desde la cámara de otro jugador.
- [x] **Contar la historia del barrio mientras se juega.** Cada propiedad conquistada se llena de vecinos que celebran bajo banderines nuevos, con el estandarte de colores y su luz por la noche. Cada pieza instalada aparece en el escenario. Falta verificar que se distingue al volver desde otra calle.
- [ ] **Componer un motivo musical de la verbena.** Probar tres arreglos para preparación, asalto y amanecer. Durante una brecha, las señales de peligro deben seguir oyéndose sobre música y disparos. Repetir con auriculares y altavoces.
  - Hecho: el mismo motivo suena como vals de verbena de día, como pulso tenso de noche (con una capa de combate que crece con los brotados) y lento con campanas al amanecer y tras la victoria. Una brecha nueva o los golpes a la casa suenan con una alarma y bajan la música unos segundos.
  - Falta escucharlo con auriculares y altavoces.
- [ ] **Hacer accesible la información bajo presión.** Acompañar las alarmas por sonido con texto e iconos, ajustar tamaño de interfaz y ofrecer reducción de destellos y sacudidas. Completar una reparación y un rescate con el audio silenciado.
  - Hecho: brechas, golpes a la casa, estandartes atacados, caídos, vecinos atrapados, piezas y suministros tienen texto y marca en pantalla además de sonido. Hay tamaño de interfaz y opciones para quitar sacudidas y destellos (luces, explosiones, relámpagos y pulso de daño).
  - Falta la prueba con el audio silenciado.

## Salida comercial · Pasar de la candidata a la versión de venta

- [ ] **Cerrar el alcance de la versión 1.0.** Tras probar el final de partida, acordar modos, contenido, idiomas y plataformas que se ofrecerán al comprador. Asociar cada promesa de la ficha de tienda a una función verificable en la candidata.
- [ ] **Facilitar jugar con amigos desde casa.** Elegir el método de invitación de la tienda objetivo y probarlo entre dos conexiones domésticas. Cubrir invitación caducada, sala llena y versiones incompatibles con un mensaje que permita actuar.
  - Hecho para la conexión directa: el cliente envía su versión al unirse y el anfitrión responde con un motivo antes de cerrar.
    - «Versión distinta: el anfitrión usa la X y tú la Y».
    - «La partida está llena (4 de 4)».
    - «La partida ha terminado; espera a la revancha».
    - Si no hay respuesta, el mensaje indica revisar la IP, la partida y el puerto UDP 24680.
  - Verificado con `tests/join_test.gd`: tres clientes dentro, uno con versión antigua y un quinto.
  - Falta elegir la tienda y su sistema de invitaciones.
- [x] **Recuperar una sesión interrumpida.** El anfitrión (o quien juega en solitario) guarda en cada amanecer `user://partida.sav`, versionado y con copia anterior. El menú ofrece «Continuar partida» con la noche y los vecinos.
  - Al volver, cada vecino recupera por su nombre sus fichas, armas y mejoras, munición, botiquines, tracas, experiencia y oficio, aunque entre en otro orden. Quien es nuevo empieza de cero.
  - Se conservan territorio, defensas, materiales, comunidad, piezas y noche. Una pieza que se cargaba queda en el suelo.
  - Un guardado a medias recupera el anterior, y al terminar la partida se borra.
  - Verificado en `tests/checkpoint_test.gd`.
- [ ] **Fijar requisitos de PC a partir de mediciones.** Elegir equipos mínimo y recomendado, resolución y objetivo de fluidez tras medir la candidata. Publicar los ajustes usados y repetir el recorrido más exigente antes de etiquetar la versión.
- [ ] **Probar textos y menús en la distribución real.** Revisar tildes, textos largos, escalado de Windows y navegación por teclado en cada idioma anunciado. Llegar desde el arranque hasta una partida y regresar al menú en la resolución mínima admitida.
- [x] **Inventariar la edición basada en c897f26.** Revisados recursos del juego, sonido sintetizado, fuente del motor y plantilla estándar. El paquete incluye el [inventario de procedencia](distribution/licencias/Materiales.txt) y las licencias oficiales del motor y sus dependencias.
- [ ] **Auditar los derechos de los materiales.** Inventariar música, fuentes, modelos, texturas y dependencias con su procedencia, licencia y créditos. Verificar el permiso de distribución comercial para cada elemento incluido en el paquete.
- [ ] **Preparar una demo representativa.** Incluir una salida al barrio, una decisión de construcción y un asalto con cierre propio. Probar si alguien que termina la demo puede explicar qué ofrece la partida completa y qué le apetecería intentar después.
- [ ] **Enseñar la experiencia real en la tienda.** Preparar portada, capturas y un tráiler breve con exploración, cooperación y consecuencias de una brecha. Comparar la ficha con la versión descargable y verificar que refleja la cámara, la interfaz y el número de jugadores disponibles.
- [ ] **Celebrar una prueba cerrada antes de fijar fecha.** Invitar tanto a grupos de amigos como a jugadores solitarios. Registrar dónde abandonan, qué recuerdan al día siguiente y si eligen repetir voluntariamente. Corregir y volver a probar los dos obstáculos más repetidos.
- [x] **Abrir un canal para incidencias de la candidata.** Preparado el [formulario de GitHub](.github/ISSUE_TEMPLATE/fallo-de-partida.yml) con versión, modo de juego, reproducción y equipo. Aparecerá en el selector de incidencias al integrar la rama en la predeterminada.
- [ ] **Ensayar el primer parche.** Instalar la candidata, crear una partida guardada, actualizarla y cargarla de nuevo. Dejar preparados el canal de incidencias, las notas de versión y la recuperación si una actualización daña partidas.
- [ ] **Decidir la salida con una partida de principio a fin.** En el paquete exacto que se venderá, comprobar compra o descarga, instalación limpia, primera sesión, victoria, derrota, guardado y cooperativo. Resolver los fallos reproducibles que impidan completar cualquiera de esos recorridos antes de publicar.
