extends SceneTree
## Full-wave benchmark with the real renderer (not headless):
##   godot --path . -s tests/benchmark.gd [-- --calidades=0,2 --segundos=20 --enemigos=60]
## Plays the same scripted night for every graphics preset: four bot players, the
## opening defences of the session test and a constant crowd of brotados. Prints a
## table and saves it to user://benchmark.md (Godot's user data folder).
const Data = preload("res://game/data.gd")
const Map = preload("res://game/map.gd")
const NAMES = ["Baja", "Media", "Alta", "Ultra"]
var game
var qualities := [0, 2]
var seconds := 20.0
var crowd := 60
var qi := -1
var t := 0.0
var frames := PackedFloat32Array()
var cpu := PackedFloat32Array()
var gpu := PackedFloat32Array()
var rows := []
var last := 0

func _initialize():
	Engine.set_meta("sin_guardar", true)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--calidades="):
			qualities = []
			for q in a.substr(12).split(","): qualities.append(int(q))
		if a.begins_with("--segundos="): seconds = float(a.substr(11))
		if a.begins_with("--enemigos="): crowd = int(a.substr(11))
	call_deferred("launch")

func launch():
	game = load("res://game/main.tscn").instantiate()
	root.add_child(game)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	next_quality()

func next_quality():
	qi += 1
	if qi >= qualities.size():
		finish()
		return
	if game.mode != "": game.stop("")
	game.prefs.values.quality = qualities[qi]
	game.apply_settings(game.prefs.values)
	game.start("solo", 2, "", "Banco")
	var sim = game.sim
	for id in [2, 3, 4]: sim.join(id, id - 1, "Bot%d" % id)
	sim.materials = 200
	var plan := [[Vector2(-4.5, 5.5), 3], [Vector2(4.5, 5.5), 3], [Vector2(-5.5, -4.5), 3], [Vector2(5.5, -4.5), 3],
		[Vector2(0.5, 7.5), 2], [Vector2(-7.5, 0.5), 2], [Vector2(7.5, 0.5), 2], [Vector2(0.5, -6.5), 2], [Vector2(-1.5, 7.5), 5]]
	for item in plan:
		sim.players[1].p = item[0] + Vector2(0, 1.2)
		sim.act(1, "build", [item[1], sim.nav.cell_of(item[0])])
	sim.clock = 0.1
	sim.wave = 4
	game.local_pos = Vector2(0, 5)
	t = -3.0
	frames.clear()
	cpu.clear()
	gpu.clear()
	last = Time.get_ticks_usec()

func _process(dt):
	if game == null or qi >= qualities.size() or game.state.is_empty(): return false
	var now := Time.get_ticks_usec()
	var ft := (now - last) / 1000.0
	last = now
	var sim = game.sim
	for q in sim.players.values():
		q.hp = q.hpmax
		q.st = 0
	sim.core = sim.core_max
	sim.queue = [0]
	while sim.enemies.size() < crowd:
		var a := randf() * TAU
		sim.new_enemy(randi() % 7, Vector2(cos(a), sin(a)) * randf_range(12.0, 18.0), "base", true)
	var me:Dictionary = sim.players[1]
	var target := Vector2(0, 12)
	for e in sim.enemies.values():
		if e.p.distance_to(me.p) < target.distance_to(me.p): target = e.p
	game.autopilot = {"move": Vector2(sin(t * 0.5), 0) * 0.6, "buttons": 1, "cursor": target}
	for id in [2, 3, 4]:
		sim.players[id].fire = true
		sim.players[id].aim = (target - sim.players[id].p).normalized()
	t += dt
	if t < 0: return false
	frames.append(ft)
	cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()) + RenderingServer.get_frame_setup_time_cpu())
	gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
	if t >= seconds:
		var sorted := frames.duplicate()
		sorted.sort()
		var avg := 0.0
		for f in frames: avg += f
		avg /= frames.size()
		var p95:float = sorted[int(sorted.size() * 0.95)]
		var p99:float = sorted[int(sorted.size() * 0.99)]
		rows.append([NAMES[qualities[qi]], frames.size() / seconds, avg, p95, p99, sorted[-1], mean(cpu), mean(gpu),
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
			sim.enemies.size()])
		next_quality()
	return false

func mean(a:PackedFloat32Array) -> float:
	var s := 0.0
	for v in a: s += v
	return s / maxf(1, a.size())

func finish():
	var lines := []
	lines.append("# Banco de pruebas · oleada llena")
	lines.append("")
	lines.append("Equipo: %s · %s · %d núcleos · %s" % [OS.get_name(), OS.get_processor_name(), OS.get_processor_count(), RenderingServer.get_video_adapter_name()])
	lines.append("Motor: %s · renderizador %s · resolución %s · %d s por calidad" % [Engine.get_version_info().string, RenderingServer.get_current_rendering_method(), str(root.get_viewport().get_visible_rect().size), seconds])
	lines.append("")
	lines.append("| Calidad | FPS | Media ms | p95 ms | p99 ms | Máx ms | Render CPU ms | Render GPU ms | Física ms | Proceso ms | Llamadas | Primitivas | RAM MB | VRAM MB | Brotados |")
	lines.append("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |")
	for r in rows:
		lines.append("| %s | %.1f | %.2f | %.2f | %.2f | %.2f | %.2f | %.2f | %.2f | %.2f | %d | %d | %.0f | %.0f | %d |" % r)
	var text := "\n".join(lines)
	print(text)
	var f := FileAccess.open("user://benchmark.md", FileAccess.WRITE)
	if f:
		f.store_string(text + "\n")
		print("\nGuardado en ", ProjectSettings.globalize_path("user://benchmark.md"))
	quit(0)
