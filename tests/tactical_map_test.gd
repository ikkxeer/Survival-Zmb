extends SceneTree
var failed := false

func check(value:bool,detail:String):
	if not value:
		push_error(detail)
		failed = true

func _initialize():
	call_deferred("run")

func key(code:Key):
	var input := InputEventKey.new()
	input.keycode = code
	input.pressed = true
	return input

func run():
	var game = load("res://game/main.tscn").instantiate()
	root.add_child(game)
	game.start("solo",1,"")
	var sim = game.sim
	var view = game.tactical
	game._unhandled_key_input(key(KEY_M))
	check(view.expanded,"M abre el plano durante la partida")
	var site:Vector2 = sim.CACHES[1]
	var pixel:Vector2 = view.map_point(site)
	check(view.covers(pixel) and view.world_point(pixel).is_equal_approx(site),"Proyección de los puestos")
	var click := InputEventMouseButton.new()
	click.position = pixel
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	game._input(click)
	check(sim.players[1].ping.is_equal_approx(site) and game.map_click,"El clic marca el puesto y consume el disparo")
	click.pressed = false
	click.position = Vector2.ZERO
	game._input(click)
	check(not game.map_click,"Soltar fuera del plano libera el disparo")
	sim.mark(1,Vector2.ZERO)
	check(sim.players[1].ping.is_equal_approx(site),"Se limita la frecuencia de señales")
	sim.tick(2)
	sim.mark(1,Vector2(INF,0))
	check(sim.players[1].ping.is_equal_approx(site),"Una coordenada inválida no desplaza la señal")
	sim.mark(1,Vector2(90,50))
	check(sim.players[1].ping==Vector2(15,13),"La señal queda dentro del barrio")
	sim.tick(9)
	check(not sim.players[1].has("ping"),"Las señales caducan")
	sim.gates[0].hp = 90
	view.update_state(sim.snapshot(),1)
	sim.gates[0].hp = 70
	view.update_state(sim.snapshot(),1)
	check(view.access_alerts.has(0),"El daño en el acceso sur aparece en el plano")
	sim.gates[0].hp = 0
	view.update_state(sim.snapshot(),1)
	check(view.access_alerts.has(0) and view.previous_hp[0]==0,"Una brecha sigue visible")
	sim.gates[0].hp = 90
	view.update_state(sim.snapshot(),1)
	check(view.access_alerts.is_empty(),"Reconstruir despeja el aviso")
	sim.join(2,2)
	sim.players[1].hp = 0
	game._unhandled_key_input(key(KEY_G))
	check(sim.players[1].ping==sim.players[1].p,"Los caídos pueden pedir rescate en su posición")
	game._unhandled_key_input(key(KEY_M))
	check(not view.expanded,"El plano se cierra")
	game.stop("")
	check(view.state.is_empty() and not view.expanded,"Salir limpia el plano")
	quit(1 if failed else 0)
