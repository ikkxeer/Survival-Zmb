extends SceneTree
## Plays several nights with simple bots to catch runtime errors and balance outliers.
## godot --headless -s tests/soak_test.gd [-- --semilla=N]   (semilla 1 por defecto: resultados comparables entre versiones)
const Match = preload("res://game/match.gd")
const Data = preload("res://game/data.gd")
const Map = preload("res://game/map.gd")

const POSTS = [Vector2(0, -5.5), Vector2(5, -0.5), Vector2(0, 4.5), Vector2(-5, -0.5)]    # norte, este, sur, oeste

static func post_of(g, id:int) -> Vector2:
	## Like players reading the day plan: spread over tonight's fronts, then over the other accesses.
	var order:Array = g.fronts.duplicate()
	for s in [2, 1, 3, 0]: if not s in order: order.append(s)
	var ids:Array = g.players.keys()
	var idx:int = ids.find(id)
	var home:Vector2 = POSTS[order[idx % order.size()]]
	# like players reading the breach warning: the closest one runs to the access being hit
	var hit := -1
	for s in 4: if g.alerts[s].house > 0 or g.alerts[s].breach: hit = s
	if hit >= 0:
		var best := -1
		var bd := 1e9
		for other in ids:
			var q:Dictionary = g.players[other]
			if q.st != 0: continue
			var d:float = q.p.distance_to(POSTS[hit])
			if d < bd:
				bd = d
				best = other
		if best == id: home = POSTS[hit]
	return home

static func route(g, from:Vector2, to:Vector2) -> Vector2:
	## Direction of the next step on a flow field towards `to` (one field per destination, kept by the grid).
	var goal:int = g.nav.cell_of(to)
	if goal < 0: return Vector2.ZERO
	var key := "bot%d" % goal
	if not g.nav.seeds.has(key): g.nav.seeds[key] = [goal]
	var next:int = g.nav.next_cell(key, 0, from)
	return Vector2.ZERO if next < 0 else (g.nav.center(next) - from).normalized()

static func shop(g, id:int, p:Dictionary):
	## Spend the day's tokens at the house: a carbine first, then its ammunition and tracas.
	if g.phase == Data.Phase.NIGHT or not g.near_shop(p.p): return
	if not p.guns.has(3):
		if p.coins >= Data.WEAPONS[3].price: g.act(id, "buy_gun", [3])
	elif p.res[3] < g.max_reserve(p, 3) / 2 and p.coins >= Data.WEAPONS[3].ammo_price: g.act(id, "ammo", [3])
	elif p.gun != 3: g.act(id, "switch", [3])
	if p.coins >= 30 and p.tr < 2: g.act(id, "buy_traca")

static func bot(g, id:int, dt:float):
	var p:Dictionary = g.players[id]
	if p.st != 0:
		if p.st == 1 and p.med > 0: g.act(id, "medkit")
		g.drive(id, p.p, p.aim, 0)
		return
	var target := Vector2.ZERO
	var best := 1e9
	for e in g.enemies.values():
		var d:float = e.p.distance_to(p.p)
		if d < best and e.state != 2 and (d < 2.0 or g.nav.clear_line(p.p, e.p)):    # only what it can actually hit
			best = d
			target = e.p
	var move := Vector2.ZERO
	var buttons := 0
	var aim:Vector2 = p.aim
	var home := post_of(g, id)
	if g.phase == Data.Phase.PREP and g.clock > 20:
		for i in g.loot.size():
			if g.loot[i]:
				home = Map.LOOT[i].p
				break
		buttons |= 2
	elif g.core < g.core_max - 20 and best >= 14:
		buttons |= 2
	move = (home - p.p).limit_length(1.0)
	if best < 14:
		aim = target - p.p
		buttons |= 1
		if best < 4: move = -aim.normalized()
		elif p.p.distance_to(home) < 3.0: move = Vector2.ZERO    # hold the post while shooting
		if best < 1.6: g.act(id, "melee")
	# a wall or a defence in between: follow a path like a player who knows the neighbourhood
	if best >= 4 and p.p.distance_to(home) > 1.5 and not (best < 14 and p.p.distance_to(home) < 3.0):
		var way := route(g, p.p, home)
		if way != Vector2.ZERO: move = way
	shop(g, id, p)
	# tracas for the Gigantón and the role ability once a fight is on, like a player would
	if best < 11 and p.tr > 0:
		for e in g.enemies.values():
			if e.k == Data.BOSS and e.p.distance_to(p.p) < 11 and e.get("rise", 0.0) <= 0:
				g.act(id, "grenade", [e.p])
				break
	if best < 8 and p.ab <= 0: g.act(id, "ability")
	if p.mag[p.gun] == 0:
		if p.res[p.gun] == 0: g.act(id, "switch", [0])
		else: g.act(id, "reload")
	var next_p:Vector2 = g.nav.move(p.p, move * g.player_speed(p) * dt, Match.PLAYER_R, 0)
	g.drive(id, next_p, aim, buttons)

func _initialize():
	var g := Match.new()
	for i in 4: g.join(i + 1, i, "Bot%d" % i)
	var seed := 1
	for a in OS.get_cmdline_user_args(): if a.begins_with("--semilla="): seed = int(a.split("=")[1])
	g.reseed(seed)
	print("semilla ", seed)
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
		for id in g.players: bot(g, id, dt)    # the bots' own path finding is not part of the game's cost
		var s := Time.get_ticks_usec()
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
