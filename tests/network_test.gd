extends SceneTree
## Replication check with real ENet processes. One host and up to three clients:
##   godot --headless -s tests/network_test.gd -- --host
##   godot --headless -s tests/network_test.gd          (x3, within 15 s)
## Each client builds a barricade; everyone must see all of them and the client predictions.
const Data = preload("res://game/data.gd")
var game
var elapsed := 0.0
var host:bool
var expected := 4
var built := false
var done := false

func _initialize():
	call_deferred("launch")

func launch():
	game = load("res://game/main.tscn").instantiate()
	root.add_child(game)
	host = "--host" in OS.get_cmdline_user_args()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--players="): expected = int(a.substr(10))
	game.start("host" if host else "join", 0 if host else 2, "127.0.0.1", "Host" if host else "Cliente")

func _process(dt):
	if game == null or done: return false
	elapsed += dt
	if elapsed > 25:
		push_error("No se recibió el estado cooperativo esperado")
		quit(1)
		return false
	var s:Dictionary = game.state
	if s.is_empty() or s.pl.size() != expected: return false
	var me:int = game.my_id()
	if not host and not built:
		built = true
		var slot:int = s.pl[me].slot
		var c:int = game.sim.nav.cell_of(Vector2(-3.5 + slot * 2.0, 6.5))
		game.local_pos = Vector2(-3.5 + slot * 2.0, 8.0)
		game.send_action("build", [Data.S_WALL, c])
	var walls:int = s.st.size() / 8
	if walls >= expected - 1:
		done = true
		print("%s ve %d barricadas y %d vecinos" % ["Anfitrión" if host else "Cliente", walls, s.pl.size()])
		create_timer(2.0 if host else 0.5).timeout.connect(func(): quit(0))
	return false
