extends SceneTree
## One process of a three-night cooperative session played by bots.
## Launched by tests/run_session.py; it can also be started by hand:
##   godot --headless -s tests/session_test.gd -- --host
##   godot --headless -s tests/session_test.gd -- [--latencia=150] [--salir-noche=2]
const Data = preload("res://game/data.gd")
const Map = preload("res://game/map.gd")
const P := Data.Phase
var game
var host := false
var leave_night := 0
var nights := 3
var elapsed := 0.0
var last_ready_wave := 0
var summary_t := -1.0
var done := false
var seeded := false

func _initialize():
	for a in OS.get_cmdline_user_args():
		if a == "--host": host = true
		if a.begins_with("--salir-noche="): leave_night = int(a.substr(14))
		if a.begins_with("--noches="): nights = int(a.substr(9))
	Engine.time_scale = 4.0
	call_deferred("launch")

func launch():
	game = load("res://game/main.tscn").instantiate()
	root.add_child(game)
	game.start("host" if host else "join", 2 if host else randi_range(0, 3), "127.0.0.1", "Anfitrión" if host else "Bot")

func _process(dt):
	if game == null or done: return false
	elapsed += dt / Engine.time_scale
	if elapsed > 900:
		print("ERROR tiempo agotado")
		quit(1)
		return false
	if game.mode == "" and elapsed > 5:
		print("ERROR sesión cerrada antes de tiempo")
		quit(1)
		return false
	var s:Dictionary = game.state
	if s.is_empty() or not s.pl.has(game.my_id()): return false
	if host and not seeded and elapsed > 4.0: seed_defences()
	if leave_night > 0 and s.w == leave_night and s.ph == P.NIGHT and s.en.size() >= 8 * 4:
		print("SALIDA noche %d con %d brotados en pie" % [s.w, s.en.size() / 8])
		game.stop("")
		done = true
		create_timer(0.5).timeout.connect(func(): quit(0))
		return false
	play(s)
	var finished:bool = (s.w > nights and s.ph == P.DAWN) or s.ph == P.OVER
	if finished:
		if summary_t < 0: summary_t = 0.0
		summary_t += dt
		if summary_t > 3.0: report(s)
	return false

func seed_defences():
	## The host prepares the same opening every run so sessions are comparable.
	seeded = true
	var sim = game.sim
	sim.materials += 60
	var plan := [[Vector2(-4.5, 5.5), 3], [Vector2(4.5, 5.5), 3], [Vector2(-5.5, -4.5), 3], [Vector2(5.5, -4.5), 3],
		[Vector2(0.5, 7.5), 2], [Vector2(-7.5, 0.5), 2], [Vector2(7.5, 0.5), 2], [Vector2(0.5, -6.5), 2]]
	var me:Dictionary = sim.players[1]
	for item in plan:
		me.p = item[0] + Vector2(0, 1.2)
		sim.act(1, "build", [item[1], sim.nav.cell_of(item[0])])
	me.p = Map.PLAYER_SPAWN

func play(s:Dictionary):
	var me:Dictionary = s.pl[game.my_id()]
	var pos:Vector2 = game.local_pos if game.local_pos != Vector2.INF else me.p
	if me.st == 1 and me.med > 0: game.send_action("medkit")
	if s.ph == P.PREP and last_ready_wave != s.w and not me.ready:
		last_ready_wave = s.w
		game.send_action("ready")
	var posts := [Vector2(0, 4.2), Vector2(4.2, -0.5), Vector2(0, -4.6), Vector2(-4.2, -0.5)]
	var post:Vector2 = posts[me.slot % 4]
	var best := Vector2.INF
	var bd := 13.0
	var en:PackedFloat32Array = s.en
	for i in range(0, en.size(), 8):
		if int(en[i + 6]) & 4 != 0: continue
		var p := Vector2(en[i + 2], en[i + 3])
		var d := p.distance_to(pos)
		if d < bd:
			bd = d
			best = p
	var move := Vector2.ZERO
	var buttons := 0
	var cursor := pos + Vector2(0, 3)
	if best != Vector2.INF:
		cursor = best
		buttons |= 1
		if bd < 3.0: move = (pos - best).normalized()
	if move == Vector2.ZERO and pos.distance_to(post) > 0.8: move = (post - pos).normalized()
	if s.ph == P.NIGHT and s.core < s.cmax - 40 and best == Vector2.INF: buttons |= 2
	game.autopilot = {"move": move, "buttons": buttons, "cursor": cursor}

func report(s:Dictionary):
	done = true
	var coins := {}
	for q in s.pl.values(): coins[q.name + str(q.slot)] = q.coins
	var out := {"rol": "anfitrion" if host else "cliente", "noche": s.w, "fase": Data.PHASE_NAMES[s.ph], "casa": snappedf(s.core, 0.1),
		"materiales": s.mat, "defensas": s.st.size() / 8, "jugadores": s.pl.size(), "fichas": coins, "derribos": s.stats.kills}
	print("RESUMEN " + JSON.stringify(out))
	create_timer(4.0 if host else 0.5).timeout.connect(func(): quit(0))
