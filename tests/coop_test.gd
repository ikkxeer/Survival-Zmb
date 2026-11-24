extends SceneTree
## Team coordination: map projection, signals by key and by map click, limits,
## expiry, breach warnings and cleanup.   godot --headless -s tests/coop_test.gd
const Data = preload("res://game/data.gd")
const Map = preload("res://game/map.gd")
var failed := 0

func check(ok:bool, detail:String):
	if not ok:
		failed += 1
		push_error("FALLO: " + detail)
	else: print("ok  ", detail)

func key(code:int) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	return e

func _initialize():
	Engine.set_meta("sin_guardar", true)
	call_deferred("run")

func run():
	var game = load("res://game/main.tscn").instantiate()
	root.add_child(game)
	game.start("solo", 1, "", "Prueba")
	await process_frame
	await process_frame
	var sim = game.sim
	var ui = game.ui
	game._unhandled_input(key(KEY_M))
	check(game.map_open and ui.map_panel.visible, "M abre el plano durante la partida")
	await process_frame
	await process_frame
	var site:Vector2 = Map.SITES[1].beacon
	var r:Rect2 = ui.bigmap.get_global_rect()
	var pixel:Vector2 = r.position + (site - Vector2(-37, -33)) / Vector2(74, 66) * r.size
	var back = ui.bigmap_world(pixel)
	check(back != null and back.distance_to(site) < 0.01, "Proyección de las propiedades en el plano")
	var click := InputEventMouseButton.new()
	click.position = pixel
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	game._input(click)
	check(sim.players[1].ping != null and sim.players[1].ping.distance_to(site) < 0.01 and game.map_click, "El clic marca la propiedad y no dispara")
	click.pressed = false
	click.position = Vector2.ZERO
	game._input(click)
	check(not game.map_click, "Soltar el botón libera el disparo")
	sim.mark(1, Vector2.ZERO)
	check(sim.players[1].ping.distance_to(site) < 0.01, "Se limita la frecuencia de señales")
	sim.tick(2.0)
	sim.mark(1, Vector2(INF, 0))
	check(sim.players[1].ping.distance_to(site) < 0.01, "Una coordenada inválida no desplaza la señal")
	sim.mark(1, Vector2(90, 50))
	check(sim.players[1].ping == Map.BOUNDS.end, "La señal queda dentro del barrio")
	sim.tick(9.0)
	check(sim.players[1].ping == null, "Las señales caducan a los ocho segundos")
	# breaches
	sim.materials = 30
	var cell:int = sim.nav.cell_of(Vector2(0.5, 7.5))
	sim.players[1].p = Vector2(0.5, 9.0)
	sim.act(1, "build", [Data.S_WALL, cell])
	sim.damage_structure(cell, 10.0)
	var br:Array = sim.snapshot().br
	check(br[2 * 3] > 0 and br[2 * 3 + 1] == 0, "El daño en una defensa del sur se avisa")
	check(ui.alert_text(sim.snapshot()).contains("sur"), "El HUD nombra el acceso atacado")
	sim.damage_structure(cell, 999.0)
	check(sim.snapshot().br[7] == 1, "Una defensa destruida abre una brecha")
	check(ui.alert_text(sim.snapshot()).contains("Brecha al sur"), "La brecha sigue visible")
	sim.tick(5.0)
	check(sim.snapshot().br[7] == 1, "La brecha no caduca sola")
	sim.act(1, "build", [Data.S_WALL, cell])
	check(sim.snapshot().br[7] == 0, "Reconstruir despeja el aviso")
	var e:Dictionary = sim.new_enemy(0, Vector2(4.5, 0.0), "base", true)
	sim.damage_core(5.0, e.p)
	check(ui.alert_text(sim.snapshot()).contains("casa por el este"), "Los golpes a la casa indican el acceso")
	sim.enemies.clear()
	# fallen players can call for help where they lie
	sim.join(2, 2, "Compi")
	sim.players[1].ping_left = 0.0
	sim.hurt_player(sim.players[1], 999.0)
	game._unhandled_input(key(KEY_G))
	check(sim.players[1].ping == sim.players[1].p, "Los caídos piden rescate en su posición")
	game._unhandled_input(key(KEY_M))
	check(not game.map_open, "El plano se cierra")
	game.stop("")
	check(not ui.map_panel.visible and game.state.is_empty(), "Salir limpia el plano y la partida")
	print("%d fallos" % failed)
	quit(1 if failed else 0)
