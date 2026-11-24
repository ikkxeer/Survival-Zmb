extends SceneTree
## Joining problems give a message the player can act on.
##   godot --headless -s tests/join_test.gd -- --host        (waits for 5 joins)
##   godot --headless -s tests/join_test.gd -- [--version=x]  (each client prints what it saw)
var game
var host := false
var fake := ""
var t := 0.0
func _initialize():
	Engine.set_meta("sin_guardar", true)
	for a in OS.get_cmdline_user_args():
		if a == "--host": host = true
		if a.begins_with("--version="): fake = a.substr(10)
	call_deferred("go")
func go():
	game = load("res://game/main.tscn").instantiate()
	root.add_child(game)
	if fake != "": ProjectSettings.set_setting("application/config/version", fake)
	game.start("host" if host else "join", 0, "127.0.0.1", "Prueba")
func _process(dt):
	if game == null: return false
	t += dt
	if host:
		if t > 45: quit(0)
		return false
	if game.mode == "" and t > 1:
		print("MENSAJE " + game.ui.status.text)
		quit(0)
	elif not game.state.is_empty() and game.state.pl.has(game.my_id()) and t > 2:
		if t > 30:
			print("DENTRO")
			quit(0)
	elif t > 40:
		print("SIN RESPUESTA")
		quit(1)
	return false
