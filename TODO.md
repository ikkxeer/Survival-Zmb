# Prioridades de La última verbena

Objetivo de la próxima versión: que un grupo pueda descargar el juego, entrar en la misma casa y superar tres noches entendiendo por qué sobrevive o por qué pierde.

## Entregado en la rama de coordinación cooperativa

- [x] **Orientarse desde la calle.** M abre el plano con el norte fijo. Muestra jugadores, caídos, enemigos, casa, puestos y defensas a partir del estado real de la partida.
- [x] **Pedir apoyo sin voz.** G marca tu posición. Un clic en el plano marca un destino. La señal aparece también en el mundo, indica la distancia y caduca a los ocho segundos. Los caídos pueden señalar dónde reanimarlos.
- [x] **Avisar de una brecha.** El HUD indica qué acceso recibe daño o se ha perdido. El plano resalta el mismo punto. Reparar o reconstruir despeja el aviso.
- [x] **Verificar la réplica.** Un anfitrión y tres clientes emiten señales y comprueban su posición, la construcción de una barricada y el gasto compartido. Las pruebas locales cubren caducidad, límites del mapa y cierre de sesión.

## P0 · Conseguir una versión que se pueda probar con amigos

- [ ] **Combinar las dos ramas en una candidata.** Cuando esté disponible la rama de gráficos y jugabilidad, comparar sus cambios en entrada, cámara, HUD y estado de partida. Probar disparo, giro, construcción, reanimación y señales con el plano abierto y cerrado.
- [ ] **Entregar un ZIP de Windows.** Preparar una exportación reproducible y abrirla en un PC sin Godot instalado. Dos equipos deben poder crear y unirse a una partida con esa misma descarga.
- [ ] **Sostener una sesión de tres noches.** Probar con uno, dos y cuatro jugadores, incluyendo una salida durante la oleada y una conexión con latencia. Registrar si divergen la vida de la casa, las fichas o las defensas y si el equipo puede seguir jugando.
- [ ] **Medir una oleada llena.** Registrar CPU, GPU, memoria y tiempos de fotograma con 48 enemigos y las dos opciones gráficas en un PC identificado. Repetir el mismo recorrido tras integrar los cambios visuales.

## P1 · Mejorar las decisiones que se toman durante una noche

- [ ] **Validar la lectura de las brechas con jugadores.** En una prueba sin instrucciones, comprobar si otro jugador llega al acceso anunciado y lo repara. Medir el tiempo desde el aviso hasta la reparación.
- [ ] **Afinar la primera noche.** Observar a un jugador nuevo desde el menú hasta el amanecer. Anotar cuándo encuentra la primera caja, qué construye y si entiende el coste de conquistar. Corregir el primer bloqueo observado y repetir.
- [ ] **Diferenciar las armas al oído y al disparar.** Coordinar con la rama de jugabilidad el sonido, la animación y la lectura del impacto de cada arma. Probar una defensa cercana y otra a distancia con los tres modelos.
- [ ] **Afinar los ataques por varias calles.** Registrar por dónde llega cada grupo y qué defensa elige atacar. Probar al menos dos preparaciones distintas que permitan superar la misma oleada.
- [ ] **Dar opciones de comodidad.** Sensibilidad de cámara, volumen de efectos y controles reasignables. Verificar que se conservan al reiniciar y que la ayuda muestra las teclas elegidas.

## P2 · Ampliar el barrio después de validar el núcleo

- [ ] **Primer rescate jugable.** Escoltar a un vecino desde un puesto hasta la casa, con recompensa compartida y resolución tanto si llega como si cae.
- [ ] **Primer jefe de barrio.** Introducir un ataque reconocible que el equipo pueda anticipar y contrarrestar con dos estrategias.
- [ ] **Progresión entre partidas.** Probar un desbloqueo por rol, guardado local versionado y recuperación tras cerrar el juego durante el guardado.
