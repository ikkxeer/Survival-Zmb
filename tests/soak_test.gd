extends SceneTree
## Plays several nights with simple bots to catch runtime errors and balance outliers.
## godot --headless -s tests/soak_test.gd
const Match = preload("res://game/match.gd")
const Data = preload("res://game/data.gd")
const Map = preload("res://game/map.gd")

func bot(g, id:int, dt:float):
	var p:Dictionary = g.players[id]
	if p.st != 0:
		if p.st == 1 and p.med > 0: g.act(id, "medkit")
		g.drive(id, p.p, p.aim, 0)
		return
	var target := Vector2.ZERO
	var best := 1e9
	for e in g.enemies.values():
		var d:float = e.p.distance_to(p.p)
		if d < best and e.state != 2:
			best = d
			target = e.p
	var move := Vector2.ZERO
	var buttons := 0
	var aim:Vector2 = p.aim
	if best < 14:
		aim = target - p.p
		buttons |= 1
		if best < 4: move = -aim.normalized()
		if best < 1.6: g.act(id, "melee")
	else:
		var posts := [Vector2(0,4.5), Vector2(5,-0.5), Vector2(0,-5.5), Vector2(-5,-0.5)]
		var home:Vector2 = posts[(id - 1) % 4]
		if g.core < g.core_max - 20:
			buttons |= 2
		if g.phase == Data.Phase.PREP and g.clock > 20:
			for i in g.loot.size():
				if g.loot[i]:
					home = Map.LOOT[i].p
					break
			buttons |= 2
		move = (home - p.p).limit_length(1.0)
	if g.players[id].mag[p.gun] == 0: g.act(id, "reload")
	var next:Vector2 = g.nav.move(p.p, move * g.player_speed(p) * dt, Match.PLAYER_R, 0)
	g.drive(id, next, aim, buttons)

func _initialize():
	var g := Match.new()
	for i in 4: g.join(i + 1, i, "Bot%d" % i)
	var dt := 1.0 / 30.0
	var t0 := Time.get_ticks_msec()
	var frames := 0
	var worst := 0
	# a ring of defences around the house
	var spots := [Vector2(-4.5,4.5), Vector2(4.5,4.5), Vector2(-5.5,-1.5), Vector2(5.5,-1.5), Vector2(0.5,6.5), Vector2(-1.5,-5.5)]
	var kinds := [Data.S_TURRET, Data.S_COIL, Data.S_WALL, Data.S_WALL, Data.S_LIGHT, Data.S_GEN]
	g.materials = 100
	for i in spots.size():
		g.players[1].p = spots[i] + Vector2(0, 1.2)
		g.act(1, "build", [kinds[i], g.nav.cell_of(spots[i])])
	g.players[1].p = Map.PLAYER_SPAWN
	g.act(1, "build", [Data.S_WIRE, g.nav.cell_of(Vector2(2.5, 8.5))])
	g.act(1, "build", [Data.S_MINE, g.nav.cell_of(Vector2(-2.5, 8.5))])
	g.act(1, "build", [Data.S_BENCH, g.nav.cell_of(Vector2(6.5, 2.5))])
	print("structures built: ", g.structures.size())
	var last_wave := 0
	while g.wave < 8 and g.phase != Data.Phase.OVER and frames < 30 * 60 * 25:
		var s := Time.get_ticks_usec()
		for id in g.players: bot(g, id, dt)
		g.tick(dt)
		if frames % 2 == 0: g.snapshot()
		worst = maxi(worst, Time.get_ticks_usec() - s)
		if g.wave != last_wave:
			last_wave = g.wave
			print("t=%.0fs wave %d start: core %.0f mat %d kills %d coins %s structures %d" % [g.time, g.wave, g.core, g.materials, g.stats.kills, str(g.players.values().map(func(q): return q.coins)), g.structures.size()])
		frames += 1
		if g.phase == Data.Phase.PREP:
			for id in g.players:
				if g.players[id].st == 0 and frames % 300 == 0: g.act(id, "ready")
	print("reached wave %d, phase %s, kills %d, core %.0f, enemies %d" % [g.wave, Data.PHASE_NAMES[g.phase], g.stats.kills, g.core, g.enemies.size()])
	print("frames %d in %d ms, worst tick %.1f ms" % [frames, Time.get_ticks_msec() - t0, worst / 1000.0])
	for k in g.enemies:
		var e = g.enemies[k]
		if e.night: print("  night enemy kind %d at %s goal %s dist %d victim %d wind %.1f cd %.1f state %d" % [e.k, str(e.p), e.goal, g.nav.distance_at(e.goal, e.mode, e.p), e.victim, e.wind, e.cd, e.state])
	var bytes := var_to_bytes(g.snapshot())
	print("snapshot %d bytes, compressed %d" % [bytes.size(), bytes.compress(FileAccess.COMPRESSION_DEFLATE).size()])
	quit(0 if g.wave >= 3 else 1)
