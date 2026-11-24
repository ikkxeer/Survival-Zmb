extends SceneTree
## Start one host and three clients as separate headless Godot processes.
var game
var elapsed := 0.0
var sent := false
var done := false
var marked := false
var host:bool
func _initialize():
	call_deferred("launch")
func launch():
	game = load("res://game/main.tscn").instantiate()
	root.add_child(game)
	host = "--host" in OS.get_cmdline_user_args()
	game.start("host" if host else "join",0 if host else 2,"127.0.0.1")

func _process(dt):
	if game == null: return false
	elapsed += dt
	if elapsed > 18:
		push_error("No se recibió el estado cooperativo esperado")
		quit(1)
		return false
	if done:
		if game.mode == "": quit(0)
		return false
	if game.state.is_empty() or game.state.players.size()!=4: return false
	if not marked:
		marked = true
		game.send_marker(game.state.players[game.multiplayer.get_unique_id()].p)
	for player in game.state.players.values():
		if not player.has("ping") or not player.ping.is_equal_approx(player.p): return false
	if host:
		# The four spawn points are within reach of the south build pad.
		if game.sim.gates[0].kind==1 and game.sim.wood==9:
			if not sent:
				sent = true
				create_timer(1.5).timeout.connect(func():
					game.stop("")
					quit(0)
				)
	else:
		if not sent:
			game.interact.rpc_id(1,"wall")
			sent = true
		if game.state.gates[0].kind==1 and game.state.wood==9:
			done = true
	return false
